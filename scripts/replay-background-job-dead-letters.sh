#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
JOB_ID=""
REPLAY_ALL=0
SCRIPT_LABEL="Background job dead-letter replay"
USAGE="Usage: $0 [--all] [--job-id <id>]"

usage() {
	echo "${USAGE}"
}

fail() {
	echo "${SCRIPT_LABEL}: $1"
	exit 1
}

info() {
	echo "${SCRIPT_LABEL}: $1"
}

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		fail "${command_name} is required"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--job-id)
			JOB_ID="${2:-}"
			shift 2
			;;
		--all)
			REPLAY_ALL=1
			shift
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [[ ! -f "${DB_PATH}" ]]; then
	fail "database not found at ${DB_PATH}"
fi

require_command sqlite3

if [[ ${REPLAY_ALL} -eq 0 && -z "${JOB_ID}" ]]; then
	usage
	exit 1
fi

if [[ ${REPLAY_ALL} -eq 1 ]]; then
	affected_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM background_job_dead_letters;")"
	if [[ "${affected_count}" == "0" ]]; then
		info "no dead-letter rows found"
		exit 0
	fi
	sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'pending', attempt_count = 0, run_after = strftime('%s','now'), last_error = NULL, started_at = NULL, completed_at = NULL, updated_at = strftime('%s','now') WHERE id IN (SELECT job_id FROM background_job_dead_letters);"
	sqlite3 "${DB_PATH}" "DELETE FROM background_job_dead_letters;"
	info "requeued ${affected_count} row(s)"
	exit 0
fi

if ! [[ "${JOB_ID}" =~ ^[0-9]+$ ]]; then
	fail "job id must be an integer"
fi

exists="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM background_job_dead_letters WHERE job_id = ${JOB_ID};")"
if [[ "${exists}" == "0" ]]; then
	fail "job id ${JOB_ID} is not in dead letters"
fi

sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'pending', attempt_count = 0, run_after = strftime('%s','now'), last_error = NULL, started_at = NULL, completed_at = NULL, updated_at = strftime('%s','now') WHERE id = ${JOB_ID};"
sqlite3 "${DB_PATH}" "DELETE FROM background_job_dead_letters WHERE job_id = ${JOB_ID};"

info "requeued job id ${JOB_ID}"
