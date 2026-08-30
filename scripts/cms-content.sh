#!/usr/bin/env bash
set -euo pipefail

CMS_CONTENT_BASE_URL="${CMS_BASE_URL:-http://127.0.0.1:4200}"
CMS_CONTENT_TOKEN="${CMS_API_TOKEN:-}"

usage() {
  printf '%s\n' \
    'Usage: bash scripts/cms-content.sh <command> [arguments]' \
    '' \
    'Commands:' \
    '  entry:compose <id> <json>             Atomically snapshot and update entry fields/terms.' \
    '  terms:bulk <taxonomy-id> <json>       Create or update up to 100 terms atomically.' \
    '  media:ingest <filename> [alt-text]    Ingest a file staged in the CMS media inbox.' \
    '  media:register-external <json>        Register an object verified by an external adapter.' \
    '' \
    'Environment: CMS_BASE_URL and CMS_API_TOKEN.'
}

if [[ -z "${CMS_CONTENT_TOKEN}" ]]; then printf '%s\n' 'CMS_API_TOKEN is required.' >&2; exit 2; fi

request() {
  local method="$1" path="$2" body="$3"
  curl --fail-with-body --silent --show-error -X "${method}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${CMS_CONTENT_TOKEN}" \
    --data "${body}" "${CMS_CONTENT_BASE_URL%/}${path}"
  printf '\n'
}

command="${1:-help}"
case "${command}" in
  help|-h|--help) usage ;;
  entry:compose)
    id="${2:-}"; body="${3:-}"
    if [[ ! "${id}" =~ ^[1-9][0-9]*$ || -z "${body}" ]]; then usage >&2; exit 2; fi
    request PATCH "/v1/entries/${id}/compose" "${body}"
    ;;
  terms:bulk)
    id="${2:-}"; body="${3:-}"
    if [[ ! "${id}" =~ ^[1-9][0-9]*$ || -z "${body}" ]]; then usage >&2; exit 2; fi
    request POST "/v1/taxonomies/${id}/terms/bulk" "${body}"
    ;;
  media:ingest)
    filename="${2:-}"; alt_text="${3:-}"
    if [[ ! "${filename}" =~ ^[A-Za-z0-9._-]+$ ]]; then usage >&2; exit 2; fi
    body="$(jq -cn --arg filename "${filename}" --arg alt_text "${alt_text}" '{filename:$filename,alt_text:$alt_text}')"
    request POST '/v1/media/ingest' "${body}"
    ;;
  media:register-external)
    body="${2:-}"
    if [[ -z "${body}" ]]; then usage >&2; exit 2; fi
    request POST '/v1/media/register-external' "${body}"
    ;;
  *) usage >&2; exit 2 ;;
esac
