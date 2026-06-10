#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-55540}"
TOKEN="${CMS_TEST_TOKEN:-multitenant-integration-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_multitenant_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_multitenant_server.log"

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

if [[ ! -x "${KUJO_BIN_PATH}" ]]; then
	echo "Kujo runtime binary is not executable: ${KUJO_BIN_PATH}"
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

assert_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" != *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to contain ${needle}"
		echo "Response body: ${BODY}"
		tail -n 120 "${LOG_FILE}" || true
		exit 1
	fi
	echo "[PASS] ${context}: contains expected text"
}

assert_not_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" == *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to omit ${needle}"
		echo "Response body: ${BODY}"
		tail -n 120 "${LOG_FILE}" || true
		exit 1
	fi
	echo "[PASS] ${context}: omission confirmed"
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

echo "Starting CMS API for multi-tenant integration checks..."
(
	cd "${ROOT_DIR}"
	RUN_CMD=("${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo)
	if command -v stdbuf >/dev/null 2>&1; then
		RUN_CMD=(stdbuf -oL -eL "${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo)
	fi
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	CMS_TENANT_MAX_COUNT="2" \
	CMS_TENANT_WORKSPACE_MAX_COUNT="1" \
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

request "POST" "/v1/tenants" '{"tenant_key":"tenant-alpha","name":"Tenant Alpha"}' "1"
assert_status "201" "create tenant alpha"
TENANT_ALPHA_ID="$(json_extract 'data.id')"

request "POST" "/v1/tenants" '{"tenant_key":"tenant-beta","name":"Tenant Beta"}' "1"
assert_status "201" "create tenant beta"
TENANT_BETA_ID="$(json_extract 'data.id')"

request "POST" "/v1/tenants" '{"tenant_key":"tenant-gamma","name":"Tenant Gamma"}' "1"
assert_status "409" "reject tenant creation when tenant quota reached"
assert_contains '"code":"tenant_limit_reached"' "tenant quota error code"

request "POST" "/v1/tenants/update" "{\"tenant_id\":${TENANT_ALPHA_ID},\"name\":\"Tenant Alpha Updated\"}" "1"
assert_status "200" "update tenant alpha"
assert_contains '"name":"Tenant Alpha Updated"' "tenant alpha updated name"

SCOPED_ROLE_KEY="tenant_alpha_admin"
SCOPED_TOKEN="tenant-alpha-scoped-token"
SCOPED_TOKEN_HASH="$(printf "%s" "${SCOPED_TOKEN}" | shasum -a 256 | awk '{print $1}')"
SCOPED_PERMISSIONS_JSON='["cms.read","cms.write","tenant:'"${TENANT_ALPHA_ID}"'"]'
sqlite3 "${DB_PATH}" "INSERT INTO roles (role_key, name, permissions_json, is_system, created_at, updated_at) VALUES ('${SCOPED_ROLE_KEY}', 'Tenant Alpha Admin', '${SCOPED_PERMISSIONS_JSON}', 0, datetime('now'), datetime('now'));"
sqlite3 "${DB_PATH}" "INSERT INTO api_tokens (token_hash, label, role_key, is_active, created_at, updated_at, expires_at, last_used_at) VALUES ('${SCOPED_TOKEN_HASH}', 'tenant-alpha-scoped', '${SCOPED_ROLE_KEY}', 1, datetime('now'), datetime('now'), NULL, NULL);"

ORIGINAL_TOKEN="${TOKEN}"
TOKEN="${SCOPED_TOKEN}"

request "GET" "/v1/tenants" '' "1"
assert_status "200" "scoped token tenant listing"
assert_contains '"tenant_key":"tenant-alpha"' "scoped tenant listing includes alpha"
assert_not_contains '"tenant_key":"tenant-beta"' "scoped tenant listing excludes beta"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_ALPHA_ID},\"workspace_key\":\"tenant-alpha-main\",\"name\":\"Tenant Alpha Main\"}" "1"
assert_status "201" "scoped token create workspace in own tenant"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_BETA_ID},\"workspace_key\":\"tenant-beta-forbidden\",\"name\":\"Tenant Beta Forbidden\"}" "1"
assert_status "403" "scoped token denied cross-tenant workspace create"
assert_contains '"code":"tenant_scope_denied"' "cross-tenant workspace denial code"

request "POST" "/v1/tenants/update" "{\"tenant_id\":${TENANT_BETA_ID},\"name\":\"Tenant Beta Scoped Update\"}" "1"
assert_status "403" "scoped token denied cross-tenant tenant update"
assert_contains '"code":"tenant_scope_denied"' "cross-tenant tenant update denial code"

request "POST" "/v1/tenants" '{"tenant_key":"tenant-delta","name":"Tenant Delta"}' "1"
assert_status "403" "scoped token denied global tenant create"
assert_contains '"code":"tenant_scope_denied"' "global tenant create denial code"

TOKEN="${ORIGINAL_TOKEN}"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_ALPHA_ID},\"workspace_key\":\"tenant-alpha-secondary\",\"name\":\"Tenant Alpha Secondary\"}" "1"
assert_status "409" "reject workspace creation when tenant workspace quota reached"
assert_contains '"code":"workspace_limit_reached"' "workspace quota error code"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_BETA_ID},\"workspace_key\":\"tenant-beta-main\",\"name\":\"Tenant Beta Main\"}" "1"
assert_status "201" "create tenant beta workspace"

request "POST" "/v1/tenants/disable" "{\"tenant_id\":${TENANT_BETA_ID}}" "1"
assert_status "200" "disable tenant beta"
assert_contains '"status":"disabled"' "tenant beta disabled status"

request "POST" "/v1/tenants/archive" "{\"tenant_id\":${TENANT_BETA_ID}}" "1"
assert_status "200" "archive tenant beta"
assert_contains '"status":"archived"' "tenant beta archived status"

request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_BETA_ID},\"workspace_key\":\"tenant-beta-secondary\",\"name\":\"Tenant Beta Secondary\"}" "1"
assert_status "409" "reject workspace creation for inactive tenant"
assert_contains '"code":"tenant_inactive"' "inactive tenant error code"

request "GET" "/v1/tenants" '' "1"
assert_status "200" "list tenants"
assert_contains '"tenant_key":"tenant-alpha"' "tenants include tenant alpha"
assert_contains '"tenant_key":"tenant-beta"' "tenants include tenant beta"
assert_contains '"status":"archived"' "tenants include archived status"

request "GET" "/v1/workspaces" '' "1"
assert_status "200" "list workspaces"
assert_contains '"workspace_key":"tenant-alpha-main"' "workspaces include tenant alpha workspace"
assert_contains '"workspace_key":"tenant-beta-main"' "workspaces include tenant beta workspace"

tenant_total="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM tenants;")"
workspace_total="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM workspaces;")"
tenant_archived="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM tenants WHERE status = 'archived';")"

if [[ "${tenant_total}" != "2" ]]; then
	echo "[FAIL] expected 2 tenants in DB, got ${tenant_total}"
	exit 1
fi
echo "[PASS] tenant row count: ${tenant_total}"

if [[ "${workspace_total}" != "2" ]]; then
	echo "[FAIL] expected 2 workspaces in DB, got ${workspace_total}"
	exit 1
fi
echo "[PASS] workspace row count: ${workspace_total}"

if [[ "${tenant_archived}" != "1" ]]; then
	echo "[FAIL] expected 1 archived tenant in DB, got ${tenant_archived}"
	exit 1
fi
echo "[PASS] archived tenant count: ${tenant_archived}"

echo "All multi-tenant integration checks passed."