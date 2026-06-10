#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4469}"
PRIMARY_TOKEN="${CMS_TEST_TOKEN:-stage3-round3-locking-token}"
PRIMARY_LOCK_SESSION="${CMS_TEST_LOCK_SESSION_PRIMARY:-editor-a}"
SECONDARY_LOCK_SESSION="${CMS_TEST_LOCK_SESSION_SECONDARY:-editor-b}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage3_round3_locking_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage3_round3_locking_server.log"

rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true

if [[ -n "${KUJO_BIN:-}" ]]; then
	KUJO_BIN_PATH="${KUJO_BIN}"
elif command -v kujo >/dev/null 2>&1; then
	KUJO_BIN_PATH="$(command -v kujo)"
elif [[ -x "${ROOT_DIR}/../kujo/target/debug/kujo" ]]; then
	KUJO_BIN_PATH="${ROOT_DIR}/../kujo/target/debug/kujo"
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
	local token="${4:-}"
	local lock_session="${5:-}"

	local curl_args=(
		-sS
		-o "${TMP_BODY}"
		-w "%{http_code}"
		-X "${method}"
	)

	if [[ -n "${token}" ]]; then
		curl_args+=( -H "Authorization: Bearer ${token}" )
	fi

	if [[ -n "${lock_session}" ]]; then
		curl_args+=( -H "X-Lock-Session: ${lock_session}" )
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

echo "Starting CMS API for Stage 3 Round 3 locking checks..."
(
	cd "${ROOT_DIR}"
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${PRIMARY_TOKEN}" \
	CMS_AUDIT_LOG="true" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${LOG_FILE}" 2>&1
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

request "POST" "/v1/content-types" '{"type_key":"collab","label":"Collaborative","singular_label":"Collaborative Item"}' "${PRIMARY_TOKEN}"
assert_status "201" "create collaborative content type"

request "POST" "/v1/entries" '{"content_type_key":"collab","title":"Locked Draft","slug":"locked-draft","status":"draft","excerpt":"Initial excerpt","body":"Initial body"}' "${PRIMARY_TOKEN}"
assert_status "201" "create lockable entry"
ENTRY_ID="$(json_extract 'data.id')"

request "POST" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"note\":\"editor_a_lock\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "200" "acquire entry lock with primary token"
assert_contains '"renewed":false' "lock acquisition result"
assert_contains '"locked_by":"session:' "lock owner recorded"
PRIMARY_LOCK_TOKEN="$(json_extract 'data.lock.lock_token')"

request "GET" "/v1/entry-locks/state?entry_id=${ENTRY_ID}"
assert_status "200" "fetch entry lock state"
assert_contains '"locked":true' "entry lock active"
assert_contains '"lock_note":"editor_a_lock"' "entry lock note"

request "POST" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"note\":\"editor_a_renewed\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "200" "renew entry lock with primary token"
assert_contains '"renewed":true' "lock renew result"
assert_contains '"lock_note":"editor_a_renewed"' "renewed lock note"
PRIMARY_LOCK_TOKEN="$(json_extract 'data.lock.lock_token')"

request "POST" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "400" "release requires lock token"
assert_contains '"code":"invalid_lock_token"' "missing lock token code"

request "POST" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"lock_token\":\"bad-token\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "409" "release rejects invalid lock token"
assert_contains '"code":"invalid_lock_token"' "invalid lock token code"

sqlite3 "${DB_PATH}" "UPDATE entry_locks SET expires_at = 1 WHERE entry_id = ${ENTRY_ID};"

request "POST" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${SECONDARY_LOCK_SESSION}\",\"note\":\"expired_takeover\"}" "${PRIMARY_TOKEN}" "${SECONDARY_LOCK_SESSION}"
assert_status "200" "secondary acquires expired lock"
assert_contains '"renewed":false' "expired lock replaced by new actor"
assert_contains '"lock_note":"expired_takeover"' "expired lock takeover note"
SECONDARY_LOCK_TOKEN="$(json_extract 'data.lock.lock_token')"

request "POST" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"lock_token\":\"${SECONDARY_LOCK_TOKEN}\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "409" "primary token cannot release lock owned by secondary"
assert_contains '"code":"entry_locked"' "primary release conflict code"

request "POST" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"force\":true}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "200" "primary token force releases lock owned by secondary"
assert_contains '"released":true' "force release result"
assert_contains '"forced":true' "force flag"

request "GET" "/v1/entry-locks/state?entry_id=${ENTRY_ID}"
assert_status "200" "fetch lock state after force release"
assert_contains '"locked":false' "entry unlocked after force release"

request "POST" "/v1/entries/${ENTRY_ID}/revisions" '{"note":"baseline for lock conflict"}' "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "201" "create revision snapshot for restore lock checks"
REVISION_ID="$(json_extract 'data.id')"

request "POST" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"note\":\"restore_guard_lock\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "200" "reacquire lock for restore conflict checks"
RESTORE_LOCK_TOKEN="$(json_extract 'data.lock.lock_token')"

request "POST" "/v1/entries/${ENTRY_ID}/revisions/${REVISION_ID}/restore" '' "${PRIMARY_TOKEN}" "${SECONDARY_LOCK_SESSION}"
assert_status "409" "secondary token blocked from restore while locked"
assert_contains '"code":"entry_locked"' "restore conflict code"

request "POST" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"${PRIMARY_LOCK_SESSION}\",\"lock_token\":\"${RESTORE_LOCK_TOKEN}\"}" "${PRIMARY_TOKEN}" "${PRIMARY_LOCK_SESSION}"
assert_status "200" "primary releases restore guard lock"

request "POST" "/v1/entries/${ENTRY_ID}/revisions/${REVISION_ID}/restore" '' "${PRIMARY_TOKEN}" "${SECONDARY_LOCK_SESSION}"
assert_status "200" "secondary restore succeeds after lock release"
assert_contains '"restored_from_revision_id":' "restore response includes revision source"

echo "All Stage 3 Round 3 locking integration checks passed."