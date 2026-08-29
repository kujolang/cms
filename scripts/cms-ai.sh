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
    '  categories                          List ability categories.' \
    '  list [category]                     List abilities, optionally by category.' \
    '  get <namespace/name>                Inspect one ability.' \
    '  run <namespace/name> [input-json]   Execute an ability with a JSON input object.' \
    '  mcp-tools                           List MCP-ready tool descriptors.' \
    '' \
    'Environment: CMS_BASE_URL and CMS_API_TOKEN.'
}

if [[ -z "${CMS_AI_TOKEN}" ]]; then
  printf '%s\n' 'CMS_API_TOKEN is required.' >&2
  exit 2
fi

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local args=(--fail-with-body --silent --show-error -X "${method}" -H 'Accept: application/json' -H "Authorization: Bearer ${CMS_AI_TOKEN}")
  if [[ -n "${body}" ]]; then args+=(-H 'Content-Type: application/json' --data "${body}"); fi
  curl "${args[@]}" "${CMS_AI_BASE_URL%/}${path}"
  printf '\n'
}

ability_path() {
  local name="$1"
  if [[ ! "${name}" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then usage >&2; exit 2; fi
  printf '%s' "${name}"
}

command="${1:-help}"
case "${command}" in
  help|-h|--help) usage ;;
  status) request POST '/v1/abilities/ai/integration-status/run' '{"input":{}}' ;;
  connectors) request GET '/v1/ai/connectors' ;;
  categories) request GET '/v1/abilities/categories' ;;
  list)
    category="${2:-}"
    path='/v1/abilities'
    if [[ -n "${category}" ]]; then path="${path}?category=${category}"; fi
    request GET "${path}"
    ;;
  get)
    name="$(ability_path "${2:-}")"
    request GET "/v1/abilities/${name}"
    ;;
  run)
    name="$(ability_path "${2:-}")"
    input="${3:-}"
    if [[ -z "${input}" ]]; then input='{}'; fi
    request POST "/v1/abilities/${name}/run" "{\"input\":${input}}"
    ;;
  mcp-tools) request GET '/v1/ai/mcp/tools' ;;
  *) usage >&2; exit 2 ;;
esac
