#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USAGE="Usage: bash scripts/restore-db.sh <backup_db_path> [target_db_path] [--force]"

usage() {
	echo "${USAGE}"
}

fail() {
	for line in "$@"; do
		echo "${line}"
	done
	exit 1
}

info() {
	echo "$1"
}

if [[ $# -lt 1 ]]; then
	usage
	exit 1
fi

BACKUP_DB="$1"
TARGET_DB="${2:-${CMS_DB_PATH:-${ROOT_DIR}/cms.db}}"
FORCE_FLAG="${3:-}"

if [[ ! -f "${BACKUP_DB}" ]]; then
	fail "Backup file not found: ${BACKUP_DB}"
fi

if [[ -f "${TARGET_DB}" ]] && [[ "${FORCE_FLAG}" != "--force" ]]; then
	fail \
		"Target DB already exists: ${TARGET_DB}" \
		"Pass --force as the third argument to overwrite."
fi

if [[ -f "${TARGET_DB}" ]] && lsof "${TARGET_DB}" >/dev/null 2>&1; then
	fail \
		"Refusing restore while target DB is actively opened by another process: ${TARGET_DB}" \
		"Stop the CMS server first, then retry."
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

info "Restore completed: ${TARGET_DB}"
