#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4464}"
TOKEN="${CMS_TEST_TOKEN:-stage2-round2-cursor-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_round2_cursor_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_round2_cursor_server.log"

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

json_extract() {
	local path="$1"
	printf "%s" "${BODY}" | node -e '
		const fs = require("fs");
		const raw = fs.readFileSync(0, "utf8");
		const path = process.argv[1].split(".");
		let value = JSON.parse(raw);
		for (const key of path) {
			if (!value || !Object.prototype.hasOwnProperty.call(value, key)) {
				process.exit(2);
			}
			value = value[key];
		}
		if (typeof value === "object") {
			process.stdout.write(JSON.stringify(value));
		} else {
			process.stdout.write(String(value));
		}
	' "${path}"
}

echo "Starting Kujo CMS API for Stage 2 Round 2 cursor checks..."
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

request "POST" "/v1/content-types" '{"type_key":"events","label":"Events","singular_label":"Event"}' "1"
assert_status "201" "create events content type"

for i in 1 2 3 4 5 6; do
	payload="$(printf '{"content_type_key":"events","title":"Event %s","slug":"event-%s","status":"published","body":"Event %s body"}' "${i}" "${i}" "${i}")"
	request "POST" "/v1/entries" "${payload}" "1"
	assert_status "201" "create published event ${i}"
done

request "GET" "/v1/entries?content_type=events&sort_by=id&sort_dir=asc&pagination=cursor&limit=2"
assert_status "200" "cursor page 1 request"
assert_contains '"mode":"cursor"' "cursor mode payload"
PAGE1_FIRST_ID="$(json_extract 'data.items.0.id')"
PAGE1_LAST_ID="$(json_extract 'data.items.1.id')"
PAGE1_NEXT_CURSOR="$(json_extract 'data.pagination.next_cursor')"
if [[ "${PAGE1_NEXT_CURSOR}" != "${PAGE1_LAST_ID}" ]]; then
	echo "[FAIL] cursor page 1 next cursor alignment"
	echo "Response body: ${BODY}"
	exit 1
fi
echo "[PASS] cursor page 1 next cursor alignment"

request "GET" "/v1/entries?content_type=events&sort_by=id&sort_dir=asc&pagination=cursor&limit=2&cursor=${PAGE1_NEXT_CURSOR}"
assert_status "200" "cursor page 2 request"
PAGE2_FIRST_ID="$(json_extract 'data.items.0.id')"
PAGE2_LAST_ID="$(json_extract 'data.items.1.id')"
PAGE2_NEXT_CURSOR="$(json_extract 'data.pagination.next_cursor')"
if (( PAGE2_FIRST_ID <= PAGE1_LAST_ID )); then
	echo "[FAIL] cursor page progression: expected page 2 first id > page 1 last id"
	echo "Page1 last id: ${PAGE1_LAST_ID}, Page2 first id: ${PAGE2_FIRST_ID}"
	exit 1
fi
echo "[PASS] cursor page progression"

request "GET" "/v1/entries?content_type=events&sort_by=id&sort_dir=asc&pagination=cursor&limit=2&cursor=${PAGE2_NEXT_CURSOR}"
assert_status "200" "cursor page 3 request"
assert_contains '"next_cursor":null' "cursor terminal page"

request "GET" "/v1/entries?content_type=events&sort_by=id&sort_dir=asc&pagination=cursor&limit=2&cursor=abc"
assert_status "400" "invalid cursor validation"
assert_contains '"code":"invalid_cursor"' "invalid cursor error code"

request "GET" "/v1/entries?content_type=events&sort_by=title&sort_dir=asc&pagination=cursor&limit=2"
assert_status "400" "unsupported cursor sort"
assert_contains '"code":"unsupported_cursor_sort"' "unsupported cursor sort code"

request "GET" "/v1/entries?content_type=events&limit=2&offset=2"
assert_status "200" "offset mode compatibility"
assert_contains '"mode":"offset"' "offset mode payload"

echo "All Stage 2 Round 2 cursor integration checks passed."