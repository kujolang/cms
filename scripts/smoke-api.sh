#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_SMOKE_PORT:-4288}"
API_HOST="${CMS_API_HOST:-127.0.0.1}"
TOKEN="${CMS_SMOKE_TOKEN:-stage1-smoke-token}"
BASE_URL="http://${API_HOST}:${PORT}"
DB_PATH="${RESULTS_DIR}/smoke_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/smoke_server.log"

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
TMP_HEADERS="$(mktemp)"
TMP_WEBMCP_RUNTIME="$(mktemp)"

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
	rm -f "${TMP_HEADERS}" || true
	rm -f "${TMP_WEBMCP_RUNTIME}" || true
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

request_head() {
	local path="$1"
	STATUS="$(curl -sS -I -o "${TMP_HEADERS}" -w "%{http_code}" "${BASE_URL}${path}")"
	BODY=""
}

assert_status() {
	local expected="$1"
	local context="$2"
	if [[ "${STATUS}" != "${expected}" ]]; then
		echo "[FAIL] ${context}: expected ${expected}, got ${STATUS}"
		echo "Response body: ${BODY}"
		tail -n 80 "${LOG_FILE}" || true
		exit 1
	fi
	echo "[PASS] ${context}"
}

assert_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" != *"${needle}"* ]]; then
		echo "[FAIL] ${context}: missing '${needle}'"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}"
}

assert_not_contains() {
	local needle="$1"
	local context="$2"
	if [[ "${BODY}" == *"${needle}"* ]]; then
		echo "[FAIL] ${context}: unexpectedly found '${needle}'"
		echo "Response body: ${BODY}"
		exit 1
	fi
	echo "[PASS] ${context}"
}

echo "Starting CMS API smoke check..."
(
	cd "${ROOT_DIR}"
	CMS_API_HOST="${API_HOST}" \
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 50); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server exited before smoke checks."
		tail -n 80 "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "GET" "/health"
assert_status "200" "health"
assert_contains '"status":"ok"' "health payload"

request "GET" "/v1"
assert_status "200" "api root"
assert_contains '"resources"' "api root resources"

request_head "/health"
assert_status "200" "HEAD health"

request_head "/v1"
assert_status "200" "HEAD api root"

request_head "/robots.txt"
assert_status "200" "HEAD robots"

request_head "/rss.xml"
assert_status "200" "HEAD rss"

request "GET" "/robots.txt"
assert_status "200" "robots"

request "GET" "/.well-known/security.txt"
assert_status "200" "security.txt"

request "GET" "/v1/extensions/contracts"
assert_status "200" "extension package contracts"
assert_contains '"schema":"kujo.theme/v1"' "theme package contract"
assert_contains '"schema":"kujo.plugin/v1"' "plugin package contract"

THEME_MANIFEST="$(jq -c . "${ROOT_DIR}/examples/extensions/starter-theme/kujo-theme.json")"
PLUGIN_MANIFEST="$(jq -c . "${ROOT_DIR}/examples/extensions/starter-plugin/kujo-plugin.json")"
request "POST" "/v1/themes/validate" "${THEME_MANIFEST}" "1"
assert_status "200" "validate portable theme manifest"
assert_contains '"valid":true' "theme manifest valid"

request "POST" "/v1/plugins/validate" "${PLUGIN_MANIFEST}" "1"
assert_status "200" "validate portable plugin manifest"
assert_contains '"valid":true' "plugin manifest valid"

request "POST" "/v1/themes/install" "{\"manifest\":${THEME_MANIFEST},\"activate\":true,\"settings\":{\"site_title\":\"Smoke Publication\",\"accent_color\":\"#224466\"}}" "1"
assert_status "200" "install and activate portable theme"
assert_contains '"installed":true' "theme package installed"
THEME_PACKAGE_ID="$(jq -r '.data.theme.id' <<<"${BODY}")"

request "POST" "/v1/themes/install" "{\"manifest\":${THEME_MANIFEST},\"activate\":false}" "1"
assert_status "200" "update installed theme package"
assert_contains '"status":"active"' "theme update preserves activation"
assert_contains '#224466' "theme update preserves configured settings"

request "POST" "/v1/plugins/install" "{\"manifest\":${PLUGIN_MANIFEST},\"activate\":false}" "1"
assert_status "200" "install portable plugin"
assert_contains '"installed":true' "plugin package installed"
PLUGIN_PACKAGE_ID="$(jq -r '.data.plugin.id' <<<"${BODY}")"

request "GET" "/v1/extensions/manage" "" "1"
assert_status "200" "extension management catalog"
assert_contains '"schema":"kujo.extensions.manage/v1"' "management catalog schema"

request "GET" "/v1/themes/${THEME_PACKAGE_ID}/export"
assert_status "200" "export portable theme"
assert_contains '"secrets_included":false' "theme export excludes secrets"
assert_not_contains '"settings"' "theme export excludes installed settings"

request "GET" "/v1/plugins/${PLUGIN_PACKAGE_ID}/export" '' "1"
assert_status "200" "export portable plugin"
assert_contains '"secrets_included":false' "plugin export excludes secrets"
assert_not_contains 'shared_secret' "plugin export excludes hook secrets"

request "GET" "/v1/extensions/catalog"
assert_status "200" "extension package catalog"
assert_contains '"key":"starter_web"' "catalog includes installed theme"

request "GET" "/.well-known/kujo-webmcp.json"
assert_status "200" "WebMCP manifest"
assert_contains '"automatic":true' "WebMCP automatic availability"
assert_contains '"get_site_info"' "WebMCP tool registry"

