#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_SMOKE_PORT:-4288}"
API_HOST="${CMS_API_HOST:-127.0.0.1}"
TOKEN="${CMS_SMOKE_TOKEN:-stage1-smoke-token}"
BASE_URL="http://${API_HOST}:${PORT}"
DB_PATH="${RESULTS_DIR}/smoke_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/smoke_server.log"

if [[ -n "${KUJO_BIN:-}" ]]; then
	KUJO_BIN_PATH="${KUJO_BIN}"
elif command -v ruff >/dev/null 2>&1; then
	KUJO_BIN_PATH="$(command -v ruff)"
elif [[ -x "${ROOT_DIR}/../ruff/target/debug/ruff" ]]; then
	KUJO_BIN_PATH="${ROOT_DIR}/../ruff/target/debug/ruff"
else
	echo "Unable to locate Kujo runtime binary. Set KUJO_BIN to continue."
	exit 1
fi

SERVER_PID=""
TMP_BODY="$(mktemp)"
TMP_HEADERS="$(mktemp)"

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
	rm -f "${TMP_HEADERS}" || true
	rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true
}
trap cleanup EXIT

STATUS=""
BODY=""

request() {
	local method="$1"
	local path="$2"
	local data="${3:-}"
	local auth="${4:-0}"

	local curl_args=(
		-sS
		-o "${TMP_BODY}"
		-w "%{http_code}"
		-X "${method}"
		-H "Content-Type: application/json"
	)

	if [[ "${auth}" == "1" ]]; then
		curl_args+=( -H "Authorization: Bearer ${TOKEN}" )
	fi
	if [[ -n "${data}" ]]; then
		curl_args+=( --data "${data}" )
	fi

	STATUS="$(curl "${curl_args[@]}" "${BASE_URL}${path}")"
	BODY="$(cat "${TMP_BODY}")"
}

request_head() {
	local path="$1"
	STATUS="$(curl -sS -I -o "${TMP_HEADERS}" -w "%{http_code}" "${BASE_URL}${path}")"
	BODY=""
}

assert_status() {
	local expected="$1"
	local context="$2"
	if [[ "${STATUS}" != "${expected}" ]]; then
		echo "[FAIL] ${context}: expected ${expected}, got ${STATUS}"
		echo "Response body: ${BODY}"
		tail -n 80 "${LOG_FILE}" || true
		exit 1
	fi
	echo "[PASS] ${context}"
}

assert_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" != *"${needle}"* ]]; then
		echo "[FAIL] ${context}: missing '${needle}'"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}"
}

echo "Starting Kujo CMS API smoke check..."
(
	cd "${ROOT_DIR}"
	CMS_API_HOST="${API_HOST}" \
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 50); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server exited before smoke checks."
		tail -n 80 "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "GET" "/health"
assert_status "200" "health"
assert_contains '"status":"ok"' "health payload"

request "GET" "/v1"
assert_status "200" "api root"
assert_contains '"resources"' "api root resources"

request_head "/health"
assert_status "200" "HEAD health"

request_head "/v1"
assert_status "200" "HEAD api root"

request_head "/robots.txt"
assert_status "200" "HEAD robots"

request_head "/rss.xml"
assert_status "200" "HEAD rss"

request "GET" "/robots.txt"
assert_status "200" "robots"

request "GET" "/.well-known/security.txt"
assert_status "200" "security.txt"

request "POST" "/v1/content-types" '{"type_key":"smoke","label":"Smoke","singular_label":"Smoke"}'
assert_status "401" "write auth required"

request "POST" "/v1/content-types" '{"type_key":"smoke","label":"Smoke","singular_label":"Smoke","description":"Smoke type"}' "1"
assert_status "201" "authorized write"

echo "Smoke checks passed."
