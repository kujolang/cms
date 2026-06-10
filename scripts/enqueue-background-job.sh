#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
JOB_TYPE=""
PAYLOAD_JSON="{}"
RUN_AFTER=""
MAX_ATTEMPTS="${CMS_BACKGROUND_JOB_MAX_ATTEMPTS:-5}"

usage() {
	echo "Usage: $0 --job-type <type> [--payload-json <json>] [--run-after <epoch_seconds>] [--max-attempts <n>]"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--job-type)
			JOB_TYPE="${2:-}"
			shift 2
			;;
		--payload-json)
			PAYLOAD_JSON="${2:-}"
			if [[ -z "${PAYLOAD_JSON}" ]]; then
				PAYLOAD_JSON="{}"
			fi
			shift 2
			;;
		--run-after)
			RUN_AFTER="${2:-}"
			shift 2
			;;
		--max-attempts)
			MAX_ATTEMPTS="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			usage
			exit 1
			;;
	esac
done

if [[ -z "${JOB_TYPE}" ]]; then
	echo "Background job enqueue: --job-type is required"
	usage
	exit 1
fi

if [[ ! -f "${DB_PATH}" ]]; then
	echo "Background job enqueue: database not found at ${DB_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Background job enqueue: sqlite3 is required"
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "Background job enqueue: node is required"
	exit 1
fi

if ! [[ "${MAX_ATTEMPTS}" =~ ^[0-9]+$ ]] || [[ "${MAX_ATTEMPTS}" -lt 1 ]]; then
	echo "Background job enqueue: max attempts must be a positive integer"
	exit 1
fi

if [[ -z "${RUN_AFTER}" ]]; then
	RUN_AFTER="$(date +%s)"
fi

if ! [[ "${RUN_AFTER}" =~ ^[0-9]+$ ]]; then
	echo "Background job enqueue: run-after must be epoch seconds"
	exit 1
fi

PAYLOAD_JSON="$(printf '%s' "${PAYLOAD_JSON}" | node -e '
	const fs = require("fs");
	const raw = fs.readFileSync(0, "utf8").trim();
	let parsed;
	try {
		parsed = raw ? JSON.parse(raw) : {};
	} catch {
		process.stderr.write("Background job enqueue: payload-json must be valid JSON\n");
		process.exit(1);
	}
	process.stdout.write(JSON.stringify(parsed));
')"

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}

job_type_sql="$(sql_escape "${JOB_TYPE}")"
payload_sql="$(sql_escape "${PAYLOAD_JSON}")"
now_value="$(date +%s)"

sqlite3 "${DB_PATH}" "INSERT INTO background_jobs (job_type, payload_json, status, attempt_count, max_attempts, run_after, last_error, result_json, started_at, completed_at, created_at, updated_at) VALUES ('${job_type_sql}', '${payload_sql}', 'pending', 0, ${MAX_ATTEMPTS}, '${RUN_AFTER}', NULL, NULL, NULL, NULL, '${now_value}', '${now_value}');"

job_id="$(sqlite3 "${DB_PATH}" "SELECT id FROM background_jobs ORDER BY id DESC LIMIT 1;")"

echo "Background job enqueue: job_id=${job_id} type=${JOB_TYPE} run_after=${RUN_AFTER} max_attempts=${MAX_ATTEMPTS}"
