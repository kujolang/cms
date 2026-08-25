#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4290}"
TOKEN="${CMS_TEST_TOKEN:-stage1-integration-token}"
ORIGINAL_TOKEN="${TOKEN}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage1_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage1_server.log"

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

dump_server_log() {
	if [[ -f "${LOG_FILE}" ]]; then
		echo "--- server log tail ---"
		tail -n 120 "${LOG_FILE}" || true
		echo "-----------------------"
	fi
}

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
		dump_server_log
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
		dump_server_log
		exit 1
	fi
	echo "[PASS] ${context}: contains expected text"
}

assert_not_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" == *"${needle}"* ]]; then
		echo "[FAIL] ${context}: expected response to omit: ${needle}"
		echo "Response body: ${BODY}"
		dump_server_log
		exit 1
	fi
	echo "[PASS] ${context}: secret not present"
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

echo "Starting CMS API for Stage 1 integration checks..."
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
	CMS_AUDIT_LOG="true" \
	"${RUN_CMD[@]}" >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 50); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server process exited early."
		echo "--- server log ---"
		cat "${LOG_FILE}" || true
		exit 1
	fi

	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "GET" "/health"
assert_status "200" "health endpoint"
assert_contains '"status":"ok"' "health payload"

request "GET" "/v1"
assert_status "200" "capabilities endpoint"
assert_contains '/v1/entries/by-slug/:content_type/:slug' "capabilities include slug lookup"

request "GET" "/v1/openapi.json"
assert_status "200" "openapi contract endpoint"
assert_contains '"openapi":"3.1.0"' "openapi contract version"
assert_contains '"/v1/entries"' "openapi contract paths"

request "GET" "/robots.txt"
assert_status "200" "robots endpoint"
assert_contains "Sitemap: ${BASE_URL}/sitemap.xml" "robots sitemap link"

request "GET" "/llms.txt"
assert_status "200" "llms endpoint"
assert_contains '/v1/entries/by-slug/{content_type}/{slug}' "llms slug guidance"

request "GET" "/.well-known/security.txt"
assert_status "200" "security.txt endpoint"
assert_contains "Contact:" "security.txt contact field"

request "GET" "/sitemap.xml"
assert_status "200" "sitemap endpoint"
assert_contains '<urlset' "sitemap xml structure"

request "GET" "/rss.xml"
assert_status "200" "rss endpoint"
assert_contains '<rss version="2.0">' "rss xml structure"

request "POST" "/v1/content-types" '{"type_key":"news","label":"News","singular_label":"News"}'
assert_status "401" "write requires auth"

request "POST" "/v1/content-types" '{"type_key":"news","label":"News","singular_label":"News","description":"News posts"}' "1"
assert_status "201" "create content type"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"!!!","status":"draft","body":"Invalid fallback slug"}' "1"
assert_status "400" "reject symbol-only title slug fallback"
assert_contains '"code":"invalid_slug"' "invalid slug code"

request "POST" "/v1/taxonomies" '{"taxonomy_key":"topic","label":"Topic","description":"Topic taxonomy"}' "1"
assert_status "201" "create taxonomy"
TAXONOMY_ID="$(json_extract 'data.id')"

request "POST" "/v1/taxonomies/${TAXONOMY_ID}/terms" '{"name":"Platform","slug":"platform","parent_id":99999}' "1"
assert_status "400" "reject invalid term parent"
assert_contains '"code":"invalid_parent_id"' "invalid parent code"

request "POST" "/v1/taxonomies/${TAXONOMY_ID}/terms" '{"name":"Platform","slug":"platform"}' "1"
assert_status "201" "create term"
TERM_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"Stage One Entry","slug":"stage-one-entry","status":"published","body":"Integration content"}' "1"
assert_status "201" "create entry"
ENTRY_ID="$(json_extract 'data.id')"

request "GET" "/v1/entries/by-slug/news/stage-one-entry"
assert_status "200" "entry slug lookup"
assert_contains '"id":'"${ENTRY_ID}" "entry slug response id"

