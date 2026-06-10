#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_COMPAT_PORT:-59600}"
API_HOST="${CMS_API_HOST:-127.0.0.1}"
TOKEN="${CMS_COMPAT_TOKEN:-compat-startup-token}"
BASE_URL="http://${API_HOST}:${PORT}"
DB_PATH="${RESULTS_DIR}/compat_startup_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/compat_startup_server.log"

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
HEALTH_BODY_FILE="$(mktemp)"
API_BODY_FILE="$(mktemp)"

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${HEALTH_BODY_FILE}" "${API_BODY_FILE}" || true
	rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true
}
trap cleanup EXIT

echo "Verifying startup compatibility via backend/runtime/main.ruff entrypoint..."
(
	cd "${ROOT_DIR}"
	CMS_API_HOST="${API_HOST}" \
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.ruff >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 50); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server exited before compatibility checks."
		tail -n 80 "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

HEALTH_STATUS="$(curl -sS -o "${HEALTH_BODY_FILE}" -w "%{http_code}" "${BASE_URL}/health")"
if [[ "${HEALTH_STATUS}" != "200" ]]; then
	echo "[FAIL] health endpoint via backend startup: expected 200, got ${HEALTH_STATUS}"
	cat "${HEALTH_BODY_FILE}"
	exit 1
fi

API_STATUS="$(curl -sS -o "${API_BODY_FILE}" -w "%{http_code}" "${BASE_URL}/v1")"
if [[ "${API_STATUS}" != "200" ]]; then
	echo "[FAIL] API discovery endpoint via backend startup: expected 200, got ${API_STATUS}"
	cat "${API_BODY_FILE}"
	exit 1
fi

if ! grep -q '"resources"' "${API_BODY_FILE}"; then
	echo "[FAIL] API discovery response missing resources key"
	cat "${API_BODY_FILE}"
	exit 1
fi

echo "Compatibility startup checks passed."
