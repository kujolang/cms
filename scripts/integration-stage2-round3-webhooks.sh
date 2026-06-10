#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_TEST_PORT:-4296}"
TOKEN="${CMS_TEST_TOKEN:-stage2-webhook-token}"
BASE_URL="http://127.0.0.1:${PORT}"
WEBHOOK_PORT="${CMS_WEBHOOK_SINK_PORT:-$((PORT + 100))}"
CONTENT_TYPE_KEY="webhooknews${PORT}"
DB_PATH="${RESULTS_DIR}/integration_stage2_webhooks_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/integration_stage2_webhooks_server.log"
SINK_LOG="${RESULTS_DIR}/integration_stage2_webhooks_sink_${PORT}.ndjson"

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

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "sqlite3 is required for webhook integration checks"
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "node is required for webhook sink checks"
	exit 1
fi

SERVER_PID=""
SINK_PID=""
TMP_BODY="$(mktemp)"

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	if [[ -n "${SINK_PID}" ]] && kill -0 "${SINK_PID}" >/dev/null 2>&1; then
		kill "${SINK_PID}" >/dev/null 2>&1 || true
		wait "${SINK_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${TMP_BODY}" || true
	rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true
	rm -f "${SINK_LOG}" || true
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

assert_file_contains() {
	local file_path="$1"
	local needle="$2"
	local context="$3"
	if ! grep -q "${needle}" "${file_path}"; then
		echo "[FAIL] ${context}: expected ${file_path} to contain ${needle}"
		if [[ -f "${file_path}" ]]; then
			echo "--- ${file_path} ---"
			cat "${file_path}" || true
			echo "---------------"
		fi
		exit 1
	fi
	echo "[PASS] ${context}"
}

start_webhook_sink() {
	echo "Starting local webhook sink on ${WEBHOOK_PORT}..."
	: > "${SINK_LOG}"
	WEBHOOK_SINK_PORT="${WEBHOOK_PORT}" WEBHOOK_SINK_FILE="${SINK_LOG}" node -e '
		const fs = require("fs");
		const http = require("http");
		const port = parseInt(process.env.WEBHOOK_SINK_PORT, 10);
		const output = process.env.WEBHOOK_SINK_FILE;
		http.createServer((req, res) => {
			let body = "";
			req.on("data", (chunk) => {
				body += chunk;
			});
			req.on("end", () => {
				const line = JSON.stringify({
					headers: req.headers,
					body
				});
				fs.appendFileSync(output, line + "\n");
				res.writeHead(202, { "Content-Type": "application/json" });
					res.end("{\"ok\":true}");
			});
		}).listen(port, "127.0.0.1");
	' > /dev/null 2>&1 &
	SINK_PID="$!"
}

start_api() {
	echo "Starting CMS API for webhook integration checks..."
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

start_webhook_sink
start_api
wait_for_health

request "GET" "/v1/plugins?limit=1&offset=0"
assert_status "200" "load seeded plugin"
PLUGIN_ID="$(json_extract 'data.items.0.id')"

request "PATCH" "/v1/plugins/${PLUGIN_ID}" '{"status":"active"}' "1"
assert_status "200" "activate plugin for webhook dispatch"

request "POST" "/v1/content-types" "{\"type_key\":\"${CONTENT_TYPE_KEY}\",\"label\":\"Webhook News\",\"singular_label\":\"Webhook News\"}" "1"
assert_status "201" "create webhook content type"

HOOK_NOW="$(date +%s)"
sqlite3 "${DB_PATH}" "INSERT INTO plugin_hooks (plugin_id, hook_name, handler_url, shared_secret, enabled, created_at, updated_at) VALUES (${PLUGIN_ID}, 'entry.created', 'http://127.0.0.1:${WEBHOOK_PORT}/hook', 'webhook-secret-accept', 1, '${HOOK_NOW}', '${HOOK_NOW}');"
sqlite3 "${DB_PATH}" "INSERT INTO plugin_hooks (plugin_id, hook_name, handler_url, shared_secret, enabled, created_at, updated_at) VALUES (${PLUGIN_ID}, 'entry.created', 'http://127.0.0.1:9/unreachable', 'webhook-secret-fail', 1, '${HOOK_NOW}', '${HOOK_NOW}');"
echo "[PASS] seeded reachable and unreachable webhook hooks"

request "POST" "/v1/entries" "{\"content_type_key\":\"${CONTENT_TYPE_KEY}\",\"title\":\"Webhook Queue Event\",\"slug\":\"webhook-queue-event\",\"status\":\"published\",\"body\":\"Queue me\"}" "1"
assert_status "201" "create entry and enqueue webhooks"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/enqueue-webhook-outbox.sh
)

