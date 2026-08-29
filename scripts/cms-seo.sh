#!/usr/bin/env bash
set -euo pipefail

CMS_SEO_BASE_URL="${CMS_BASE_URL:-http://127.0.0.1:4200}"
CMS_SEO_TOKEN="${CMS_API_TOKEN:-}"

usage() {
  printf '%s\n' \
    'Usage: bash scripts/cms-seo.sh <command> [arguments]' \
    '' \
    'Commands:' \
    '  report [query]              List SEO inventory; query is an URL query string.' \
    '  update <entry-id> <json>    Update SEO fields for one entry.' \
    '  bulk <id,id,...> <json>     Apply SEO fields to selected entries.' \
    '  sharing:get                 Read social-sharing settings.' \
    '  sharing:update <json>       Update networks, content types, and account handles.' \
    '' \
    'Environment: CMS_BASE_URL and CMS_API_TOKEN are required for non-default/local use.'
}

require_token() {
  if [[ -z "${CMS_SEO_TOKEN}" ]]; then
    printf '%s\n' 'CMS_API_TOKEN is required.' >&2
    exit 2
  fi
}

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local args=(--fail-with-body --silent --show-error -X "${method}" -H 'Accept: application/json' -H "Authorization: Bearer ${CMS_SEO_TOKEN}")
  if [[ -n "${body}" ]]; then
    args+=(-H 'Content-Type: application/json' --data "${body}")
  fi
  curl "${args[@]}" "${CMS_SEO_BASE_URL%/}${path}"
  printf '\n'
}

command="${1:-help}"
case "${command}" in
  help|-h|--help)
    usage
    ;;
  report)
    require_token
    query="${2:-limit=25&offset=0}"
    request GET "/v1/seo/entries?${query}"
    ;;
  update)
    require_token
    entry_id="${2:-}"
    changes="${3:-}"
    if [[ ! "${entry_id}" =~ ^[1-9][0-9]*$ || -z "${changes}" ]]; then usage >&2; exit 2; fi
    request PATCH "/v1/entries/${entry_id}/seo" "${changes}"
    ;;
  bulk)
    require_token
    ids="${2:-}"
    changes="${3:-}"
    if [[ ! "${ids}" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ || -z "${changes}" ]]; then usage >&2; exit 2; fi
    id_json="[${ids}]"
    request POST '/v1/seo/entries/bulk' "{\"entry_ids\":${id_json},\"changes\":${changes}}"
    ;;
  sharing:get)
    require_token
    request GET '/v1/settings/social-sharing'
    ;;
  sharing:update)
    require_token
    settings="${2:-}"
    if [[ -z "${settings}" ]]; then usage >&2; exit 2; fi
    request PATCH '/v1/settings/social-sharing' "${settings}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