request "POST" "/v1/entries/${ENTRY_ID}/terms" '{"term_ids":['"${TERM_ID}"',99999]}' "1"
assert_status "400" "reject invalid entry term IDs"
assert_contains '"code":"invalid_term_ids"' "invalid term id code"

request "POST" "/v1/entries/${ENTRY_ID}/terms" '{"term_ids":['"${TERM_ID}"']}' "1"
assert_status "200" "assign valid entry terms"
assert_contains '"entry_id":'"${ENTRY_ID}" "assigned terms payload"

request "POST" "/v1/plugins/99999/hooks" '{"hook_name":"publish","handler_url":"https://example.com/webhook","shared_secret":"supersecret"}' "1"
assert_status "404" "reject hook creation for missing plugin"

request "GET" "/v1/content-types?limit=1&offset=0"
assert_status "200" "content type pagination"
assert_contains '"limit":1' "content type pagination payload"

request "GET" "/v1/content-types?limit=1&offset=0&sort_by=label&sort_dir=desc"
assert_status "200" "content type sort query"
assert_contains '"sort_by":"label"' "content type sort metadata"

request "GET" "/v1/plugins?limit=1&offset=0" "" "1"
assert_status "200" "load seeded plugin for hook tests"
PLUGIN_ID="$(json_extract 'data.items.0.id')"

request "POST" "/v1/plugins/${PLUGIN_ID}/hooks" '{"hook_name":"entry.published","handler_url":"https://example.com/webhook","shared_secret":"supersecret-123","enabled":true}' "1"
assert_status "201" "create plugin hook"
assert_not_contains "shared_secret" "plugin hook create omits shared secret"

request "POST" "/v1/themes/99999/activate" '{}' "1"
assert_status "404" "reject theme activation for missing theme"

request "DELETE" "/v1/auth/tokens/99999" '' "1"
assert_status "404" "reject token deactivation for missing token"

request "GET" "/v1/media?limit=1&offset=0"
assert_status "200" "media pagination"
assert_contains '"limit":1' "media pagination payload"

request "GET" "/v1/media?limit=1&offset=0&sort_by=filename&sort_dir=desc"
assert_status "200" "media sort query"
assert_contains '"sort_by":"filename"' "media sort metadata"

request "GET" "/v1/menus?limit=1&offset=0"
assert_status "200" "menu pagination"
assert_contains '"limit":1' "menu pagination payload"

request "GET" "/v1/plugins?limit=1&offset=0" "" "1"
assert_status "200" "plugin pagination"
assert_contains '"limit":1' "plugin pagination payload"

request "GET" "/v1/themes?limit=1&offset=0"
assert_status "200" "theme pagination"
assert_contains '"limit":1' "theme pagination payload"

request "GET" "/v1/auth/roles?limit=1&offset=0" "" "1"
assert_status "200" "role pagination"
assert_contains '"limit":1' "role pagination payload"

request "POST" "/v1/tenants" '{"tenant_key":"stage1-tenant","name":"Stage1 Tenant","status":"active"}' "1"
assert_status "201" "create tenant"
TENANT_ID="$(json_extract 'data.id')"

request "POST" "/v1/tenants/update" '{"tenant_id":'"${TENANT_ID}"',"name":"Stage1 Tenant Updated","status":"active"}' "1"
assert_status "200" "update tenant"

request "POST" "/v1/workspaces" '{"tenant_id":'"${TENANT_ID}"',"workspace_key":"stage1-workspace","name":"Stage1 Workspace","status":"active"}' "1"
assert_status "201" "create workspace"

request "POST" "/v1/auth/tokens" '{"label":"Invalid Expiry Token","role_key":"super_admin","expires_at":"not-a-timestamp"}' "1"
assert_status "400" "reject invalid token expires_at format"
assert_contains '"code":"invalid_expires_at"' "invalid expires_at code"

request "POST" "/v1/auth/tokens" '{"label":"ISO Expiry Token","role_key":"super_admin","expires_at":"2030-01-01T00:00:00Z"}' "1"
assert_status "201" "create token with ISO expires_at"

