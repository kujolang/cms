#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4460}"
TOKEN="${CMS_TEST_TOKEN:-stage2-round1-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_round1_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_round1_server.log"

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

echo "Starting Kujo CMS API for Stage 2 Round 1 integration checks..."
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

request "POST" "/v1/content-types" '{"type_key":"seo_news","label":"SEO News","singular_label":"SEO News"}' "1"
assert_status "201" "create seo_news content type"

request "POST" "/v1/entries" '{"content_type_key":"seo_news","title":"Zeta Update","slug":"zeta-update","status":"published","author_id":"alice","excerpt":"Zeta summary","body":"Zeta body text","seo":{"title":"Zeta SEO Title","description":"Zeta SEO Description","canonical_url":"https://example.test/seo-news/zeta-update","og_image_url":"https://example.test/images/zeta.jpg","schema_type":"NewsArticle"}}' "1"
assert_status "201" "create entry with seo metadata"
ENTRY_A_ID="$(json_extract 'data.id')"

request "POST" "/v1/entries" '{"content_type_key":"seo_news","title":"Alpha Draft","slug":"alpha-draft","status":"draft","author_id":"bob","excerpt":"Alpha summary","body":"Alpha body text"}' "1"
assert_status "201" "create draft entry"

request "POST" "/v1/entries" '{"content_type_key":"seo_news","title":"Beta Update","slug":"beta-update","status":"published","author_id":"alice","excerpt":"Beta summary","body":"Beta body text"}' "1"
assert_status "201" "create second published entry"

request "GET" "/v1/entries?content_type=seo_news&status=published&author_id=alice&sort_by=title&sort_dir=asc"
assert_status "200" "filtered sorted entry list"
FILTER_CONTENT_TYPE="$(json_extract 'data.filters.content_type')"
FILTER_STATUS="$(json_extract 'data.filters.status')"
FILTER_AUTHOR="$(json_extract 'data.filters.author_id')"
SORT_BY="$(json_extract 'data.sort.by')"
SORT_DIR="$(json_extract 'data.sort.dir')"
if [[ "${FILTER_CONTENT_TYPE}" != "seo_news" || "${FILTER_STATUS}" != "published" || "${FILTER_AUTHOR}" != "alice" ]]; then
	echo "[FAIL] list filters payload: unexpected filter values"
	echo "Response body: ${BODY}"
	exit 1
fi
if [[ "${SORT_BY}" != "title" || "${SORT_DIR}" != "asc" ]]; then
	echo "[FAIL] list sort payload: unexpected sort values"
	echo "Response body: ${BODY}"
	exit 1
fi
echo "[PASS] list filters payload"
echo "[PASS] list sort payload"
FIRST_TITLE="$(json_extract 'data.items.0.title')"
if [[ "${FIRST_TITLE}" != "Beta Update" ]]; then
	echo "[FAIL] sorted entry order: expected first title Beta Update, got ${FIRST_TITLE}"
	exit 1
fi
echo "[PASS] sorted entry order"

request "GET" "/v1/entries/${ENTRY_A_ID}/seo"
assert_status "200" "entry seo endpoint"
assert_contains '"title":"Zeta SEO Title"' "seo title projection"
assert_contains '"@type":"NewsArticle"' "json-ld schema type"
assert_contains '"canonical_url":"https://example.test/seo-news/zeta-update"' "seo canonical projection"

echo "All Stage 2 Round 1 integration checks passed."
