#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4395}"
TOKEN="${CMS_TEST_TOKEN:-pagination-parity-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_pagination_parity_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_pagination_parity_server.log"
RUN_TAG="$(date +%s)_$RANDOM"
CONTENT_TYPE_KEY="pagecheck${RUN_TAG}"
TENANT_KEY_PREFIX="page-tenant-${RUN_TAG}"
WORKSPACE_KEY_PREFIX="page-workspace-${RUN_TAG}"
PLUGIN_KEY_PREFIX="page-plugin-${RUN_TAG}"
TOKEN_LABEL_PREFIX="Page Token ${RUN_TAG}"

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

validate_page_and_get_ids() {
	local expected_limit="$1"
	local expected_offset="$2"
	local context="$3"
	printf "%s" "${BODY}" | node -e '
		const fs = require("fs");
		const expectedLimit = Number(process.argv[1]);
		const expectedOffset = Number(process.argv[2]);
		const context = process.argv[3];
		const fail = (message) => {
			console.error(`[FAIL] ${context}: ${message}`);
			process.exit(1);
		};
		let payload;
		try {
			payload = JSON.parse(fs.readFileSync(0, "utf8"));
		} catch (e) {
			fail("response body is not valid JSON");
		}
		if (!payload || payload.ok !== true || typeof payload.data !== "object") {
			fail("response shape missing ok/data contract");
		}
		const data = payload.data;
		if (!Array.isArray(data.items)) {
			fail("data.items is missing or not an array");
		}
		if (Number(data.count) !== data.items.length) {
			fail(`data.count (${data.count}) does not equal items.length (${data.items.length})`);
		}
		if (Number(data.limit) !== expectedLimit) {
			fail(`data.limit (${data.limit}) does not equal expected limit (${expectedLimit})`);
		}
		if (Number(data.offset) !== expectedOffset) {
			fail(`data.offset (${data.offset}) does not equal expected offset (${expectedOffset})`);
		}
		const ids = data.items.map((item) => String(item.id ?? ""));
		if (ids.some((id) => id === "")) {
			fail("one or more items are missing id");
		}
		process.stdout.write(ids.join(","));
	' "${expected_limit}" "${expected_offset}" "${context}"
}

assert_stable_offset_order() {
	local ids_page_0="$1"
	local ids_page_1="$2"
	local context="$3"
	IFS=',' read -r -a page0_ids <<< "${ids_page_0}"
	IFS=',' read -r -a page1_ids <<< "${ids_page_1}"
	if [[ ${#page0_ids[@]} -lt 2 || ${#page1_ids[@]} -lt 1 ]]; then
		echo "[FAIL] ${context}: not enough list items to verify stable offset ordering"
		exit 1
	fi
	if [[ "${page0_ids[1]}" != "${page1_ids[0]}" ]]; then
		echo "[FAIL] ${context}: offset ordering mismatch (page0 second id=${page0_ids[1]}, page1 first id=${page1_ids[0]})"
		exit 1
	fi
	echo "[PASS] ${context}: stable ordering for limit/offset verified"
}

verify_list_contract() {
	local path_base="$1"
	local context="$2"
	local separator="?"
	if [[ "${path_base}" == *"?"* ]]; then
		separator="&"
	fi

	request "GET" "${path_base}${separator}limit=2&offset=0" '' "1"
	assert_status "200" "${context} page 1"
	local ids_page_0
	ids_page_0="$(validate_page_and_get_ids "2" "0" "${context} page 1")"

	request "GET" "${path_base}${separator}limit=2&offset=1" '' "1"
	assert_status "200" "${context} page 2"
	local ids_page_1
	ids_page_1="$(validate_page_and_get_ids "2" "1" "${context} page 2")"

	assert_stable_offset_order "${ids_page_0}" "${ids_page_1}" "${context}"
}

echo "Starting CMS API for pagination parity integration checks..."
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
		cat "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}\",\"label\":\"Pagination Type\",\"singular_label\":\"Pagination Type\"}" "1"
assert_status "201" "create content type"

for i in 1 2 3; do
	request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}_extra_${i}\",\"label\":\"Pagination Type Extra ${i}\",\"singular_label\":\"Pagination Type Extra ${i}\"}" "1"
	assert_status "201" "create extra content type ${i}"
done

for i in 1 2 3; do
	request "POST" "/v1/entries" "{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Page Entry ${i}\",\"slug\":\"page-entry-${RUN_TAG}-${i}\",\"status\":\"published\",\"body\":\"entry ${i}\"}" "1"
	assert_status "201" "create entry ${i}"
done

TENANT_ID=""
for i in 1 2 3; do
	request "POST" "/v1/tenants" "{\"tenant_key\":\"${TENANT_KEY_PREFIX}-${i}\",\"name\":\"Page Tenant ${i}\",\"status\":\"active\"}" "1"
	assert_status "201" "create tenant ${i}"
	if [[ "${i}" == "1" ]]; then
		TENANT_ID="$(json_extract 'data.id')"
	fi
done

for i in 1 2 3; do
	request "POST" "/v1/workspaces" "{\"tenant_id\":${TENANT_ID},\"workspace_key\":\"${WORKSPACE_KEY_PREFIX}-${i}\",\"name\":\"Page Workspace ${i}\",\"status\":\"active\"}" "1"
	assert_status "201" "create workspace ${i}"
done

for i in 1 2 3; do
	request "POST" "/v1/plugins" "{\"plugin_key\":\"${PLUGIN_KEY_PREFIX}-${i}\",\"name\":\"Page Plugin ${i}\",\"version\":\"1.0.${i}\",\"status\":\"inactive\"}" "1"
	assert_status "201" "create plugin ${i}"
done

for i in 1 2 3; do
	request "POST" "/v1/auth/tokens" "{\"label\":\"${TOKEN_LABEL_PREFIX} ${i}\",\"role_key\":\"super_admin\",\"token\":\"pagination-token-${RUN_TAG}-${i}\"}" "1"
	assert_status "201" "create token ${i}"
done

verify_list_contract "/v1/entries?content_type_key=${CONTENT_TYPE_KEY}" "entries list"
verify_list_contract "/v1/content-types" "content types list"
verify_list_contract "/v1/tenants" "tenants list"
verify_list_contract "/v1/workspaces" "workspaces list"
verify_list_contract "/v1/plugins" "plugins list"
verify_list_contract "/v1/auth/tokens" "tokens list"

echo "All pagination parity integration checks passed."
