#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/cms.db}"
SCRIPT_LABEL="Media maintenance"

fail() {
	echo "${SCRIPT_LABEL}: $1"
	exit 1
}

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		fail "${command_name} is required"
	fi
}

if [[ ! -f "${DB_PATH}" ]]; then
	fail "database not found at ${DB_PATH}"
fi

require_command sqlite3

total_items="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items;")"
missing_storage_path="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items WHERE TRIM(COALESCE(storage_path, '')) = '';")"
invalid_size="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items WHERE CAST(COALESCE(size_bytes, 0) AS INTEGER) < 0;")"

now_epoch="$(date +%s)"

printf '{"task":"media.maintain","ok":true,"checked_at":"%s","total_items":%s,"missing_storage_path":%s,"invalid_size":%s}\n' "${now_epoch}" "${total_items:-0}" "${missing_storage_path:-0}" "${invalid_size:-0}"
