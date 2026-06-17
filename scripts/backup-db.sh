#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
BACKUP_DIR="${CMS_BACKUP_DIR:-${RESULTS_DIR}/backups}"

SOURCE_DB="${1:-${CMS_DB_PATH:-${ROOT_DIR}/cms.db}}"
fail() {
	for line in "$@"; do
		echo "${line}"
	done
	exit 1
}

info() {
	echo "$1"
}

if [[ ! -f "${SOURCE_DB}" ]]; then
	fail "Source database file not found: ${SOURCE_DB}"
fi

if lsof "${SOURCE_DB}" >/dev/null 2>&1; then
	fail \
		"Refusing backup while database file is actively opened by another process: ${SOURCE_DB}" \
		"Stop the CMS server first, then retry."
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

info "Backup completed: ${BACKUP_DB}"
info "Manifest: ${MANIFEST_FILE}"