request "POST" "/v1/auth/tokens" '{"label":"Expired Token","role_key":"super_admin","expires_at":1}' "1"
assert_status "201" "create already-expired token"
EXPIRED_TOKEN_SECRET="$(json_extract 'data.token_secret')"

TOKEN="${EXPIRED_TOKEN_SECRET}"
request "GET" "/v1/auth/tokens?limit=1&offset=0" '' "1"
assert_status "401" "expired token denied"
assert_contains 'Token expired' "expired token error"
TOKEN="${ORIGINAL_TOKEN}"

request "POST" "/v1/auth/tokens" '{"label":"Stage1 Lifecycle Token","role_key":"super_admin"}' "1"
assert_status "201" "create token with one-time reveal"
assert_contains '"token_secret":"' "token create reveal payload"
TOKEN_ROW_ID="$(json_extract 'data.id')"
TOKEN_CREATE_SECRET="$(json_extract 'data.token_secret')"

request "GET" "/v1/auth/tokens?limit=20&offset=0" '' "1"
assert_status "200" "token listing after create"
assert_not_contains "${TOKEN_CREATE_SECRET}" "token list omits one-time create secret"

request "PATCH" "/v1/auth/tokens/${TOKEN_ROW_ID}" '{"token":"stage1-rotated-token-secret-123456"}' "1"
assert_status "200" "rotate token using patch"
assert_contains '"token_secret":"' "token rotate reveal payload"
TOKEN_ROTATED_SECRET="$(json_extract 'data.token_secret')"
if [[ "${TOKEN_ROTATED_SECRET}" == "${TOKEN_CREATE_SECRET}" ]]; then
	echo "[FAIL] rotated token secret should differ from create secret"
	exit 1
fi

TOKEN="${TOKEN_ROTATED_SECRET}"
request "GET" "/v1/auth/tokens?limit=20&offset=0" '' "1"
assert_status "200" "token listing after rotated token use"
assert_not_contains "${TOKEN_ROTATED_SECRET}" "token list omits one-time rotate secret"

TOKEN_LAST_USED="$(sqlite3 "${DB_PATH}" "SELECT COALESCE(last_used_at, '') FROM api_tokens WHERE id = ${TOKEN_ROW_ID};")"
if [[ -z "${TOKEN_LAST_USED}" ]]; then
	echo "[FAIL] expected last_used_at to be set after rotated token usage"
	exit 1
fi
echo "[PASS] token last_used_at persisted after rotated token usage"

TOKEN="${ORIGINAL_TOKEN}"

request "GET" "/v1/auth/tokens?limit=1&offset=0" '' "1"
assert_status "200" "token pagination"
assert_contains '"limit":1' "token pagination payload"

ENTRY_CREATE_AUDIT_COUNT="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM audit_log WHERE action = 'entry.create';")"
if [[ "${ENTRY_CREATE_AUDIT_COUNT}" -lt 1 ]]; then
	echo "[FAIL] expected at least one entry.create audit row"
	exit 1
fi
echo "[PASS] entry.create audit row recorded"

TENANT_CREATE_AUDIT_COUNT="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM audit_log WHERE action = 'tenant.create';")"
if [[ "${TENANT_CREATE_AUDIT_COUNT}" -lt 1 ]]; then
	echo "[FAIL] expected at least one tenant.create audit row"
	exit 1
fi
echo "[PASS] tenant.create audit row recorded"

TENANT_UPDATE_AUDIT_COUNT="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM audit_log WHERE action = 'tenant.update';")"
if [[ "${TENANT_UPDATE_AUDIT_COUNT}" -lt 1 ]]; then
	echo "[FAIL] expected at least one tenant.update audit row"
	exit 1
fi
echo "[PASS] tenant.update audit row recorded"

WORKSPACE_CREATE_AUDIT_COUNT="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM audit_log WHERE action = 'workspace.create';")"
if [[ "${WORKSPACE_CREATE_AUDIT_COUNT}" -lt 1 ]]; then
	echo "[FAIL] expected at least one workspace.create audit row"
	exit 1
fi
echo "[PASS] workspace.create audit row recorded"

echo "All Stage 1 integration checks passed."
