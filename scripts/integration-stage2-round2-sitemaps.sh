#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4462}"
TOKEN="${CMS_TEST_TOKEN:-stage2-round2-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_round2_sitemaps_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_round2_sitemaps_server.log"

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

echo "Starting Kujo CMS API for Stage 2 Round 2 sitemap checks..."
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

request "POST" "/v1/content-types" '{"type_key":"news","label":"News","singular_label":"News Item"}' "1"
assert_status "201" "create news content type"

request "POST" "/v1/content-types" '{"type_key":"updates","label":"Updates","singular_label":"Update"}' "1"
assert_status "201" "create updates content type"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"January News","slug":"january-news","status":"published","published_at":"2026-01-15T10:00:00Z","body":"January news body"}' "1"
assert_status "201" "create january news entry"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"February News","slug":"february-news","status":"published","published_at":"2026-02-02T09:00:00Z","body":"February news body"}' "1"
assert_status "201" "create february news entry"

request "POST" "/v1/entries" '{"content_type_key":"updates","title":"January Update","slug":"january-update","status":"published","published_at":"2026-01-20T12:00:00Z","body":"January update body"}' "1"
assert_status "201" "create january update entry"

request "POST" "/v1/entries" '{"content_type_key":"news","title":"Draft Hidden","slug":"draft-hidden","status":"draft","body":"Not for sitemap"}' "1"
assert_status "201" "create draft entry"

request "GET" "/sitemap.xml"
assert_status "200" "base sitemap"
assert_contains '<urlset' "base sitemap structure"
assert_contains '/news/january-news' "base sitemap january news"
assert_contains '/updates/january-update' "base sitemap january update"
assert_not_contains '/news/draft-hidden' "base sitemap excludes draft"

request "GET" "/sitemap-index.xml"
assert_status "200" "sitemap index"
assert_contains '<sitemapindex' "sitemap index structure"
assert_contains '/sitemaps/content-types.xml' "sitemap index content-type index link"
assert_contains '/sitemaps/dates.xml' "sitemap index date index link"
assert_contains '/sitemaps/content-type/news' "sitemap index news segment link"
assert_contains '/sitemaps/date/2026-01' "sitemap index january segment link"
assert_contains '/sitemaps/date/2026-02' "sitemap index february segment link"

request "GET" "/sitemaps/content-types.xml"
assert_status "200" "content-type sitemap index"
assert_contains '/sitemaps/content-type/news' "content-type index includes news"
assert_contains '/sitemaps/content-type/updates' "content-type index includes updates"

request "GET" "/sitemaps/content-type/news"
assert_status "200" "news segmented sitemap"
assert_contains '/news/january-news' "news sitemap january news"
assert_contains '/news/february-news' "news sitemap february news"
assert_not_contains '/updates/january-update' "news sitemap excludes updates entries"

request "GET" "/sitemaps/dates.xml"
assert_status "200" "date sitemap index"
assert_contains '/sitemaps/date/2026-01' "date index includes january"
assert_contains '/sitemaps/date/2026-02' "date index includes february"

request "GET" "/sitemaps/date/2026-01"
assert_status "200" "january segmented sitemap"
assert_contains '/news/january-news' "january sitemap includes january news"
assert_contains '/updates/january-update' "january sitemap includes january update"
assert_not_contains '/news/february-news' "january sitemap excludes february news"

request "GET" "/sitemaps/date/not-a-bucket"
assert_status "400" "invalid date bucket validation"
assert_contains 'invalid_bucket' "invalid date bucket error code"

echo "All Stage 2 Round 2 sitemap integration checks passed."
