#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 ]]; then
	echo "Usage: bash scripts/restore-db.sh <backup_db_path> [target_db_path] [--force]"
	exit 1
fi

BACKUP_DB="$1"
TARGET_DB="${2:-${CMS_DB_PATH:-${ROOT_DIR}/kujo_cms.db}}"
FORCE_FLAG="${3:-}"

if [[ ! -f "${BACKUP_DB}" ]]; then
	echo "Backup file not found: ${BACKUP_DB}"
	exit 1
fi

if [[ -f "${TARGET_DB}" ]] && [[ "${FORCE_FLAG}" != "--force" ]]; then
	echo "Target DB already exists: ${TARGET_DB}"
	echo "Pass --force as the third argument to overwrite."
	exit 1
fi

if [[ -f "${TARGET_DB}" ]] && lsof "${TARGET_DB}" >/dev/null 2>&1; then
	echo "Refusing restore while target DB is actively opened by another process: ${TARGET_DB}"
	echo "Stop the CMS server first, then retry."
	exit 1
fi

mkdir -p "$(dirname "${TARGET_DB}")"

cp "${BACKUP_DB}" "${TARGET_DB}"

if [[ -f "${BACKUP_DB}-wal" ]]; then
	cp "${BACKUP_DB}-wal" "${TARGET_DB}-wal"
else
	rm -f "${TARGET_DB}-wal" || true
fi

if [[ -f "${BACKUP_DB}-shm" ]]; then
	cp "${BACKUP_DB}-shm" "${TARGET_DB}-shm"
else
	rm -f "${TARGET_DB}-shm" || true
fi

echo "Restore completed: ${TARGET_DB}"
