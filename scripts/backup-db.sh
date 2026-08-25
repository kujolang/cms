#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
BACKUP_DIR="${CMS_BACKUP_DIR:-${RESULTS_DIR}/backups}"
SOURCE_DB="${1:-${CMS_DB_PATH:-${ROOT_DIR}/cms.db}}"

fail() { for line in "$@"; do echo "${line}"; done; exit 1; }
info() { echo "$1"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }

[[ -f "${SOURCE_DB}" ]] || fail "Source database file not found: ${SOURCE_DB}"
require_command sqlite3
require_command shasum
mkdir -p "${BACKUP_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
SOURCE_BASE="$(basename "${SOURCE_DB}")"
BACKUP_DB="${BACKUP_DIR}/${SOURCE_BASE}.${STAMP}.$$.bak"
MANIFEST_FILE="${BACKUP_DB}.manifest.txt"
TEMP_DIR="$(mktemp -d "${BACKUP_DIR}/.backup.XXXXXX")"
TEMP_DB="${TEMP_DIR}/snapshot.db"
TEMP_MANIFEST="${TEMP_DIR}/manifest.txt"
cleanup() { rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT

sqlite3 -cmd ".timeout 5000" "${SOURCE_DB}" ".backup '${TEMP_DB}'"
integrity="$(sqlite3 -cmd ".timeout 5000" "${TEMP_DB}" "PRAGMA integrity_check;")"
[[ "${integrity}" == "ok" ]] || fail "Backup integrity check failed: ${integrity}"
checksum="$(shasum -a 256 "${TEMP_DB}" | awk '{print $1}')"

{
	echo "timestamp=${STAMP}"
	echo "source_db=${SOURCE_DB}"
	echo "backup_db=${BACKUP_DB}"
	echo "sha256=${checksum}"
	echo "integrity_check=ok"
	echo "host=$(hostname)"
	echo "created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${TEMP_MANIFEST}"

mv "${TEMP_DB}" "${BACKUP_DB}"
mv "${TEMP_MANIFEST}" "${MANIFEST_FILE}"
info "Backup completed: ${BACKUP_DB}"
info "Manifest: ${MANIFEST_FILE}"
