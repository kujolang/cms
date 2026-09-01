#!/usr/bin/env bash
set -euo pipefail

CMS_AI_BASE_URL="${CMS_BASE_URL:-http://127.0.0.1:4200}"
CMS_AI_TOKEN="${CMS_API_TOKEN:-}"

usage() {
  printf '%s\n' \
    'Usage: bash scripts/cms-ai.sh <command> [arguments]' \
    '' \
    'Commands:' \
    '  status                              Show connector and interoperability status.' \
    '  connectors                          List Kujo connectors without secret values.' \
    '  ability:enable <namespace/name>      Enable a built-in ability.' \
    '  ability:disable <namespace/name>     Disable a built-in ability.' \
    '  connector:enable <key>              Activate a configured connector.' \
    '  connector:disable <key>             Deactivate a connector.' \
    '  connector:health <key>              Probe a configured connector health endpoint.' \
    '  categories                          List ability categories.' \
    '  definitions                         List portable kujo.ability/v1 definitions.' \
    '  list [category]                     List abilities, optionally by category.' \
    '  get <namespace/name>                Inspect one ability.' \
    '  run <namespace/name> [input-json]   Execute an ability with a JSON input object.' \
    '  approve <namespace/name> <invocation-id>  Approve a pending mutating invocation.' \
    '  run-approved <namespace/name> <invocation-id> <approval-id> <idempotency-key> [input-json]' \
    '                                      Execute the exact approved invocation once.' \
    '  mcp-tools                           List MCP-ready tool descriptors.' \
    '  webmcp                              Show the public WebMCP manifest.' \
    '  webmcp-tools                        List public browser tool descriptors.' \
    '  webmcp-index [limit] [offset]       Read the published-content index.' \
    '' \
    'Environment: CMS_BASE_URL and CMS_API_TOKEN.'
}

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local idempotency_key="${4:-}"
  local approval_id="${5:-}"
  local args=(--fail-with-body --silent --show-error -X "${method}" -H 'Accept: application/json')
  if [[ -n "${CMS_AI_TOKEN}" ]]; then args+=(-H "Authorization: Bearer ${CMS_AI_TOKEN}"); fi
  if [[ -n "${body}" ]]; then args+=(-H 'Content-Type: application/json' --data "${body}"); fi
  if [[ -n "${idempotency_key}" ]]; then args+=(-H "Idempotency-Key: ${idempotency_key}"); fi
  if [[ -n "${approval_id}" ]]; then args+=(-H "X-Ability-Approval: ${approval_id}"); fi
  curl "${args[@]}" "${CMS_AI_BASE_URL%/}${path}"
  printf '\n'
}

require_token() {
  if [[ -z "${CMS_AI_TOKEN}" ]]; then printf '%s\n' 'CMS_API_TOKEN is required for this command.' >&2; exit 2; fi
}

ability_path() {
  local name="$1"
  if [[ ! "${name}" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then usage >&2; exit 2; fi
  printf '%s' "${name}"
}

command="${1:-help}"
case "${command}" in
  help|-h|--help) usage ;;
  status) require_token; request POST '/v1/abilities/ai/integration-status/run' '{"input":{}}' ;;
  connectors) require_token; request GET '/v1/ai/connectors' ;;
  ability:enable|ability:disable)
    require_token
    name="$(ability_path "${2:-}")"
    enabled=false
    if [[ "${command}" == 'ability:enable' ]]; then enabled=true; fi
    request PATCH "/v1/abilities/${name}" "{\"enabled\":${enabled}}"
    ;;
  connector:enable|connector:disable)
    require_token
    key="${2:-}"
    if [[ ! "${key}" =~ ^[a-z0-9_-]+$ ]]; then usage >&2; exit 2; fi
    enabled=false
    if [[ "${command}" == 'connector:enable' ]]; then enabled=true; fi
    request PATCH "/v1/ai/connectors/${key}" "{\"enabled\":${enabled}}"
    ;;
  connector:health)
    require_token
    key="${2:-}"
    if [[ ! "${key}" =~ ^[a-z0-9_-]+$ ]]; then usage >&2; exit 2; fi
    request POST "/v1/ai/connectors/${key}/health" '{}'
    ;;
  categories) require_token; request GET '/v1/abilities/categories' ;;
  definitions) require_token; request GET '/v1/abilities/definitions' ;;
  list)
    require_token
    category="${2:-}"
    path='/v1/abilities'
    if [[ -n "${category}" ]]; then path="${path}?category=${category}"; fi
    request GET "${path}"
    ;;
  get)
    require_token
    name="$(ability_path "${2:-}")"
    request GET "/v1/abilities/${name}"
    ;;
  run)
    require_token
    name="$(ability_path "${2:-}")"
    input="${3:-}"
    if [[ -z "${input}" ]]; then input='{}'; fi
    request POST "/v1/abilities/${name}/run" "{\"input\":${input}}"
    ;;
  approve)
    require_token
    name="$(ability_path "${2:-}")"
    invocation_id="${3:-}"
    if [[ -z "${invocation_id}" ]]; then usage >&2; exit 2; fi
    request POST "/v1/abilities/${name}/approvals" "{\"invocation_id\":\"${invocation_id}\"}"
    ;;
  run-approved)
    require_token
    name="$(ability_path "${2:-}")"
    invocation_id="${3:-}"
    approval_id="${4:-}"
    idempotency_key="${5:-}"
    input="${6:-}"
    if [[ -z "${input}" ]]; then input='{}'; fi
    if [[ -z "${invocation_id}" || -z "${approval_id}" || -z "${idempotency_key}" ]]; then usage >&2; exit 2; fi
    request POST "/v1/abilities/${name}/run" "{\"invocation_id\":\"${invocation_id}\",\"input\":${input}}" "${idempotency_key}" "${approval_id}"
    ;;
  mcp-tools) require_token; request GET '/v1/ai/mcp/tools' ;;
  webmcp) request GET '/v1/webmcp' ;;
  webmcp-tools) request GET '/v1/webmcp/tools' ;;
  webmcp-index)
    limit="${2:-100}"
    offset="${3:-0}"
    if [[ ! "${limit}" =~ ^[0-9]+$ || ! "${offset}" =~ ^[0-9]+$ ]]; then usage >&2; exit 2; fi
    request GET "/.well-known/kujo-site-index.json?limit=${limit}&offset=${offset}"
    ;;
  *) usage >&2; exit 2 ;;
esac
