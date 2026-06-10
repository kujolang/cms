#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4394}"
TOKEN="${CMS_TEST_TOKEN:-audit-consistency-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_audit_consistency_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_audit_consistency_server.log"
RUN_TAG="$(date +%s)_$RANDOM"
CONTENT_TYPE_KEY="auditnews${RUN_TAG}"
ENTRY_SLUG="audit-entry-${RUN_TAG}"
TENANT_KEY="audit-tenant-${RUN_TAG}"
WORKSPACE_KEY="audit-workspace-${RUN_TAG}"
PLUGIN_KEY="audit-plugin-${RUN_TAG}"
TOKEN_LABEL="Audit Token ${RUN_TAG}"

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
STATUS=""
BODY=""

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
	rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true
}
trap cleanup EXIT

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

assert_audit_row() {
	local action="$1"
	local target_id="$2"
	local context="$3"
	local total
	total="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM audit_log WHERE action = '${action}' AND target_id = '${target_id}';")"
	if [[ "${total}" -lt 1 ]]; then
		echo "[FAIL] ${context}: missing audit row action='${action}' target_id='${target_id}'"
		echo "Available rows for action '${action}':"
		sqlite3 "${DB_PATH}" "SELECT action, target_id, status_code, method, path FROM audit_log WHERE action = '${action}' ORDER BY id DESC LIMIT 20;" || true
		echo "Recent audit rows:"
		sqlite3 "${DB_PATH}" "SELECT action, target_id, status_code, method, path FROM audit_log ORDER BY id DESC LIMIT 20;" || true
		exit 1
	fi
	echo "[PASS] ${context}: found action='${action}' target_id='${target_id}'"
}

echo "Starting Kujo CMS API for audit consistency integration checks..."
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

for _ in $(seq 1 50); do
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

request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}\",\"label\":\"Audit News\",\"singular_label\":\"Audit News\"}" "1"
assert_status "201" "create content type for audit entry"

request "POST" "/v1/entries" "{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Audit Entry\",\"slug\":\"${ENTRY_SLUG}\",\"status\":\"published\",\"body\":\"Audit body\"}" "1"
assert_status "201" "create entry"
ENTRY_ID="$(json_extract 'data.id')"

request "POST" "/v1/tenants" "{\"tenant_key\":\"${TENANT_KEY}\",\"name\":\"Audit Tenant\",\"status\":\"active\"}" "1"
assert_status "201" "create tenant"
TENANT_ID="$(json_extract 'data.id')"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"${WORKSPACE_KEY}\",\"name\":\"Audit Workspace\",\"status\":\"active\"}" "1"
assert_status "201" "create workspace"
WORKSPACE_ID="$(json_extract 'data.id')"

request "POST" "/v1/plugins" "{\"plugin_key\":\"${PLUGIN_KEY}\",\"name\":\"Audit Plugin\",\"version\":\"1.0.0\",\"status\":\"inactive\"}" "1"
assert_status "201" "create plugin"
PLUGIN_ID="$(json_extract 'data.id')"

request "POST" "/v1/auth/tokens" "{\"label\":\"${TOKEN_LABEL}\",\"role_key\":\"super_admin\",\"token\":\"audit-token-created-${RUN_TAG}\"}" "1"
assert_status "201" "create auth token"
TOKEN_ID="$(json_extract 'data.id')"

assert_audit_row "entry.create" "${ENTRY_ID}" "entry audit action"
assert_audit_row "tenant.create" "${TENANT_ID}" "tenant audit action"
assert_audit_row "workspace.create" "${WORKSPACE_ID}" "workspace audit action"
assert_audit_row "plugin.create" "${PLUGIN_ID}" "plugin audit action"
assert_audit_row "token.create" "${TOKEN_ID}" "token audit action"

echo "All audit consistency integration checks passed."
