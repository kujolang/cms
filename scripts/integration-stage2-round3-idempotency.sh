#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4297}"
TOKEN="${CMS_TEST_TOKEN:-stage2-idempotency-token}"
BASE_URL="http://127.0.0.1:${PORT}"
CONTENT_TYPE_KEY="idempotencynews${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_idempotency_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_idempotency_server.log"

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

if [[ ! -x "${KUJO_BIN_PATH}" ]]; then
	echo "Kujo runtime binary is not executable: ${KUJO_BIN_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "sqlite3 is required for idempotency integration checks"
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "node is required for idempotency integration checks"
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
	local idempotency_key="${5:-}"

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
	if [[ -n "${idempotency_key}" ]]; then
		curl_args+=( -H "Idempotency-Key: ${idempotency_key}" )
	fi
	if [[ -n "${data}" ]]; then
		curl_args+=( --data "${data}" )
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
		exit 1
	fi
	echo "[PASS] ${context}: status ${STATUS}"
}

assert_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" != *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to contain ${needle}"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}"
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

assert_sql_equals() {
	local sql="$1"
	local expected="$2"
	local context="$3"
	local value
	value="$(sqlite3 "${DB_PATH}" "${sql}")"
	if [[ "${value}" != "${expected}" ]]; then
		echo "[FAIL] ${context}: expected ${expected}, got ${value}"
		exit 1
	fi
	echo "[PASS] ${context}: ${value}"
}

