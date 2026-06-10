#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-49780}"
BASE_URL="http://127.0.0.1:${PORT}"
TOKEN="test-token-background-jobs"
CONTENT_TYPE_KEY="jobsnews${PORT}${RANDOM}"
DB_PATH="${RESULTS_DIR}/integration_stage2_background_jobs_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_background_jobs_server.log"

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
	echo "sqlite3 is required for background jobs integration checks"
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "node is required for background jobs integration checks"
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

start_api() {
	echo "Starting Kujo CMS API for background jobs integration checks..."
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
}

wait_for_health() {
	for _ in $(seq 1 60); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			echo "Server process exited early."
			cat "${LOG_FILE}" || true
			exit 1
		fi
		if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
			return
		fi
		sleep 0.2
	done
	echo "Timed out waiting for health endpoint"
	exit 1
}

start_api
wait_for_health

request "GET" "/v1/plugins?limit=1&offset=0"
assert_status "200" "load seeded plugin"

request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}\",\"label\":\"Background Jobs News\",\"singular_label\":\"Background Jobs News\"}" "1"
assert_status "201" "create background jobs content type"

PAST_PUBLISH_AT="$(( ($(date +%s) * 1000) - 60000 ))"
request "POST" "/v1/entries" "{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Scheduled Publish Entry\",\"slug\":\"scheduled-publish-entry\",\"status\":\"draft\",\"published_at\":\"${PAST_PUBLISH_AT}\",\"body\":\"Publish me by scheduler\"}" "1"
assert_status "201" "create scheduled entry"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-background-job.sh --job-type "webhook.enqueue" --payload-json '{}'
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-background-job.sh --job-type "webhook.process" --payload-json '{}'
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-background-job.sh --job-type "scheduler.run" --payload-json "{\"base_url\":\"${BASE_URL}\",\"token\":\"${TOKEN}\"}"
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-background-job.sh --job-type "media.maintain" --payload-json '{}'
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-background-job.sh --job-type "unsupported.task" --payload-json '{}' --max-attempts 1
)

UNKNOWN_JOB_ID="$(sqlite3 "${DB_PATH}" "SELECT id FROM background_jobs WHERE job_type = 'unsupported.task' ORDER BY id DESC LIMIT 1;")"
if [[ -z "${UNKNOWN_JOB_ID}" ]]; then
	echo "[FAIL] missing unsupported task job row"
	exit 1
fi

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	CMS_BACKGROUND_JOB_PROCESS_LIMIT="10" \
	CMS_BACKGROUND_JOB_RETRY_BASE_SEC="1" \
	CMS_WEBHOOK_CONNECT_TIMEOUT_SEC="1" \
	CMS_WEBHOOK_MAX_TIME_SEC="1" \
	CMS_API_TOKEN="${TOKEN}" \
	CMS_SITE_URL="${BASE_URL}" \
	bash scripts/process-background-jobs.sh
)

assert_sql_equals "SELECT COUNT(*) FROM background_jobs WHERE status = 'completed';" "4" "four background jobs completed"
assert_sql_equals "SELECT COUNT(*) FROM background_jobs WHERE status = 'dead_letter';" "1" "unsupported background job dead-lettered"
assert_sql_equals "SELECT COUNT(*) FROM background_job_dead_letters WHERE job_id = ${UNKNOWN_JOB_ID};" "1" "dead-letter row persisted"
assert_sql_equals "SELECT CASE WHEN COALESCE((SELECT last_audit_id FROM webhook_dispatch_state WHERE id = 1), 0) > 0 THEN 1 ELSE 0 END;" "1" "webhook enqueue advanced dispatch cursor"
assert_sql_equals "SELECT status FROM entries WHERE slug = 'scheduled-publish-entry' ORDER BY id DESC LIMIT 1;" "published" "scheduler job published overdue entry"
assert_sql_equals "SELECT COUNT(*) FROM audit_log WHERE action = 'background.job.completed';" "4" "audit log recorded completed jobs"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/replay-background-job-dead-letters.sh --job-id "${UNKNOWN_JOB_ID}"
	CMS_DB_PATH="${DB_PATH}" \
	CMS_BACKGROUND_JOB_PROCESS_LIMIT="10" \
	CMS_BACKGROUND_JOB_RETRY_BASE_SEC="1" \
	bash scripts/process-background-jobs.sh
)

assert_sql_equals "SELECT status FROM background_jobs WHERE id = ${UNKNOWN_JOB_ID};" "dead_letter" "replayed unsupported job dead-letters again"

echo "Stage 2 Round 3 background jobs integration checks passed."
