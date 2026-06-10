#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"

if [[ ! -f "${DB_PATH}" ]]; then
	echo "Media maintenance: database not found at ${DB_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Media maintenance: sqlite3 is required"
	exit 1
fi

total_items="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items;")"
missing_storage_path="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items WHERE TRIM(COALESCE(storage_path, '')) = '';")"
invalid_size="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM media_items WHERE CAST(COALESCE(size_bytes, 0) AS INTEGER) < 0;")"

now_epoch="$(date +%s)"

printf '{"task":"media.maintain","ok":true,"checked_at":"%s","total_items":%s,"missing_storage_path":%s,"invalid_size":%s}\n' "${now_epoch}" "${total_items:-0}" "${missing_storage_path:-0}" "${invalid_size:-0}"