echo "Starting Kujo CMS API for idempotency integration checks..."
(
	cd "${ROOT_DIR}"
	RUN_CMD=("${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff)
	if command -v stdbuf >/dev/null 2>&1; then
		RUN_CMD=(stdbuf -oL -eL "${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff)
	fi
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	CMS_AUDIT_LOG="true" \
	"${RUN_CMD[@]}" >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 60); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server process exited early."
		cat "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}\",\"label\":\"Idempotency News\",\"singular_label\":\"Idempotency News\"}" "1"
assert_status "201" "create content type"

CTYPE_KEY="idem-content-type-${PORT}"
CTYPE_BODY="{\"type_key\":\"idemtype${PORT}\",\"label\":\"Idempotency Type\",\"singular_label\":\"Idempotency Type\"}"
request "POST" "/v1/content-types" "${CTYPE_BODY}" "1" "${CTYPE_KEY}"
assert_status "201" "create content type with idempotency key"
CTYPE_ID="$(json_extract 'data.id')"

request "POST" "/v1/content-types" "${CTYPE_BODY}" "1" "${CTYPE_KEY}"
assert_status "201" "retry content type create with same idempotency key"
assert_contains '"replayed":true' "content type retry returns replay marker"
assert_contains "\"target_id\":\"${CTYPE_ID}\"" "content type retry target id preserved"

CTYPE_CONFLICT_BODY="{\"type_key\":\"idemtypeconflict${PORT}\",\"label\":\"Idempotency Type Conflict\",\"singular_label\":\"Idempotency Type Conflict\"}"
request "POST" "/v1/content-types" "${CTYPE_CONFLICT_BODY}" "1" "${CTYPE_KEY}"
assert_status "409" "content type idempotency conflict on changed payload"
assert_contains '"code":"idempotency_conflict"' "content type idempotency conflict code"

TAXONOMY_KEY="idem-taxonomy-${PORT}"
TAXONOMY_BODY="{\"taxonomy_key\":\"idemtaxonomy${PORT}\",\"label\":\"Idempotency Taxonomy\",\"hierarchical\":false}"
request "POST" "/v1/taxonomies" "${TAXONOMY_BODY}" "1" "${TAXONOMY_KEY}"
assert_status "201" "create taxonomy with idempotency key"
TAXONOMY_ID="$(json_extract 'data.id')"

request "POST" "/v1/taxonomies" "${TAXONOMY_BODY}" "1" "${TAXONOMY_KEY}"
assert_status "201" "retry taxonomy create with same idempotency key"
assert_contains '"replayed":true' "taxonomy retry returns replay marker"
assert_contains "\"target_id\":\"${TAXONOMY_ID}\"" "taxonomy retry target id preserved"

PLUGIN_KEY="idem-plugin-${PORT}"
PLUGIN_BODY="{\"plugin_key\":\"idemplugin${PORT}\",\"name\":\"Idempotency Plugin\",\"version\":\"1.0.0\"}"
request "POST" "/v1/plugins" "${PLUGIN_BODY}" "1" "${PLUGIN_KEY}"
assert_status "201" "create plugin with idempotency key"
PLUGIN_ID="$(json_extract 'data.id')"

request "POST" "/v1/plugins" "${PLUGIN_BODY}" "1" "${PLUGIN_KEY}"
assert_status "201" "retry plugin create with same idempotency key"
assert_contains '"replayed":true' "plugin retry returns replay marker"
assert_contains "\"target_id\":\"${PLUGIN_ID}\"" "plugin retry target id preserved"

TENANT_KEY="idem-tenant-${PORT}"
TENANT_BODY="{\"tenant_key\":\"idemtenant${PORT}\",\"name\":\"Idempotency Tenant\",\"status\":\"active\"}"
request "POST" "/v1/tenants" "${TENANT_BODY}" "1" "${TENANT_KEY}"
assert_status "201" "create tenant with idempotency key"
TENANT_ID="$(json_extract 'data.id')"

request "POST" "/v1/tenants" "${TENANT_BODY}" "1" "${TENANT_KEY}"
assert_status "201" "retry tenant create with same idempotency key"
assert_contains '"replayed":true' "tenant retry returns replay marker"
assert_contains "\"target_id\":\"${TENANT_ID}\"" "tenant retry target id preserved"

WORKSPACE_KEY="idem-workspace-${PORT}"
WORKSPACE_BODY="{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"idemworkspace${PORT}\",\"name\":\"Idempotency Workspace\",\"status\":\"active\"}"
request "POST" "/v1/workspaces" "${WORKSPACE_BODY}" "1" "${WORKSPACE_KEY}"
assert_status "201" "create workspace with idempotency key"
WORKSPACE_ID="$(json_extract 'data.id')"

request "POST" "/v1/workspaces" "${WORKSPACE_BODY}" "1" "${WORKSPACE_KEY}"
assert_status "201" "retry workspace create with same idempotency key"
assert_contains '"replayed":true' "workspace retry returns replay marker"
assert_contains "\"target_id\":\"${WORKSPACE_ID}\"" "workspace retry target id preserved"

CREATE_KEY="idem-create-${PORT}"
ENTRY_CREATE_BODY="{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Idempotent Entry\",\"slug\":\"idempotent-entry\",\"status\":\"draft\",\"body\":\"idempotent body\"}"
request "POST" "/v1/entries" "${ENTRY_CREATE_BODY}" "1" "${CREATE_KEY}"
assert_status "201" "create entry with idempotency key"
ENTRY_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" "${ENTRY_CREATE_BODY}" "1" "${CREATE_KEY}"
assert_status "201" "retry create with same idempotency key"
assert_contains '"replayed":true' "create retry returns replay marker"
assert_contains "\"target_id\":\"${ENTRY_ID}\"" "create retry target id preserved"

assert_sql_equals "SELECT COUNT(*) FROM entries WHERE content_type_key = '${CONTENT_TYPE_KEY}' AND slug = 'idempotent-entry';" "1" "duplicate create does not duplicate writes"

ENTRY_CREATE_CONFLICT_BODY="{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Idempotent Entry Changed\",\"slug\":\"idempotent-entry-changed\",\"status\":\"draft\",\"body\":\"idempotent body changed\"}"
request "POST" "/v1/entries" "${ENTRY_CREATE_CONFLICT_BODY}" "1" "${CREATE_KEY}"
assert_status "409" "same key with different payload is rejected"
assert_contains '"code":"idempotency_conflict"' "idempotency conflict code"

DELETE_KEY="idem-delete-${PORT}"
request "DELETE" "/v1/entries/${ENTRY_ID}" "" "1" "${DELETE_KEY}"
assert_status "200" "delete entry with idempotency key"

request "DELETE" "/v1/entries/${ENTRY_ID}" "" "1" "${DELETE_KEY}"
assert_status "200" "retry delete with same idempotency key"
assert_contains '"replayed":true' "delete retry returns replay marker"
assert_contains "\"target_id\":\"${ENTRY_ID}\"" "delete retry target id preserved"

assert_sql_equals "SELECT COUNT(*) FROM entries WHERE id = ${ENTRY_ID};" "0" "idempotent delete does not fail on retry"
assert_sql_equals "SELECT COUNT(*) FROM idempotency_keys WHERE idempotency_key IN ('${CTYPE_KEY}','${TAXONOMY_KEY}','${PLUGIN_KEY}','${TENANT_KEY}','${WORKSPACE_KEY}','${CREATE_KEY}','${DELETE_KEY}');" "7" "idempotency keys persisted"

echo "Stage 2 Round 3 idempotency integration checks passed."
