#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_GRACEFUL_PORT:-49720}"
TOKEN="${CMS_GRACEFUL_TOKEN:-graceful-restart-token-123456}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/graceful_restart_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/graceful_restart_${PORT}.log"

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

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

require_port_available() {
	for _ in $(seq 1 50); do
		if node -e '
			const net = require("node:net");
			const server = net.createServer();
			server.once("error", () => process.exit(1));
			server.listen(Number(process.argv[1]), "127.0.0.1", () => server.close(() => process.exit(0)));
		' "${PORT}"; then return 0; fi
		sleep 0.2
	done
	echo "[FAIL] test port ${PORT} is already in use; refusing to stop an unrelated process"
	exit 1
}

start_server() {
	require_port_available
	(
		cd "${ROOT_DIR}"
		exec env CMS_API_PORT="${PORT}" \
		CMS_SITE_URL="${BASE_URL}" \
		CMS_DB_PATH="${DB_PATH}" \
		CMS_API_TOKEN="${TOKEN}" \
		"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${LOG_FILE}" 2>&1
	) &
	SERVER_PID="$!"

	for _ in $(seq 1 60); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			echo "[FAIL] server exited during startup"
			tail -n 120 "${LOG_FILE}" || true
			exit 1
		fi
		if curl -fsS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.2
	done

	echo "[FAIL] server did not become healthy"
	tail -n 120 "${LOG_FILE}" || true
	exit 1
}

stop_server_gracefully() {
	if [[ -z "${SERVER_PID}" ]] || ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "[FAIL] server pid not running for graceful shutdown"
		exit 1
	fi

	kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true
	for _ in $(seq 1 25); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			SERVER_PID=""
			return 0
		fi
		sleep 0.2
	done

	echo "[FAIL] server did not stop after SIGTERM"
	exit 1
}

echo "Running graceful shutdown/restart validation..."
rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" "${LOG_FILE}" || true

start_server
curl -fsS "${BASE_URL}/v1" >/dev/null
stop_server_gracefully

echo "[PASS] graceful shutdown completed"

start_server
curl -fsS "${BASE_URL}/health" >/dev/null
stop_server_gracefully

echo "[PASS] graceful restart validation completed"
