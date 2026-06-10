#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4463}"
TOKEN="${CMS_TEST_TOKEN:-stage2-round2-feeds-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_round2_feeds_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_round2_feeds_server.log"

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

echo "Starting CMS API for Stage 2 Round 2 feed checks..."
(
	cd "${ROOT_DIR}"
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
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

request "POST" "/v1/content-types" '{"type_key":"news","label":"News","singular_label":"News Item"}' "1"
assert_status "201" "create news content type"

request "POST" "/v1/content-types" '{"type_key":"blogs","label":"Blogs","singular_label":"Blog"}' "1"
assert_status "201" "create blogs content type"

request "POST" "/v1/taxonomies" '{"taxonomy_key":"topic","label":"Topic","description":"Topic taxonomy","hierarchical":false}' "1"
assert_status "201" "create topic taxonomy"
TAXONOMY_ID="$(json_extract 'data.id')"

request "POST" "/v1/taxonomies/${TAXONOMY_ID}/terms" '{"name":"AI","slug":"ai"}' "1"
assert_status "201" "create ai term"
TERM_AI_ID="$(json_extract 'data.id')"

request "POST" "/v1/taxonomies/${TAXONOMY_ID}/terms" '{"name":"DevOps","slug":"devops"}' "1"
assert_status "201" "create devops term"
TERM_DEVOPS_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"AI News","slug":"ai-news","status":"published","excerpt":"AI news excerpt","body":"AI news body"}' "1"
assert_status "201" "create ai news entry"
ENTRY_AI_NEWS_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"DevOps News","slug":"devops-news","status":"published","excerpt":"DevOps news excerpt","body":"DevOps news body"}' "1"
assert_status "201" "create devops news entry"
ENTRY_DEVOPS_NEWS_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"blogs","title":"AI Blog","slug":"ai-blog","status":"published","excerpt":"AI blog excerpt","body":"AI blog body"}' "1"
assert_status "201" "create ai blog entry"
ENTRY_AI_BLOG_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"AI Draft","slug":"ai-draft","status":"draft","excerpt":"AI draft excerpt","body":"AI draft body"}' "1"
assert_status "201" "create ai draft entry"
ENTRY_AI_DRAFT_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries/${ENTRY_AI_NEWS_ID}/terms" '{"term_ids":['"${TERM_AI_ID}"']}' "1"
assert_status "200" "assign ai term to ai news"

request "POST" "/v1/entries/${ENTRY_DEVOPS_NEWS_ID}/terms" '{"term_ids":['"${TERM_DEVOPS_ID}"']}' "1"
assert_status "200" "assign devops term to devops news"

request "POST" "/v1/entries/${ENTRY_AI_BLOG_ID}/terms" '{"term_ids":['"${TERM_AI_ID}"']}' "1"
assert_status "200" "assign ai term to ai blog"

request "POST" "/v1/entries/${ENTRY_AI_DRAFT_ID}/terms" '{"term_ids":['"${TERM_AI_ID}"']}' "1"
assert_status "200" "assign ai term to ai draft"

request "GET" "/rss/content-type/news"
assert_status "200" "news content-type feed"
assert_contains '<rss version="2.0">' "news feed xml structure"
assert_contains '/news/ai-news' "news feed includes ai news"
assert_contains '/news/devops-news' "news feed includes devops news"
assert_not_contains '/blogs/ai-blog' "news feed excludes blogs"
assert_not_contains '/news/ai-draft' "news feed excludes draft entries"

request "GET" "/rss/content-type/blogs"
assert_status "200" "blogs content-type feed"
assert_contains '/blogs/ai-blog' "blogs feed includes ai blog"
assert_not_contains '/news/ai-news' "blogs feed excludes news"

request "GET" "/rss/taxonomy/topic/ai"
assert_status "200" "ai taxonomy feed"
assert_contains '/news/ai-news' "ai taxonomy feed includes ai news"
assert_contains '/blogs/ai-blog' "ai taxonomy feed includes ai blog"
assert_not_contains '/news/devops-news' "ai taxonomy feed excludes devops news"
assert_not_contains '/news/ai-draft' "ai taxonomy feed excludes draft entries"

request "GET" "/rss/taxonomy/topic/devops"
assert_status "200" "devops taxonomy feed"
assert_contains '/news/devops-news' "devops taxonomy includes devops news"
assert_not_contains '/news/ai-news' "devops taxonomy excludes ai news"

request "GET" "/rss/taxonomy/topic/missing"
assert_status "404" "missing taxonomy term feed"
assert_contains 'term_not_found' "missing taxonomy term error"

echo "All Stage 2 Round 2 feed variant integration checks passed."
