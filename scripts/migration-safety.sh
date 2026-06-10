#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_MIGRATION_TEST_PORT:-49510}"
TOKEN="${CMS_MIGRATION_TEST_TOKEN:-migration-safety-token}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/migration_safety_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/migration_safety_${PORT}.log"

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
}
trap cleanup EXIT

stop_server() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	SERVER_PID=""
}

start_server() {
	rm -f "${LOG_FILE}" || true
	(
		cd "${ROOT_DIR}"
		CMS_API_PORT="${PORT}" \
		CMS_SITE_URL="${BASE_URL}" \
		CMS_DB_PATH="${DB_PATH}" \
		CMS_API_TOKEN="${TOKEN}" \
		"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${LOG_FILE}" 2>&1
	) &
	SERVER_PID="$!"

	for _ in $(seq 1 50); do
		if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
			echo "Server process exited early during migration safety check."
			tail -n 120 "${LOG_FILE}" || true
			exit 1
		fi
		if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.2
	done

	echo "Server did not become healthy in time."
	tail -n 120 "${LOG_FILE}" || true
	exit 1
}

get_schema_version() {
	curl -sS "${BASE_URL}/" >"${TMP_BODY}"
	node -e '
		const fs = require("fs");
		const raw = fs.readFileSync(process.argv[1], "utf8");
		const parsed = JSON.parse(raw);
		const schemaVersion = parsed && parsed.ok && parsed.data ? parsed.data.schema_version : null;
		if (schemaVersion === null || schemaVersion === undefined) process.exit(2);
		process.stdout.write(String(schemaVersion));
	' "${TMP_BODY}"
}

echo "Running migration safety validation..."
rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true

start_server
FIRST_SCHEMA_VERSION="$(get_schema_version)"
echo "[PASS] first boot schema version: ${FIRST_SCHEMA_VERSION}"
stop_server

start_server
SECOND_SCHEMA_VERSION="$(get_schema_version)"
echo "[PASS] restart schema version: ${SECOND_SCHEMA_VERSION}"
stop_server

if (( FIRST_SCHEMA_VERSION < 5 )); then
	echo "[FAIL] expected schema version >= 5 on first boot, got ${FIRST_SCHEMA_VERSION}"
	exit 1
fi

if (( SECOND_SCHEMA_VERSION < FIRST_SCHEMA_VERSION )); then
	echo "[FAIL] schema version regressed after restart (${FIRST_SCHEMA_VERSION} -> ${SECOND_SCHEMA_VERSION})"
	exit 1
fi

echo "[PASS] migration safety checks completed"
