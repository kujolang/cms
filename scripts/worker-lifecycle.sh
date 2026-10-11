#!/usr/bin/env bash
# Sourced by queue workers; each renewal helper owns and reaps its timer.
heartbeat_pid=""
worker_job_pid=""
worker_output_file=""

start_worker_heartbeat() {
	local table="$1" row_id="$2" parent_pid="$3"
	(
		sleeper=""
		trap 'for timer in $(jobs -pr); do kill "${timer}" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT
		trap 'exit 0' INT TERM
		interval="$((CLAIM_TTL_SEC / 3))"
		if [[ "${interval}" -lt 10 ]]; then interval=10; fi
		while kill -0 "${parent_pid}" 2>/dev/null; do
			sleep "${interval}" &
			sleeper=$!
			wait "${sleeper}" || exit 0
			sleeper=""
			kill -0 "${parent_pid}" 2>/dev/null || exit 0
			heartbeat_now="$(date +%s)"
			heartbeat_expiry="$((heartbeat_now + CLAIM_TTL_SEC))"
			renewed="$(sqlite3 "${DB_PATH}" "UPDATE ${table} SET claim_expires_at = '${heartbeat_expiry}', updated_at = '${heartbeat_now}' WHERE id = ${row_id} AND claim_token = '${WORKER_TOKEN}'; SELECT changes();")"
			[[ "${renewed}" == "1" ]] || exit 0
		done
	) </dev/null >/dev/null &
	heartbeat_pid=$!
}

stop_worker_heartbeat() {
	if [[ -n "${heartbeat_pid}" ]]; then
		kill "${heartbeat_pid}" 2>/dev/null || true
		wait "${heartbeat_pid}" 2>/dev/null || true
		heartbeat_pid=""
	fi
}

cleanup_worker() {
	stop_worker_heartbeat
	if [[ -n "${worker_job_pid}" ]] && kill -0 "${worker_job_pid}" 2>/dev/null; then
		# Only terminate descendants of the job this worker started.
		python3 - "${worker_job_pid}" <<'PY'
import os, signal, subprocess, sys
root = int(sys.argv[1])
rows = subprocess.check_output(['ps', '-eo', 'pid=,ppid='], text=True).splitlines()
children = {}
for row in rows:
    pid, parent = map(int, row.split())
    children.setdefault(parent, []).append(pid)
def terminate(pid):
    for child in children.get(pid, []):
        terminate(child)
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
terminate(root)
PY
		wait "${worker_job_pid}" 2>/dev/null || true
	fi
	if [[ -n "${worker_output_file}" ]]; then rm -f "${worker_output_file}"; fi
}
trap cleanup_worker EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
