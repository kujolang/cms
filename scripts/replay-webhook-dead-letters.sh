#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
OUTBOX_ID=""
REPLAY_ALL=0

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
			echo "Usage: $0 [--all] [--outbox-id <id>]"
			exit 1
			;;
	esac
done

if [[ ! -f "${DB_PATH}" ]]; then
	echo "Webhook dead-letter replay: database not found at ${DB_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Webhook dead-letter replay: sqlite3 is required"
	exit 1
fi

if [[ ${REPLAY_ALL} -eq 0 && -z "${OUTBOX_ID}" ]]; then
	echo "Usage: $0 [--all] [--outbox-id <id>]"
	exit 1
fi

if [[ ${REPLAY_ALL} -eq 1 ]]; then
	affected_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM webhook_dead_letters;")"
	if [[ "${affected_count}" == "0" ]]; then
		echo "Webhook dead-letter replay: no dead-letter rows found"
		exit 0
	fi
	sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'pending', attempt_count = 0, next_attempt_at = strftime('%s','now'), last_error = NULL, last_status_code = NULL, updated_at = strftime('%s','now') WHERE id IN (SELECT outbox_id FROM webhook_dead_letters);"
	sqlite3 "${DB_PATH}" "DELETE FROM webhook_dead_letters;"
	echo "Webhook dead-letter replay: requeued ${affected_count} row(s)"
	exit 0
fi

if ! [[ "${OUTBOX_ID}" =~ ^[0-9]+$ ]]; then
	echo "Webhook dead-letter replay: outbox id must be an integer"
	exit 1
fi

exists="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM webhook_dead_letters WHERE outbox_id = ${OUTBOX_ID};")"
if [[ "${exists}" == "0" ]]; then
	echo "Webhook dead-letter replay: outbox id ${OUTBOX_ID} is not in dead letters"
	exit 1
fi

sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'pending', attempt_count = 0, next_attempt_at = strftime('%s','now'), last_error = NULL, last_status_code = NULL, updated_at = strftime('%s','now') WHERE id = ${OUTBOX_ID};"
sqlite3 "${DB_PATH}" "DELETE FROM webhook_dead_letters WHERE outbox_id = ${OUTBOX_ID};"

echo "Webhook dead-letter replay: requeued outbox id ${OUTBOX_ID}"
