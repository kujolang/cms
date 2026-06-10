#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT_SQLITE="${CMS_TEST_PORT_SQLITE:-56130}"
PORT_MEMORY="${CMS_TEST_PORT_MEMORY:-56131}"
TOKEN="${CMS_TEST_TOKEN:-durable-rate-limit-token-123456}"

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

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "sqlite3 is required for durable rate-limit integration checks"
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

start_server() {
	local port="$1"
	local db_path="$2"
	local log_file="$3"
	local mode="$4"
	local site_url="http://127.0.0.1:${port}"
	clear_port "${port}"

	(
		cd "${ROOT_DIR}"
		CMS_API_PORT="${port}" \
		CMS_SITE_URL="${site_url}" \
		CMS_DB_PATH="${db_path}" \
		CMS_API_TOKEN="${TOKEN}" \
		CMS_RATE_LIMIT_MODE="${mode}" \
		CMS_RATE_WINDOW_SEC="3600" \
		CMS_RATE_MAX_REQUESTS="100" \
		CMS_RATE_MAX_KEYS="10000" \
		"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${log_file}" 2>&1
	) &
	SERVER_PID="$!"

	for _ in $(seq 1 60); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			echo "Server exited during startup (${mode})."
			tail -n 120 "${log_file}" || true
			exit 1
		fi
		if lsof -tiTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
			sleep 0.2
			return 0
		fi
		sleep 0.2
	done

	echo "Server did not become healthy in time (${mode})."
	tail -n 120 "${log_file}" || true
	exit 1
}

request_post_content_type() {
	local base_url="$1"
	local type_key="$2"
	STATUS="$(curl -sS -o "${TMP_BODY}" -w "%{http_code}" -X POST "${base_url}/v1/content-types" -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" --data "{\"type_key\":\"${type_key}\",\"label\":\"${type_key}\",\"singular_label\":\"${type_key}\"}")"
	BODY="$(cat "${TMP_BODY}")"
}

assert_status() {
	local expected="$1"
	local context="$2"
	if [[ "${STATUS}" != "${expected}" ]]; then
		echo "[FAIL] ${context}: expected ${expected}, got ${STATUS}"
		echo "Response body: ${BODY}"
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
		exit 1
	fi
	echo "[PASS] ${context}"
}

read_sqlite_bucket_count() {
	local db_path="$1"
	local value
	value="$(sqlite3 "${db_path}" "SELECT COALESCE(MAX(count), 0) FROM rate_limit_buckets;")"
	if [[ -z "${value}" ]]; then
		value="0"
	fi
	echo "${value}"
}

echo "Running durable rate-limit integration checks..."

SQLITE_DB="${RESULTS_DIR}/integration_rate_limit_sqlite_${PORT_SQLITE}.db"
SQLITE_LOG="${RESULTS_DIR}/integration_rate_limit_sqlite_${PORT_SQLITE}.log"
SQLITE_URL="http://127.0.0.1:${PORT_SQLITE}"
rm -f "${SQLITE_DB}" "${SQLITE_DB}-wal" "${SQLITE_DB}-shm" "${SQLITE_LOG}" || true

start_server "${PORT_SQLITE}" "${SQLITE_DB}" "${SQLITE_LOG}" "sqlite"
request_post_content_type "${SQLITE_URL}" "durable-sqlite-a-${PORT_SQLITE}"
assert_status "201" "sqlite mode first write accepted"
SQLITE_COUNT_BEFORE_RESTART="$(read_sqlite_bucket_count "${SQLITE_DB}")"
if (( SQLITE_COUNT_BEFORE_RESTART < 1 )); then
	echo "[FAIL] sqlite mode did not persist initial bucket count"
	exit 1
fi
echo "[PASS] sqlite mode initial bucket count persisted: ${SQLITE_COUNT_BEFORE_RESTART}"
stop_server

start_server "${PORT_SQLITE}" "${SQLITE_DB}" "${SQLITE_LOG}" "sqlite"
request_post_content_type "${SQLITE_URL}" "durable-sqlite-b-${PORT_SQLITE}"
assert_status "201" "sqlite mode write after restart accepted"
SQLITE_COUNT_AFTER_RESTART="$(read_sqlite_bucket_count "${SQLITE_DB}")"
if (( SQLITE_COUNT_AFTER_RESTART <= SQLITE_COUNT_BEFORE_RESTART )); then
	echo "[FAIL] sqlite mode bucket count did not continue across restart (${SQLITE_COUNT_BEFORE_RESTART} -> ${SQLITE_COUNT_AFTER_RESTART})"
	exit 1
fi
echo "[PASS] sqlite mode bucket count continued across restart: ${SQLITE_COUNT_BEFORE_RESTART} -> ${SQLITE_COUNT_AFTER_RESTART}"
stop_server

MEMORY_DB="${RESULTS_DIR}/integration_rate_limit_memory_${PORT_MEMORY}.db"
MEMORY_LOG="${RESULTS_DIR}/integration_rate_limit_memory_${PORT_MEMORY}.log"
MEMORY_URL="http://127.0.0.1:${PORT_MEMORY}"
rm -f "${MEMORY_DB}" "${MEMORY_DB}-wal" "${MEMORY_DB}-shm" "${MEMORY_LOG}" || true

start_server "${PORT_MEMORY}" "${MEMORY_DB}" "${MEMORY_LOG}" "memory"
request_post_content_type "${MEMORY_URL}" "durable-memory-a-${PORT_MEMORY}"
assert_status "201" "memory mode first write accepted"
stop_server

start_server "${PORT_MEMORY}" "${MEMORY_DB}" "${MEMORY_LOG}" "memory"
request_post_content_type "${MEMORY_URL}" "durable-memory-b-${PORT_MEMORY}"
assert_status "201" "memory mode bucket resets after restart"
MEMORY_SQLITE_BUCKETS="$(read_sqlite_bucket_count "${MEMORY_DB}")"
if (( MEMORY_SQLITE_BUCKETS != 0 )); then
	echo "[FAIL] memory mode unexpectedly wrote SQLite rate buckets"
	exit 1
fi
echo "[PASS] memory mode keeps SQLite rate bucket table unused"
stop_server

echo "Durable rate-limit integration checks passed."
