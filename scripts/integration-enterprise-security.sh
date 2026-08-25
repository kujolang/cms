#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

BASE_PORT="${CMS_SECURITY_TEST_PORT_BASE:-47280}"
PORT_ONE="${BASE_PORT}"
PORT_TWO="$((BASE_PORT + 1))"
PORT_THREE="$((BASE_PORT + 2))"
PORT_FOUR="$((BASE_PORT + 3))"
PORT_FIVE="$((BASE_PORT + 4))"

TOKEN="${CMS_TEST_TOKEN:-enterprise-security-token-123456789}"

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
STATUS=""
BODY=""

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
}
trap cleanup EXIT

stop_server() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	SERVER_PID=""
}

clear_port() {
	local port="$1"
	local existing_pids
	existing_pids="$(lsof -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
	if [[ -n "${existing_pids}" ]]; then
		for existing_pid in ${existing_pids}; do
			kill "${existing_pid}" >/dev/null 2>&1 || true
		done
	fi
}

request() {
	local method="$1"
	local base_url="$2"
	local path="$3"
	local data="${4:-}"
	local auth_header="${5:-}"
	local content_type="${6:-application/json}"

	local curl_args=(
		-sS
		-o "${TMP_BODY}"
		-w "%{http_code}"
		-X "${method}"
	)

	if [[ -n "${auth_header}" ]]; then
		curl_args+=( -H "Authorization: ${auth_header}" )
	fi

	if [[ -n "${data}" ]]; then
		if [[ -n "${content_type}" ]]; then
			curl_args+=( -H "Content-Type: ${content_type}" )
		fi
		curl_args+=( --data "${data}" )
	fi

	STATUS="$(curl "${curl_args[@]}" "${base_url}${path}")"
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

start_server() {
	local port="$1"
	local db_path="$2"
	local log_file="$3"
	local site_url="http://127.0.0.1:${port}"

	shift 3
	clear_port "${port}"

	rm -f "${db_path}" "${db_path}-wal" "${db_path}-shm" "${log_file}" || true

	(
		cd "${ROOT_DIR}"
		env \
			CMS_API_PORT="${port}" \
			CMS_SITE_URL="${site_url}" \
			CMS_DB_PATH="${db_path}" \
			CMS_API_TOKEN="${TOKEN}" \
			"$@" \
			"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${log_file}" 2>&1
	) &
	SERVER_PID=$!
	
	for _ in {1..50}; do
		if curl -fsS --max-time 1 "${site_url}/health" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.2
	done

	echo "[FAIL] server startup on ${site_url}"
	tail -n 120 "${log_file}" || true
	exit 1
}

echo "Running enterprise security integration checks..."

BASE_URL_ONE="http://127.0.0.1:${PORT_ONE}"
DB_ONE="${RESULTS_DIR}/integration_enterprise_security_${PORT_ONE}.db"
LOG_ONE="${RESULTS_DIR}/integration_enterprise_security_${PORT_ONE}.log"
start_server "${PORT_ONE}" "${DB_ONE}" "${LOG_ONE}" CMS_MAX_BODY_BYTES=128

EDITOR_TOKEN="enterprise-security-editor-token-123456789"
request "POST" "${BASE_URL_ONE}" "/v1/auth/tokens" "{\"label\":\"security editor\",\"role_key\":\"editor\",\"token\":\"${EDITOR_TOKEN}\"}" "Bearer ${TOKEN}"
assert_status "201" "super admin creates editor token"

request "POST" "${BASE_URL_ONE}" "/v1/auth/tokens" '{"label":"generated one","role_key":"viewer"}' "Bearer ${TOKEN}"
assert_status "201" "automatic token generation succeeds"
GENERATED_TOKEN_ONE="$(json_extract 'data.token_secret')"
if [[ "${GENERATED_TOKEN_ONE}" != cms_* || ${#GENERATED_TOKEN_ONE} -ne 52 ]]; then
	echo "[FAIL] generated token has unexpected format"
	exit 1
fi
echo "[PASS] generated token uses expected one-time secret format"

request "POST" "${BASE_URL_ONE}" "/v1/auth/tokens" '{"label":"generated two","role_key":"viewer"}' "Bearer ${TOKEN}"
assert_status "201" "second automatic token generation succeeds"
GENERATED_TOKEN_TWO="$(json_extract 'data.token_secret')"
if [[ "${GENERATED_TOKEN_ONE}" == "${GENERATED_TOKEN_TWO}" ]]; then
	echo "[FAIL] generated token secrets must be distinct"
	exit 1
fi
echo "[PASS] generated token secrets are distinct"

request "POST" "${BASE_URL_ONE}" "/v1/auth/tokens" '{"label":"blocked escalation","role_key":"super_admin","token":"blocked-escalation-token-123456789"}' "Bearer ${EDITOR_TOKEN}"
assert_status "403" "editor cannot mint super admin token"
assert_contains '"code":"forbidden"' "editor privilege escalation error"

request "GET" "${BASE_URL_ONE}" "/v1/users" "" "Bearer ${EDITOR_TOKEN}"
assert_status "403" "editor cannot administer users"

request "PATCH" "${BASE_URL_ONE}" "/v1/settings/registration" '{"mode":"open","default_role":"subscriber"}' "Bearer ${EDITOR_TOKEN}"
assert_status "403" "editor cannot administer registration settings"

request "POST" "${BASE_URL_ONE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"https://0177.1/webhook","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "octal loopback webhook host rejected"
assert_contains '"code":"unsafe_handler_url"' "octal loopback policy code"

request "POST" "${BASE_URL_ONE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"https://0x7f.1/webhook","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "hex loopback webhook host rejected"
assert_contains '"code":"unsafe_handler_url"' "hex loopback policy code"

request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":"stories","label":"Stories","singular_label":"Story"}' "Bearer ${TOKEN}"
assert_status "201" "create stories content type"

oversized_body="$(printf 'x%.0s' $(seq 1 1400))"
oversized_payload="{\"content_type_key\":\"stories\",\"title\":\"Oversize Story\",\"slug\":\"oversize-story\",\"status\":\"published\",\"excerpt\":\"Oversize excerpt\",\"body\":\"${oversized_body}\"}"
request "POST" "${BASE_URL_ONE}" "/v1/entries" "${oversized_payload}" "Bearer ${TOKEN}"
assert_status "400" "oversized body rejected"
assert_contains "Request body exceeds max size" "oversized body error"

request "POST" "${BASE_URL_ONE}" "/v1/entries" '{"content_type_key":"stories","title":"Bad Header Story","slug":"bad-header-story","status":"draft","body":"x"}' "Bearer ${TOKEN}" "text/plain"
assert_status "400" "invalid content type rejected"
assert_contains "Content-Type must be application/json" "invalid content type error"

request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":' "Bearer ${TOKEN}"
assert_status "400" "malformed JSON payload rejected"
assert_contains "Invalid JSON body" "malformed JSON error"

request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":"badtoken","label":"Bad Token","singular_label":"Bad Token"}' 'Bearer bad token!*'
assert_status "401" "malformed bearer token rejected"
assert_contains "Invalid bearer token format" "malformed token error"

long_token="$(printf 'a%.0s' $(seq 1 700))"
request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":"longtoken","label":"Long Token","singular_label":"Long Token"}' "Bearer ${long_token}"
assert_status "401" "oversized bearer token rejected"
assert_contains "Invalid bearer token format" "oversized token error"

request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":"replaybase","label":"Replay Base","singular_label":"Replay Base"}' "Bearer ${TOKEN}"
assert_status "201" "replay baseline mutation accepted"

request "POST" "${BASE_URL_ONE}" "/v1/content-types" '{"type_key":"replaybase","label":"Replay Base","singular_label":"Replay Base"}' "Bearer ${TOKEN}"
assert_status "409" "replayed duplicate mutation rejected"
assert_contains "create_failed" "replay duplicate conflict error"

request "POST" "${BASE_URL_ONE}" "/v1/tenants" '{"tenant_key":"x","name":"Invalid Tenant"}' "Bearer ${TOKEN}"
assert_status "400" "invalid tenant key rejected"
assert_contains '"code":"invalid_tenant_key"' "invalid tenant key code"

request "POST" "${BASE_URL_ONE}" "/v1/tenants" '{"tenant_key":"Bad Key","name":"Invalid Tenant"}' "Bearer ${TOKEN}"
assert_status "400" "malformed tenant key rejected"
assert_contains '"code":"invalid_tenant_key"' "malformed tenant key code"

request "POST" "${BASE_URL_ONE}" "/v1/tenants" '{"tenant_key":"tenant-security","name":"Tenant Security"}' "Bearer ${TOKEN}"
assert_status "201" "create tenant for workspace validation"
TENANT_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/workspaces" "{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"x\",\"name\":\"Invalid Workspace\"}" "Bearer ${TOKEN}"
assert_status "400" "invalid workspace key rejected"
assert_contains '"code":"invalid_workspace_key"' "invalid workspace key code"

request "POST" "${BASE_URL_ONE}" "/v1/workspaces" "{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"Bad Key\",\"name\":\"Invalid Workspace\"}" "Bearer ${TOKEN}"
assert_status "400" "malformed workspace key rejected"
assert_contains '"code":"invalid_workspace_key"' "malformed workspace key code"

request "POST" "${BASE_URL_ONE}" "/v1/tenants" '{"tenant_key":"tenant-secondary","name":"Tenant Secondary"}' "Bearer ${TOKEN}"
assert_status "201" "create second tenant for workspace key scope"
SECOND_TENANT_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/workspaces" "{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"primary\",\"name\":\"Primary Workspace\"}" "Bearer ${TOKEN}"
assert_status "201" "create tenant-scoped workspace key"

request "POST" "${BASE_URL_ONE}" "/v1/workspaces" "{\"tenant_id\":${SECOND_TENANT_ID},\"workspace_key\":\"primary\",\"name\":\"Secondary Workspace\"}" "Bearer ${TOKEN}"
assert_status "201" "reuse workspace key in another tenant"

request "POST" "${BASE_URL_ONE}" "/v1/media" '{"filename":"bad.png","storage_path":"/bad.png","size_bytes":-1}' "Bearer ${TOKEN}"
assert_status "400" "negative media size rejected"
assert_contains '"code":"invalid_size_bytes"' "negative media size code"

request "DELETE" "${BASE_URL_ONE}" "/v1/media/999999" "" "Bearer ${TOKEN}"
assert_status "404" "missing media delete returns not found"

request "POST" "${BASE_URL_ONE}" "/v1/taxonomies" '{"taxonomy_key":"hierarchy","label":"Hierarchy","hierarchical":true}' "Bearer ${TOKEN}"
assert_status "201" "create hierarchy taxonomy"
HIERARCHY_TAXONOMY_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/taxonomies/${HIERARCHY_TAXONOMY_ID}/terms" '{"name":"Parent","slug":"parent"}' "Bearer ${TOKEN}"
assert_status "201" "create parent term"
PARENT_TERM_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/taxonomies/${HIERARCHY_TAXONOMY_ID}/terms" "{\"name\":\"Child\",\"slug\":\"child\",\"parent_id\":${PARENT_TERM_ID}}" "Bearer ${TOKEN}"
assert_status "201" "create child term"
CHILD_TERM_ID="$(json_extract 'data.id')"

request "PATCH" "${BASE_URL_ONE}" "/v1/terms/${PARENT_TERM_ID}" "{\"parent_id\":${CHILD_TERM_ID}}" "Bearer ${TOKEN}"
assert_status "400" "taxonomy descendant cycle rejected"
assert_contains "descendant term" "taxonomy cycle error"

request "POST" "${BASE_URL_ONE}" "/v1/menus" '{"menu_key":"cycle-menu","name":"Cycle Menu","location":"footer"}' "Bearer ${TOKEN}"
assert_status "201" "create cycle test menu"
CYCLE_MENU_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/menus/${CYCLE_MENU_ID}/items" '{"label":"Parent","url":"/parent"}' "Bearer ${TOKEN}"
assert_status "201" "create parent menu item"
PARENT_MENU_ITEM_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/menus/${CYCLE_MENU_ID}/items" "{\"label\":\"Child\",\"url\":\"/child\",\"parent_id\":${PARENT_MENU_ITEM_ID}}" "Bearer ${TOKEN}"
assert_status "201" "create child menu item"
CHILD_MENU_ITEM_ID="$(json_extract 'data.id')"

request "PATCH" "${BASE_URL_ONE}" "/v1/menu-items/${PARENT_MENU_ITEM_ID}" "{\"parent_id\":${CHILD_MENU_ITEM_ID}}" "Bearer ${TOKEN}"
assert_status "400" "menu descendant cycle rejected"
assert_contains "descendant menu item" "menu cycle error"

request "GET" "${BASE_URL_ONE}" "/v1/themes/active"
assert_status "200" "load active theme before duplicate create"
ACTIVE_THEME_ID="$(json_extract 'data.id')"

request "POST" "${BASE_URL_ONE}" "/v1/themes" '{"theme_key":"starter","name":"Duplicate Starter","status":"active"}' "Bearer ${TOKEN}"
assert_status "409" "duplicate active theme rejected"

request "GET" "${BASE_URL_ONE}" "/v1/themes/active"
assert_status "200" "active theme preserved after failed create"
assert_contains "\"id\":${ACTIVE_THEME_ID}" "active theme identity preserved"

request "POST" "${BASE_URL_ONE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"bad","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "invalid plugin hook URL rejected"
assert_contains "handler_url" "invalid handler url message"

request "POST" "${BASE_URL_ONE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"http://example.com/webhooks/entry-created","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "insecure plugin hook http scheme rejected"
assert_contains '"code":"invalid_handler_url_scheme"' "plugin hook scheme policy code"

request "POST" "${BASE_URL_ONE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"https://127.0.0.1/webhooks/entry-created","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "internal plugin hook host rejected"
assert_contains '"code":"unsafe_handler_url"' "plugin hook host policy code"

request "POST" "${BASE_URL_ONE}" "/v1/entries" '{"content_type_key":"stories","title":"Lock Target","slug":"lock-target","status":"draft","body":"lock body"}' "Bearer ${TOKEN}"
assert_status "201" "create lock target entry"
ENTRY_ID="$(json_extract 'data.id')"

request "GET" "${BASE_URL_ONE}" "/v1/entries/${ENTRY_ID}"
assert_status "404" "anonymous draft detail is hidden"
assert_contains '"code":"not_found"' "anonymous draft detail error"

request "GET" "${BASE_URL_ONE}" "/v1/entries/by-slug/stories/lock-target"
assert_status "404" "anonymous draft slug lookup is hidden"

request "GET" "${BASE_URL_ONE}" "/v1/entries?status=draft"
assert_status "200" "anonymous entry list remains available"
if [[ "${BODY}" == *"lock-target"* ]]; then
	echo "[FAIL] anonymous entry list disclosed a draft"
	exit 1
fi
echo "[PASS] anonymous entry list excludes drafts"

request "GET" "${BASE_URL_ONE}" "/v1/entries/${ENTRY_ID}" "" "Bearer ${TOKEN}"
assert_status "200" "authenticated editor can read draft detail"

request "GET" "${BASE_URL_ONE}" "/v1/entries/${ENTRY_ID}/revisions"
assert_status "401" "anonymous revision history is denied"

request "POST" "${BASE_URL_ONE}" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"owner-session\",\"note\":\"security lock\"}" "Bearer ${TOKEN}" "text/plain"
assert_status "400" "unsupported content type rejected for lock acquire"
assert_contains "Content-Type must be application/json" "lock acquire content type error"

request "POST" "${BASE_URL_ONE}" "/v1/entry-locks/acquire" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"owner-session\",\"note\":\"security lock\"}" "Bearer ${TOKEN}"
assert_status "200" "acquire entry lock for ownership checks"
LOCK_TOKEN="$(json_extract 'data.lock.lock_token')"

request "POST" "${BASE_URL_ONE}" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"owner-session\"}" "Bearer ${TOKEN}"
assert_status "400" "missing lock token rejected"
assert_contains '"code":"invalid_lock_token"' "missing lock token code"

request "POST" "${BASE_URL_ONE}" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"owner-session\",\"lock_token\":\"wrong-token\"}" "Bearer ${TOKEN}"
assert_status "409" "wrong lock token rejected"
assert_contains '"code":"invalid_lock_token"' "wrong lock token code"

request "POST" "${BASE_URL_ONE}" "/v1/entry-locks/release" "{\"entry_id\":${ENTRY_ID},\"session_id\":\"other-session\",\"lock_token\":\"${LOCK_TOKEN}\"}" "Bearer ${TOKEN}"
assert_status "409" "cross-session lock release rejected"
assert_contains '"code":"entry_locked"' "cross-session release code"

stop_server

BASE_URL_TWO="http://127.0.0.1:${PORT_TWO}"
DB_TWO="${RESULTS_DIR}/integration_enterprise_security_${PORT_TWO}.db"
LOG_TWO="${RESULTS_DIR}/integration_enterprise_security_${PORT_TWO}.log"
start_server "${PORT_TWO}" "${DB_TWO}" "${LOG_TWO}" CMS_ALLOW_BOOTSTRAP_TOKEN=false

request "POST" "${BASE_URL_TWO}" "/v1/content-types" '{"type_key":"bootstrap-disabled","label":"Bootstrap Disabled","singular_label":"Bootstrap Disabled"}' "Bearer ${TOKEN}"
assert_status "401" "bootstrap token disabled"
assert_contains "Bootstrap token is disabled" "bootstrap disabled error"

stop_server

BASE_URL_THREE="http://127.0.0.1:${PORT_THREE}"
DB_THREE="${RESULTS_DIR}/integration_enterprise_security_${PORT_THREE}.db"
LOG_THREE="${RESULTS_DIR}/integration_enterprise_security_${PORT_THREE}.log"
TOKEN="change-me-in-production"
start_server "${PORT_THREE}" "${DB_THREE}" "${LOG_THREE}" CMS_ENV=production CMS_ALLOW_BOOTSTRAP_TOKEN=true CMS_ENFORCE_BOOTSTRAP_TOKEN_ROTATION=true

request "POST" "${BASE_URL_THREE}" "/v1/content-types" '{"type_key":"bootstrap-rotation","label":"Bootstrap Rotation","singular_label":"Bootstrap Rotation"}' "Bearer ${TOKEN}"
assert_status "401" "bootstrap token rotation enforced"
assert_contains "Bootstrap token is disabled" "bootstrap default token blocked"

stop_server

BASE_URL_FOUR="http://127.0.0.1:${PORT_FOUR}"
DB_FOUR="${RESULTS_DIR}/integration_enterprise_security_${PORT_FOUR}.db"
LOG_FOUR="${RESULTS_DIR}/integration_enterprise_security_${PORT_FOUR}.log"
TOKEN="aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
start_server "${PORT_FOUR}" "${DB_FOUR}" "${LOG_FOUR}" CMS_ENV=production CMS_ALLOW_BOOTSTRAP_TOKEN=true CMS_ENFORCE_BOOTSTRAP_TOKEN_ROTATION=true

request "POST" "${BASE_URL_FOUR}" "/v1/content-types" '{"type_key":"bootstrap-entropy","label":"Bootstrap Entropy","singular_label":"Bootstrap Entropy"}' "Bearer ${TOKEN}"
assert_status "401" "bootstrap token entropy classes enforced"
assert_contains "character classes" "bootstrap entropy error"

stop_server

BASE_URL_FIVE="http://127.0.0.1:${PORT_FIVE}"
DB_FIVE="${RESULTS_DIR}/integration_enterprise_security_${PORT_FIVE}.db"
LOG_FIVE="${RESULTS_DIR}/integration_enterprise_security_${PORT_FIVE}.log"
TOKEN="${CMS_TEST_TOKEN:-enterprise-security-token-123456789}"
start_server "${PORT_FIVE}" "${DB_FIVE}" "${LOG_FIVE}" CMS_PLUGIN_HOOK_URL_DENYLIST="localhost,127.*,10.*,172.*,192.168.*,169.254.*,0.0.0.0,::1,*.local,203.0.113.0/24"

request "POST" "${BASE_URL_FIVE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"https://203.0.113.25/webhook","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "400" "CIDR denylist blocks plugin hook host"
assert_contains '"code":"unsafe_handler_url"' "CIDR denylist unsafe code"

request "POST" "${BASE_URL_FIVE}" "/v1/plugins/1/hooks" '{"hook_name":"entry.created","handler_url":"https://example.com/webhook","shared_secret":"supersecret","enabled":true}' "Bearer ${TOKEN}"
assert_status "201" "public webhook host still accepted under CIDR denylist"

stop_server

echo "[PASS] enterprise security integration checks completed"
