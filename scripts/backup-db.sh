#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
BACKUP_DIR="${CMS_BACKUP_DIR:-${RESULTS_DIR}/backups}"

SOURCE_DB="${1:-${CMS_DB_PATH:-${ROOT_DIR}/kujo_cms.db}}"

if [[ ! -f "${SOURCE_DB}" ]]; then
	echo "Source database file not found: ${SOURCE_DB}"
	exit 1
fi

if lsof "${SOURCE_DB}" >/dev/null 2>&1; then
	echo "Refusing backup while database file is actively opened by another process: ${SOURCE_DB}"
	echo "Stop the CMS server first, then retry."
	exit 1
fi

mkdir -p "${BACKUP_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
SOURCE_BASE="$(basename "${SOURCE_DB}")"
BACKUP_DB="${BACKUP_DIR}/${SOURCE_BASE}.${STAMP}.bak"
MANIFEST_FILE="${BACKUP_DB}.manifest.txt"

cp "${SOURCE_DB}" "${BACKUP_DB}"

if [[ -f "${SOURCE_DB}-wal" ]]; then
	cp "${SOURCE_DB}-wal" "${BACKUP_DB}-wal"
fi
if [[ -f "${SOURCE_DB}-shm" ]]; then
	cp "${SOURCE_DB}-shm" "${BACKUP_DB}-shm"
fi

{
	echo "timestamp=${STAMP}"
	echo "source_db=${SOURCE_DB}"
	echo "backup_db=${BACKUP_DB}"
	echo "host=$(hostname)"
	echo "created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MANIFEST_FILE}"

echo "Backup completed: ${BACKUP_DB}"
echo "Manifest: ${MANIFEST_FILE}"
