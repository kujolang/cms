#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/cms.db}"
OUTBOX_ID=""
REPLAY_ALL=0
SCRIPT_LABEL="Webhook dead-letter replay"
USAGE="Usage: $0 [--all] [--outbox-id <id>]"

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
		--outbox-id)
			OUTBOX_ID="${2:-}"
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

sqlite3() {
	command sqlite3 -cmd ".timeout 5000" "$@"
}

if [[ ${REPLAY_ALL} -eq 0 && -z "${OUTBOX_ID}" ]]; then
	usage
	exit 1
fi

if [[ ${REPLAY_ALL} -eq 1 ]]; then
	affected_count="$(sqlite3 "${DB_PATH}" "BEGIN IMMEDIATE; CREATE TEMP TABLE replay_ids AS SELECT outbox_id FROM webhook_dead_letters; SELECT COUNT(*) FROM replay_ids; UPDATE webhook_outbox SET status = 'pending', attempt_count = 0, next_attempt_at = strftime('%s','now'), last_error = NULL, last_status_code = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = strftime('%s','now') WHERE id IN (SELECT outbox_id FROM replay_ids); DELETE FROM webhook_dead_letters WHERE outbox_id IN (SELECT outbox_id FROM replay_ids); COMMIT;")"
	if [[ "${affected_count}" == "0" ]]; then
		info "no dead-letter rows found"
		exit 0
	fi
	info "requeued ${affected_count} row(s)"
	exit 0
fi

if ! [[ "${OUTBOX_ID}" =~ ^[0-9]+$ ]]; then
	fail "outbox id must be an integer"
fi

exists="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM webhook_dead_letters WHERE outbox_id = ${OUTBOX_ID};")"
if [[ "${exists}" == "0" ]]; then
	fail "outbox id ${OUTBOX_ID} is not in dead letters"
fi

sqlite3 "${DB_PATH}" "BEGIN IMMEDIATE; UPDATE webhook_outbox SET status = 'pending', attempt_count = 0, next_attempt_at = strftime('%s','now'), last_error = NULL, last_status_code = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = strftime('%s','now') WHERE id = ${OUTBOX_ID}; DELETE FROM webhook_dead_letters WHERE outbox_id = ${OUTBOX_ID}; COMMIT;"

info "requeued outbox id ${OUTBOX_ID}"