request "GET" "/assets/js/kujo-webmcp.js"
assert_status "200" "WebMCP browser adapter"
assert_contains 'document.modelContext' "WebMCP runtime contract"
cp "${TMP_BODY}" "${TMP_WEBMCP_RUNTIME}"
node "${ROOT_DIR}/scripts/test-webmcp-runtime.js" "${TMP_WEBMCP_RUNTIME}"

request "GET" "/v1/webmcp/site"
assert_status "200" "WebMCP site information"

request "GET" "/.well-known/kujo-site-index.json?limit=10&offset=0"
assert_status "200" "WebMCP published-content index"
assert_contains '"schema":"kujo-cms-site-index/v1"' "WebMCP site index schema"

request "POST" "/v1/content-types" '{"type_key":"smoke","label":"Smoke","singular_label":"Smoke"}'
assert_status "401" "write auth required"

request "POST" "/v1/content-types" '{"type_key":"smoke","label":"Smoke","singular_label":"Smoke","description":"Smoke type"}' "1"
assert_status "201" "authorized write"

request "GET" "/v1/abilities/definitions" "" "1"
assert_status "200" "portable Ability definitions"
assert_contains '"schema":"kujo.ability/v1"' "Ability definition schema"
assert_contains '"id":"kujo.cms.content.list"' "canonical Ability identity"

request "POST" "/v1/abilities/content/list/run" '{"input":{"unexpected":true}}' "1"
assert_status "400" "Ability input schema enforced"
assert_contains '"code":"ability_input_invalid"' "Ability input schema error"

request "POST" "/v1/entries" '{"content_type_key":"smoke","title":"Ability Approval Fixture","slug":"ability-approval-fixture","status":"draft","body":"Approval fixture"}' "1"
assert_status "201" "Ability approval fixture"
ABILITY_ENTRY_ID="$(jq -r '.data.id' <<<"${BODY}")"

ABILITY_INPUT="{\"entry_id\":${ABILITY_ENTRY_ID},\"changes\":{\"description\":\"Approved SEO description\"}}"
request "POST" "/v1/abilities/seo/update-entry/run" "{\"input\":${ABILITY_INPUT}}" "1"
assert_status "409" "Ability mutation requires request-bound approval"
assert_contains '"code":"ability_approval_required"' "Ability approval requirement"
ABILITY_INVOCATION_ID="$(jq -r '.error.details.receipt.invocation_id' <<<"${BODY}")"

request "POST" "/v1/abilities/seo/update-entry/approvals" "{\"invocation_id\":\"${ABILITY_INVOCATION_ID}\"}" "1"
assert_status "201" "Ability approval issued"
ABILITY_APPROVAL_ID="$(jq -r '.data.approval_id' <<<"${BODY}")"

request "POST" "/v1/abilities/seo/update-entry/run" "{\"invocation_id\":\"${ABILITY_INVOCATION_ID}\",\"approval_id\":\"${ABILITY_APPROVAL_ID}\",\"input\":${ABILITY_INPUT}}" "1" "ability-approval-success"
assert_status "200" "Approved Ability executes"
assert_contains '"approval_id":"' "Ability receipt records approval"

request "POST" "/v1/abilities/seo/update-entry/run" "{\"invocation_id\":\"${ABILITY_INVOCATION_ID}\",\"approval_id\":\"${ABILITY_APPROVAL_ID}\",\"input\":${ABILITY_INPUT}}" "1" "ability-approval-replay"
assert_status "409" "Ability approval is one-time"
assert_contains '"code":"ability_approval_replayed"' "Ability approval replay blocked"

request "POST" "/v1/abilities/content/list/run" '{"input":{"limit":5}}' "1"
assert_status "200" "Ability execution validates output"
assert_contains '"ability":"content/list"' "Ability execution response"

request "GET" "/v1/ai/mcp/tools" "" "1"
assert_status "200" "MCP-ready Ability projection"
assert_contains '"abilityId":"kujo.cms.content.list"' "MCP projection preserves canonical Ability identity"

request "POST" "/v1/entries" '{"content_type_key":"smoke","title":"WebMCP Public","slug":"webmcp-public","status":"published","excerpt":"Published excerpt","body":"Published searchable body"}' "1"
assert_status "201" "WebMCP published fixture"

request "POST" "/v1/entries" '{"content_type_key":"smoke","title":"WebMCP Draft Secret","slug":"webmcp-draft","status":"draft","body":"Draft content must stay private"}' "1"
assert_status "201" "WebMCP draft fixture"

request "POST" "/v1/entries" '{"content_type_key":"smoke","title":"WebMCP Excluded","slug":"webmcp-excluded","status":"published","body":"Excluded published content","meta":{"webmcp_exclude":true}}' "1"
assert_status "201" "WebMCP excluded fixture"

request "GET" "/v1/webmcp/search?q=searchable&limit=10"
assert_status "200" "WebMCP published search"
assert_contains '"title":"WebMCP Public"' "WebMCP returns matching published content"
assert_not_contains 'WebMCP Draft Secret' "WebMCP search excludes drafts"
assert_not_contains 'WebMCP Excluded' "WebMCP search honors entry exclusion"

request "GET" "/.well-known/kujo-site-index.json?limit=10&offset=0"
assert_status "200" "WebMCP populated index"
assert_contains '"id":"smoke:webmcp-public"' "WebMCP index exposes stable public ID"
assert_not_contains 'webmcp-draft' "WebMCP index excludes drafts"
assert_not_contains 'webmcp-excluded' "WebMCP index honors entry exclusion"

echo "Smoke checks passed."
