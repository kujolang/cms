#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PERF_RUNS="${CMS_OPS_LOAD_PERF_RUNS:-30}"
PERF_PORT="${CMS_OPS_LOAD_PERF_PORT:-49810}"
MIGRATION_PORT="${CMS_OPS_LOAD_MIGRATION_PORT:-49820}"
PORT="${CMS_OPS_LOAD_PORT:-49830}"
TOKEN="${CMS_OPS_LOAD_TOKEN:-ops-load-token-1234567890}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/ops_load_validation_${PORT}.db"
RESTORED_DB="${RESULTS_DIR}/ops_load_validation_${PORT}_restored.db"
SNAPSHOT_DB="${RESULTS_DIR}/ops_load_validation_${PORT}_snapshot.db"
LOG_FILE="${RESULTS_DIR}/ops_load_validation_${PORT}.log"

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

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

start_server() {
	(
		cd "${ROOT_DIR}"
		CMS_API_PORT="${PORT}" \
		CMS_SITE_URL="${BASE_URL}" \
		CMS_DB_PATH="${DB_PATH}" \
		CMS_API_TOKEN="${TOKEN}" \
		"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff >"${LOG_FILE}" 2>&1
	) &
	SERVER_PID="$!"

	for _ in $(seq 1 60); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			echo "[FAIL] load validation server exited during startup"
			tail -n 120 "${LOG_FILE}" || true
			exit 1
		fi
		if curl -fsS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.2
	done

	echo "[FAIL] load validation server did not become healthy"
	tail -n 120 "${LOG_FILE}" || true
	exit 1
}

stop_server() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	SERVER_PID=""
}

echo "Running operational load validation..."

CMS_PERF_PORT="${PERF_PORT}" CMS_PERF_RUNS="${PERF_RUNS}" KUJO_BIN="${KUJO_BIN_PATH}" bash "${ROOT_DIR}/scripts/perf-baseline.sh"
CMS_MIGRATION_TEST_PORT="${MIGRATION_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" bash "${ROOT_DIR}/scripts/migration-safety.sh"

rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" "${RESTORED_DB}" "${RESTORED_DB}-wal" "${RESTORED_DB}-shm" "${SNAPSHOT_DB}" "${SNAPSHOT_DB}-wal" "${SNAPSHOT_DB}-shm" "${LOG_FILE}" || true
start_server

curl -fsS "${BASE_URL}/v1" >/dev/null
for _ in $(seq 1 200); do
	curl -fsS "${BASE_URL}/health" >/dev/null
	done

stop_server

cp "${DB_PATH}" "${SNAPSHOT_DB}"
bash "${ROOT_DIR}/scripts/backup-db.sh" "${SNAPSHOT_DB}"
LATEST_BACKUP="$(ls -t "${ROOT_DIR}/results/backups/$(basename "${SNAPSHOT_DB}")."*.bak | head -n 1)"

if [[ -z "${LATEST_BACKUP}" ]]; then
	echo "[FAIL] backup file was not created"
	exit 1
fi

bash "${ROOT_DIR}/scripts/restore-db.sh" "${LATEST_BACKUP}" "${RESTORED_DB}" --force

echo "[PASS] operational load validation completed"
