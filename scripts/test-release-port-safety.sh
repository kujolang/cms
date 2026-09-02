#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPORARY_DIRECTORY="$(mktemp -d)"
PORT_FILE="${TEMPORARY_DIRECTORY}/port"
OUTPUT_FILE="${TEMPORARY_DIRECTORY}/output"
LISTENER_PID=""

cleanup() {
	if [[ -n "${LISTENER_PID}" ]] && kill -0 "${LISTENER_PID}" >/dev/null 2>&1; then
		kill "${LISTENER_PID}" >/dev/null 2>&1 || true
		wait "${LISTENER_PID}" >/dev/null 2>&1 || true
	fi
	rm -rf "${TEMPORARY_DIRECTORY}"
}
trap cleanup EXIT

node -e '
	const fs = require("node:fs");
	const net = require("node:net");
	const server = net.createServer();
	server.listen(0, "0.0.0.0", () => fs.writeFileSync(process.argv[1], String(server.address().port)));
' "${PORT_FILE}" &
LISTENER_PID="$!"

for _ in $(seq 1 50); do
	[[ -s "${PORT_FILE}" ]] && break
	sleep 0.1
done
[[ -s "${PORT_FILE}" ]] || { echo "[FAIL] fixture listener did not start"; exit 1; }
BASE_PORT="$(cat "${PORT_FILE}")"

if CMS_GATE_PORT_BASE="${BASE_PORT}" CMS_GATE_RUN_PERF=false KUJO_BIN="${KUJO_BIN:-/bin/false}" bash "${ROOT_DIR}/scripts/run-release-gate.sh" >"${OUTPUT_FILE}" 2>&1; then
	echo "[FAIL] release gate accepted an occupied port"
	exit 1
fi

grep -q "port ${BASE_PORT} is already in use" "${OUTPUT_FILE}"
kill -0 "${LISTENER_PID}" >/dev/null 2>&1 || { echo "[FAIL] release gate stopped an unrelated listener"; exit 1; }

echo "Release gate refuses occupied ports without stopping unrelated processes"
