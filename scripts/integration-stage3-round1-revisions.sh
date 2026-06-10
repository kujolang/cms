#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4466}"
TOKEN="${CMS_TEST_TOKEN:-stage3-round1-revisions-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage3_round1_revisions_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage3_round1_revisions_server.log"

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

echo "Starting Kujo CMS API for Stage 3 Round 1 revision checks..."
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

request "POST" "/v1/content-types" '{"type_key":"stories","label":"Stories","singular_label":"Story"}' "1"
assert_status "201" "create stories content type"

request "POST" "/v1/entries" '{"content_type_key":"stories","title":"Story One","slug":"story-one","status":"published","excerpt":"Story one excerpt","body":"Story one body"}' "1"
assert_status "201" "create story entry"
ENTRY_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries/${ENTRY_ID}/revisions" '{"note":"initial snapshot"}' "1"
assert_status "201" "create first revision snapshot"
assert_contains '"revision_note":"initial snapshot"' "first revision note"

request "POST" "/v1/entries/${ENTRY_ID}/revisions" '{"note":"manual checkpoint snapshot"}' "1"
assert_status "201" "create second revision snapshot"
assert_contains '"revision_note":"manual checkpoint snapshot"' "second revision note"

request "GET" "/v1/entries/${ENTRY_ID}/revisions"
assert_status "200" "list entry revisions"
assert_contains '"count":2' "revision count"
assert_contains '"revision_note":"manual checkpoint snapshot"' "revision ordering latest first"
assert_contains '"revision_note":"initial snapshot"' "revision history contains initial snapshot"

request "POST" "/v1/entries/999999/revisions" '{"note":"should fail"}' "1"
assert_status "404" "revision create not found"
assert_contains '"code":"not_found"' "revision create not found code"

echo "All Stage 3 Round 1 revision integration checks passed."
