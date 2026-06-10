#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4468}"
TOKEN="${CMS_TEST_TOKEN:-stage3-round3-scheduler-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage3_round3_scheduler_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage3_round3_scheduler_server.log"

rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true

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

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
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
	)

	if [[ "${auth}" == "1" ]]; then
		curl_args+=( -H "Authorization: Bearer ${TOKEN}" )
	fi

	if [[ -n "${data}" ]]; then
		curl_args+=( -H "Content-Type: application/json" --data "${data}" )
	fi

	STATUS="$(curl "${curl_args[@]}" "${BASE_URL}${path}")"
	BODY="$(cat "${TMP_BODY}")"
}

assert_status() {
	local expected="$1"
	local context="$2"
	if [[ "${STATUS}" != "${expected}" ]]; then
		echo "[FAIL] ${context}: expected status ${expected}, got ${STATUS}"
		echo "Response body: ${BODY}"
		tail -n 120 "${LOG_FILE}" || true
		exit 1
	fi
	echo "[PASS] ${context}: status ${STATUS}"
}

assert_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" != *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to contain: ${needle}"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}: contains expected text"
}

echo "Starting Kujo CMS API for Stage 3 Round 3 scheduler checks..."
(
	cd "${ROOT_DIR}"
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	CMS_AUDIT_LOG="true" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 50); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server process exited early."
		tail -n 120 "${LOG_FILE}" || true
		exit 1
	fi

	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "POST" "/v1/content-types" '{"type_key":"timed","label":"Timed","singular_label":"Timed Item"}' "1"
assert_status "201" "create timed content type"

request "POST" "/v1/entries" '{"content_type_key":"timed","title":"Due Publish","slug":"due-publish","status":"scheduled","excerpt":"Due publish excerpt","body":"Due publish body","published_at":0}' "1"
assert_status "201" "create due scheduled publish entry"

request "POST" "/v1/entries" '{"content_type_key":"timed","title":"Future Publish","slug":"future-publish","status":"scheduled","excerpt":"Future publish excerpt","body":"Future publish body","published_at":9999999999999}' "1"
assert_status "201" "create future scheduled publish entry"

request "POST" "/v1/entries" '{"content_type_key":"timed","title":"Due Unpublish","slug":"due-unpublish","status":"published","excerpt":"Due unpublish excerpt","body":"Due unpublish body","unpublish_at":0}' "1"
assert_status "201" "create due scheduled unpublish entry"

request "POST" "/v1/entries" '{"content_type_key":"timed","title":"Future Unpublish","slug":"future-unpublish","status":"published","excerpt":"Future unpublish excerpt","body":"Future unpublish body","unpublish_at":9999999999999}' "1"
assert_status "201" "create future scheduled unpublish entry"

request "POST" "/v1/entries/scheduler/run" '' "1"
assert_status "200" "run scheduler"
assert_contains '"published_count":1' "scheduler published count"
assert_contains '"unpublished_count":1' "scheduler unpublished count"

request "GET" "/v1/entries/by-slug/timed/due-publish"
assert_status "200" "fetch due publish entry"
assert_contains '"status":"published"' "due publish transitioned"

request "GET" "/v1/entries/by-slug/timed/future-publish"
assert_status "200" "fetch future publish entry"
assert_contains '"status":"scheduled"' "future publish remains scheduled"

request "GET" "/v1/entries/by-slug/timed/due-unpublish"
assert_status "200" "fetch due unpublish entry"
assert_contains '"status":"archived"' "due unpublish transitioned"
assert_contains '"unpublish_at":null' "due unpublish cleared unpublish_at"

request "GET" "/v1/entries/by-slug/timed/future-unpublish"
assert_status "200" "fetch future unpublish entry"
assert_contains '"status":"published"' "future unpublish remains published"

request "POST" "/v1/entries/scheduler/run" '' "1"
assert_status "200" "run scheduler second time"
assert_contains '"published_count":0' "second scheduler run publish count"
assert_contains '"unpublished_count":0' "second scheduler run unpublish count"

echo "All Stage 3 Round 3 scheduler integration checks passed."