assert_sql_equals "SELECT COUNT(*) FROM webhook_outbox WHERE event_type = 'entry.created';" "2" "two outbox rows created"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	CMS_WEBHOOK_CONNECT_TIMEOUT_SEC="1" \
	CMS_WEBHOOK_MAX_TIME_SEC="1" \
	bash scripts/process-webhook-outbox.sh
)

assert_sql_equals "SELECT COUNT(*) FROM webhook_outbox WHERE status = 'delivered' AND event_type = 'entry.created';" "1" "reachable webhook delivered"
assert_sql_equals "SELECT COUNT(*) FROM webhook_outbox WHERE status = 'retry' AND event_type = 'entry.created';" "1" "unreachable webhook moved to retry"

RETRY_OUTBOX_ID="$(sqlite3 "${DB_PATH}" "SELECT id FROM webhook_outbox WHERE status = 'retry' AND handler_url = 'http://127.0.0.1:9/unreachable' ORDER BY id DESC LIMIT 1;")"
if [[ -z "${RETRY_OUTBOX_ID}" ]]; then
	echo "[FAIL] missing retry outbox row for unreachable hook"
	exit 1
fi

sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET max_attempts = 1, next_attempt_at = strftime('%s','now') WHERE id = ${RETRY_OUTBOX_ID};"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	CMS_WEBHOOK_CONNECT_TIMEOUT_SEC="1" \
	CMS_WEBHOOK_MAX_TIME_SEC="1" \
	bash scripts/process-webhook-outbox.sh
)

assert_sql_equals "SELECT status FROM webhook_outbox WHERE id = ${RETRY_OUTBOX_ID};" "dead_letter" "retry webhook moved to dead-letter"
assert_sql_equals "SELECT COUNT(*) FROM webhook_dead_letters WHERE outbox_id = ${RETRY_OUTBOX_ID};" "1" "dead-letter row created"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	bash scripts/replay-webhook-dead-letters.sh --outbox-id "${RETRY_OUTBOX_ID}"
)

assert_sql_equals "SELECT status FROM webhook_outbox WHERE id = ${RETRY_OUTBOX_ID};" "pending" "dead-letter replay requeues outbox row"
assert_sql_equals "SELECT COUNT(*) FROM webhook_dead_letters WHERE outbox_id = ${RETRY_OUTBOX_ID};" "0" "dead-letter row removed on replay"

(
	cd "${ROOT_DIR}"
	CMS_DB_PATH="${DB_PATH}" \
	CMS_WEBHOOK_CONNECT_TIMEOUT_SEC="1" \
	CMS_WEBHOOK_MAX_TIME_SEC="1" \
	bash scripts/process-webhook-outbox.sh
)

assert_sql_equals "SELECT status FROM webhook_outbox WHERE id = ${RETRY_OUTBOX_ID};" "dead_letter" "replayed row is processed again"
assert_file_contains "${SINK_LOG}" '"x-cms-webhook-event":"entry.created"' "sink captured entry.created payload"

echo "Stage 2 Round 3 webhook integration checks passed."
