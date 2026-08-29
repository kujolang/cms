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
    '  theme:validate <manifest>         Validate kujo-theme.json.' \
    '  theme:install <manifest> [active] Install or update a theme package.' \
    '  theme:install-zip <archive> [active] Verify and install a theme ZIP.' \
    '  theme:export <id>                 Export a secret-free theme manifest.' \
    '  theme:activate <id>               Activate an installed theme.' \
    '  plugin:validate <manifest>        Validate kujo-plugin.json.' \
    '  plugin:install <manifest> [active] Install or update a plugin package.' \
    '  plugin:install-zip <archive> [active] Verify and install a plugin ZIP.' \
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
  curl "${args[@]}" "${CMS_EXT_BASE_URL%/}${path}"
  printf '\n'
}

install_payload() {
  local manifest="$1"
  local active="${2:-false}"
  if [[ "${active}" == "active" || "${active}" == "true" ]]; then active=true; else active=false; fi
  jq -c --argjson active "${active}" '{manifest:.,activate:$active}' "${manifest}"
}

install_zip_payload() {
  local archive_path="$1"
  local active_value="${2:-false}"
  if [[ "${active_value}" == "active" || "${active_value}" == "true" ]]; then active_value=true; else active_value=false; fi
  node "${ROOT_DIR}/scripts/read-extension-package.mjs" "${archive_path}" | jq -c --argjson activate "${active_value}" '. + {activate: $activate}'
}

command="${1:-help}"
case "${command}" in
  help|-h|--help) usage ;;
  contracts) request GET '/v1/extensions/contracts' ;;
  catalog) request GET '/v1/extensions/catalog' ;;
  theme:validate) require_token; require_file "${2:-}"; request POST '/v1/themes/validate' "${2}" ;;
  theme:install) require_token; require_file "${2:-}"; request POST '/v1/themes/install' '' "$(install_payload "${2}" "${3:-false}")" ;;
  theme:install-zip) require_token; require_file "${2:-}"; request POST '/v1/themes/install' '' "$(install_zip_payload "${2}" "${3:-false}")" ;;
  theme:export) require_id "${2:-}"; request GET "/v1/themes/${2}/export" ;;
  theme:activate) require_token; require_id "${2:-}"; request POST "/v1/themes/${2}/activate" ;;
  plugin:validate) require_token; require_file "${2:-}"; request POST '/v1/plugins/validate' "${2}" ;;
  plugin:install) require_token; require_file "${2:-}"; request POST '/v1/plugins/install' '' "$(install_payload "${2}" "${3:-false}")" ;;
  plugin:install-zip) require_token; require_file "${2:-}"; request POST '/v1/plugins/install' '' "$(install_zip_payload "${2}" "${3:-false}")" ;;
  plugin:export) require_token; require_id "${2:-}"; request GET "/v1/plugins/${2}/export" ;;
  *) usage >&2; exit 2 ;;
esac
