#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USAGE="Usage: bash scripts/restore-db.sh <backup_db_path> [target_db_path] [--force]"

usage() { echo "${USAGE}"; }
fail() { for line in "$@"; do echo "${line}"; done; exit 1; }
info() { echo "$1"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }

if [[ $# -lt 1 ]]; then usage; exit 1; fi

BACKUP_DB="$1"
TARGET_DB="${2:-${CMS_DB_PATH:-${ROOT_DIR}/cms.db}}"
FORCE_FLAG="${3:-}"
MANIFEST_FILE="${BACKUP_DB}.manifest.txt"

[[ -f "${BACKUP_DB}" ]] || fail "Backup file not found: ${BACKUP_DB}"
if [[ -f "${TARGET_DB}" && "${FORCE_FLAG}" != "--force" ]]; then
	fail "Target DB already exists: ${TARGET_DB}" "Pass --force as the third argument to overwrite."
fi
if [[ -f "${TARGET_DB}" ]] && lsof "${TARGET_DB}" >/dev/null 2>&1; then
	fail "Refusing restore while target DB is actively opened by another process: ${TARGET_DB}" "Stop the CMS server first, then retry."
fi

require_command sqlite3
require_command shasum
TARGET_DIR="$(dirname "${TARGET_DB}")"
mkdir -p "${TARGET_DIR}"
TEMP_DB="$(mktemp "${TARGET_DIR}/.restore.XXXXXX")"
cleanup() { rm -f "${TEMP_DB}"; }
trap cleanup EXIT

if [[ -f "${MANIFEST_FILE}" ]]; then
	expected_checksum="$(awk -F= '$1 == "sha256" {print $2}' "${MANIFEST_FILE}" | tail -n 1)"
	if [[ -n "${expected_checksum}" ]]; then
		actual_checksum="$(shasum -a 256 "${BACKUP_DB}" | awk '{print $1}')"
		[[ "${actual_checksum}" == "${expected_checksum}" ]] || fail "Backup checksum does not match its manifest"
	fi
fi

cp "${BACKUP_DB}" "${TEMP_DB}"
integrity="$(sqlite3 -cmd ".timeout 5000" "${TEMP_DB}" "PRAGMA integrity_check;")"
[[ "${integrity}" == "ok" ]] || fail "Backup integrity check failed: ${integrity}"

rm -f "${TARGET_DB}-wal" "${TARGET_DB}-shm"
mv -f "${TEMP_DB}" "${TARGET_DB}"
trap - EXIT
info "Restore completed: ${TARGET_DB}"
