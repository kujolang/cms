#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4465}"
TOKEN="${CMS_TEST_TOKEN:-stage2-round2-projection-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_round2_projection_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_round2_projection_server.log"

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

assert_not_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" == *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to not contain: ${needle}"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}: excludes unexpected text"
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

echo "Starting Kujo CMS API for Stage 2 Round 2 projection checks..."
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

request "POST" "/v1/content-types" '{"type_key":"notes","label":"Notes","singular_label":"Note"}' "1"
assert_status "201" "create notes content type"

request "POST" "/v1/taxonomies" '{"taxonomy_key":"topic","label":"Topic","description":"Topic taxonomy","hierarchical":false}' "1"
assert_status "201" "create topic taxonomy"
TAXONOMY_ID="$(json_extract 'data.id')"

request "POST" "/v1/taxonomies/${TAXONOMY_ID}/terms" '{"name":"Alpha","slug":"alpha"}' "1"
assert_status "201" "create alpha term"
TERM_ALPHA_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"notes","title":"Note One","slug":"note-one","status":"published","excerpt":"Note one excerpt","body":"Note one body"}' "1"
assert_status "201" "create note one"
ENTRY_ONE_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"notes","title":"Note Two","slug":"note-two","status":"published","excerpt":"Note two excerpt","body":"Note two body"}' "1"
assert_status "201" "create note two"

request "POST" "/v1/entries/${ENTRY_ONE_ID}/terms" '{"term_ids":['"${TERM_ALPHA_ID}"']}' "1"
assert_status "200" "assign alpha term"

request "GET" "/v1/entries?content_type=notes&sort_by=id&sort_dir=asc&fields=id,title,status&include=terms"
assert_status "200" "sparse fieldset with included terms"
assert_contains '"include_terms":true' "projection include_terms flag"
assert_contains '"fields":["id","title","status"]' "projection fields list"
assert_contains '"terms":[' "included terms payload"
assert_not_contains '"body":"Note one body"' "sparse fieldset excludes body"

request "GET" "/v1/entries?content_type=notes&sort_by=id&sort_dir=asc&include=terms"
assert_status "200" "include terms without sparse fields"
assert_contains '"include_terms":true' "include terms metadata"
assert_contains '"body":"Note one body"' "full item payload retained"
assert_contains '"slug":"alpha"' "included term slug"

request "GET" "/v1/entries?content_type=notes&fields=id,unknown"
assert_status "400" "invalid sparse field validation"
assert_contains '"code":"invalid_fields"' "invalid fields error code"

echo "All Stage 2 Round 2 projection integration checks passed."
