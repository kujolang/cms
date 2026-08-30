#!/usr/bin/env bash
set -euo pipefail

CMS_EXT_BASE_URL="${CMS_BASE_URL:-http://127.0.0.1:4200}"
CMS_EXT_TOKEN="${CMS_API_TOKEN:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  printf '%s\n' \
    'Usage: bash scripts/cms-extensions.sh <command> [arguments]' \
    '' \
    'Commands:' \
    '  contracts                         Show portable extension contracts.' \
    '  catalog                           List installed themes and active plugins.' \
    '  navigation                        List active admin-sidebar contributions.' \
    '  ai                                List active plugin AI contributions.' \
    '  theme:validate <manifest>         Validate kujo-theme.json.' \
    '  theme:install <manifest> [active] Install or update a theme package.' \
    '  theme:install-zip <archive> [active] Upload, verify, and install a theme ZIP.' \
    '  theme:export <id>                 Export a secret-free theme manifest.' \
    '  theme:activate <id>               Activate an installed theme.' \
    '  plugin:validate <manifest>        Validate kujo-plugin.json.' \
    '  plugin:install <manifest> [active] Install or update a plugin package.' \
    '  plugin:install-zip <archive> [active] Upload, verify, and install a plugin ZIP.' \
    '  plugin:export <id>                Export a secret-free plugin manifest.' \
    '' \
    'Environment: CMS_BASE_URL and CMS_API_TOKEN. Contracts, catalog, and theme export are public.'
}

require_token() {
  if [[ -z "${CMS_EXT_TOKEN}" ]]; then printf '%s\n' 'CMS_API_TOKEN is required for this command.' >&2; exit 2; fi
}

require_file() {
  if [[ -z "${1:-}" || ! -f "${1}" ]]; then usage >&2; exit 2; fi
}

require_id() {
  if [[ ! "${1:-}" =~ ^[1-9][0-9]*$ ]]; then usage >&2; exit 2; fi
}

request() {
  local method="$1"
  local path="$2"
  local body_file="${3:-}"
  local body_text="${4:-}"
  local args=(--fail-with-body --silent --show-error -X "${method}" -H 'Accept: application/json')
  if [[ -n "${CMS_EXT_TOKEN}" ]]; then args+=(-H "Authorization: Bearer ${CMS_EXT_TOKEN}"); fi
  if [[ -n "${body_file}" ]]; then args+=(-H 'Content-Type: application/json' --data-binary "@${body_file}"); fi
  if [[ -n "${body_text}" ]]; then args+=(-H 'Content-Type: application/json' --data-binary "${body_text}"); fi
  local status=0
  curl "${args[@]}" "${CMS_EXT_BASE_URL%/}${path}" || status=$?
  printf '\n'
  return "${status}"
}

install_payload() {
  local manifest="$1"
  local active="${2:-false}"
  if [[ "${active}" == "active" || "${active}" == "true" ]]; then active=true; else active=false; fi
  jq -c --argjson active "${active}" '{manifest:.,activate:$active}' "${manifest}"
}

upload_zip() {
  local archive_path="$1" active_value="${2:-false}" expected_kind="$3"
  local payload_file
  payload_file="$(mktemp /tmp/cms-extension-upload.XXXXXX.json)"
  node "${ROOT_DIR}/scripts/encode-upload.mjs" "${archive_path}" "${active_value}" >"${payload_file}"
  local output status=0
  output="$(request POST '/v1/extensions/packages/upload' "${payload_file}")" || status=$?
  rm -f "${payload_file}"
  if [[ ${status} -ne 0 ]]; then return "${status}"; fi
  if [[ "$(jq -r '.data.kind // empty' <<<"${output}")" != "${expected_kind}" ]]; then printf '%s\n' "CMS verified a different package kind than ${expected_kind}." >&2; return 1; fi
  printf '%s\n' "${output}"
}

command="${1:-help}"
case "${command}" in
  help|-h|--help) usage ;;
  contracts) request GET '/v1/extensions/contracts' ;;
  catalog) request GET '/v1/extensions/catalog' ;;
  navigation) require_token; request GET '/v1/extensions/navigation' ;;
  ai) require_token; request GET '/v1/extensions/ai' ;;
  theme:validate) require_token; require_file "${2:-}"; request POST '/v1/themes/validate' "${2}" ;;
  theme:install) require_token; require_file "${2:-}"; request POST '/v1/themes/install' '' "$(install_payload "${2}" "${3:-false}")" ;;
  theme:install-zip) require_token; require_file "${2:-}"; upload_zip "${2}" "${3:-false}" theme ;;
  theme:export) require_id "${2:-}"; request GET "/v1/themes/${2}/export" ;;
  theme:activate) require_token; require_id "${2:-}"; request POST "/v1/themes/${2}/activate" ;;
  plugin:validate) require_token; require_file "${2:-}"; request POST '/v1/plugins/validate' "${2}" ;;
  plugin:install) require_token; require_file "${2:-}"; request POST '/v1/plugins/install' '' "$(install_payload "${2}" "${3:-false}")" ;;
  plugin:install-zip) require_token; require_file "${2:-}"; upload_zip "${2}" "${3:-false}" plugin ;;
  plugin:export) require_token; require_id "${2:-}"; request GET "/v1/plugins/${2}/export" ;;
  *) usage >&2; exit 2 ;;
esac
