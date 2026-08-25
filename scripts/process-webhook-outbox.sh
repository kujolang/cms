#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
LIMIT="${CMS_WEBHOOK_PROCESS_LIMIT:-50}"
RETRY_BASE_SEC="${CMS_WEBHOOK_RETRY_BASE_SEC:-30}"
CONNECT_TIMEOUT_SEC="${CMS_WEBHOOK_CONNECT_TIMEOUT_SEC:-3}"
MAX_TIME_SEC="${CMS_WEBHOOK_MAX_TIME_SEC:-10}"
ALLOW_HTTP="${CMS_PLUGIN_HOOK_ALLOW_HTTP:-false}"
ALLOW_PRIVATE="${CMS_PLUGIN_HOOK_ALLOW_PRIVATE:-false}"
SCRIPT_LABEL="Webhook outbox processor"

fail() {
	echo "${SCRIPT_LABEL}: $1"
	exit 1
}

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		fail "${command_name} is required"
	fi
}

delivery_status() {
	local status="$1"
	local outbox_id="$2"
	local event_type="$3"
	local details="$4"
	echo "[${status}] outbox_id=${outbox_id} event=${event_type} ${details}"
}

if [[ ! -f "${DB_PATH}" ]]; then
	fail "database not found at ${DB_PATH}"
fi

require_command sqlite3
require_command python3

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}

decode_hex() {
	printf '%s' "$1" | xxd -r -p
}

now_epoch() {
	date +%s
}

resolve_handler_target() {
	local handler_url="$1"
	python3 - "${handler_url}" "${ALLOW_HTTP}" "${ALLOW_PRIVATE}" <<'PY'
import ipaddress
import socket
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
allow_http = sys.argv[2].strip().lower() in {"1", "true", "yes", "on"}
allow_private = sys.argv[3].strip().lower() in {"1", "true", "yes", "on"}

if url.scheme not in ({"http", "https"} if allow_http else {"https"}):
    raise SystemExit(1)
if not url.hostname or url.username is not None or url.password is not None:
    raise SystemExit(1)

labels = url.hostname.lower().split(".")
numeric_alias = bool(labels)
for label in labels:
    if label.startswith("0x"):
        try:
            int(label[2:], 16)
        except ValueError:
            numeric_alias = False
            break
    elif not label.isdigit():
        numeric_alias = False
        break
if numeric_alias:
    canonical_decimal = len(labels) == 4 and all(
        label.isdigit() and (label == "0" or not label.startswith("0")) and 0 <= int(label, 10) <= 255
        for label in labels
    )
    if not canonical_decimal:
        raise SystemExit(1)

port = url.port or (443 if url.scheme == "https" else 80)
try:
    addresses = sorted({item[4][0] for item in socket.getaddrinfo(url.hostname, port, type=socket.SOCK_STREAM)})
except (OSError, ValueError):
    raise SystemExit(1)
if not addresses:
    raise SystemExit(1)

translation_networks = (
    ipaddress.ip_network("64:ff9b::/96"),
    ipaddress.ip_network("64:ff9b:1::/48"),
    ipaddress.ip_network("2001::/32"),
    ipaddress.ip_network("2002::/16"),
)
for address in addresses:
    parsed = ipaddress.ip_address(address)
    if not allow_private and not parsed.is_global:
        raise SystemExit(1)
    if not allow_private and parsed.version == 6 and any(parsed in network for network in translation_networks):
        raise SystemExit(1)

selected = addresses[0]
if ":" in selected:
    selected = f"[{selected}]"
try:
    ipaddress.ip_address(url.hostname)
    output_host = "DIRECT"
except ValueError:
    output_host = url.hostname
print(f"{output_host}|{port}|{selected}")
PY
}

rows="$(sqlite3 -separator '|' "${DB_PATH}" "SELECT id, hook_id, event_id, event_type, hex(payload_json), hex(handler_url), hex(shared_secret), attempt_count, max_attempts FROM webhook_outbox WHERE status IN ('pending','retry') AND CAST(next_attempt_at AS INTEGER) <= CAST(strftime('%s','now') AS INTEGER) ORDER BY id ASC LIMIT ${LIMIT};")"

if [[ -z "${rows}" ]]; then
	echo "${SCRIPT_LABEL}: no due deliveries"
	exit 0
fi

processed=0
delivered=0
retried=0
dead_lettered=0

while IFS='|' read -r outbox_id hook_id event_id event_type payload_hex handler_url_hex shared_secret_hex attempt_count max_attempts; do
	[[ -z "${outbox_id}" ]] && continue
	processed=$((processed + 1))

	payload_json="$(decode_hex "${payload_hex}")"
	handler_url="$(decode_hex "${handler_url_hex}")"
	shared_secret="$(decode_hex "${shared_secret_hex}")"

	signature="$(printf '%s' "${payload_json}.${shared_secret}" | shasum -a 256 | awk '{print $1}')"
	response_file="$(mktemp)"
	policy_error=""
	resolved_target=""
	if ! resolved_target="$(resolve_handler_target "${handler_url}")"; then
		policy_error="egress_policy_denied"
	fi

	if [[ -n "${policy_error}" ]]; then
		http_status="000"
		curl_exit_code=90
	else
		IFS='|' read -r resolved_host resolved_port resolved_ip <<< "${resolved_target}"
		curl_resolution_args=( --noproxy "*" )
		if [[ "${resolved_host}" != "DIRECT" ]]; then
			curl_resolution_args+=( --resolve "${resolved_host}:${resolved_port}:${resolved_ip}" )
		fi
		set +e
		http_status="$(curl "${curl_resolution_args[@]}" -sS -o "${response_file}" -w "%{http_code}" -X POST "${handler_url}" \
			-H "Content-Type: application/json" \
			-H "X-CMS-Webhook-Event: ${event_type}" \
			-H "X-CMS-Webhook-Id: ${event_id}" \
			-H "X-CMS-Webhook-Signature: sha256=${signature}" \
			--connect-timeout "${CONNECT_TIMEOUT_SEC}" \
			--max-time "${MAX_TIME_SEC}" \
			--data "${payload_json}")"
		curl_exit_code=$?
		set -e
	fi

	now_value="$(now_epoch)"
	if [[ ${curl_exit_code} -eq 0 && "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
		next_attempt_count=$((attempt_count + 1))
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'delivered', attempt_count = ${next_attempt_count}, last_error = NULL, last_status_code = ${http_status}, delivered_at = '${now_value}', updated_at = '${now_value}' WHERE id = ${outbox_id};"
		delivered=$((delivered + 1))
		delivery_status "DELIVERED" "${outbox_id}" "${event_type}" "status=${http_status}"
		rm -f "${response_file}"
		continue
	fi

	next_attempt_count=$((attempt_count + 1))
	error_message=""
	if [[ -n "${policy_error}" ]]; then
		error_message="${policy_error}"
	elif [[ ${curl_exit_code} -ne 0 ]]; then
		error_message="curl_exit_${curl_exit_code}"
	else
		error_message="http_${http_status}"
	fi
	escaped_error="$(sql_escape "${error_message}")"

	if [[ ${next_attempt_count} -ge ${max_attempts} ]]; then
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'dead_letter', attempt_count = ${next_attempt_count}, last_error = '${escaped_error}', last_status_code = ${http_status:-0}, updated_at = '${now_value}' WHERE id = ${outbox_id};"
		sqlite3 "${DB_PATH}" "INSERT OR REPLACE INTO webhook_dead_letters (outbox_id, hook_id, event_id, event_type, payload_json, handler_url, shared_secret, attempt_count, last_error, last_status_code, failed_at, created_at) SELECT id, hook_id, event_id, event_type, payload_json, handler_url, shared_secret, attempt_count, '${escaped_error}', ${http_status:-0}, '${now_value}', '${now_value}' FROM webhook_outbox WHERE id = ${outbox_id};"
		dead_lettered=$((dead_lettered + 1))
		delivery_status "DEAD-LETTER" "${outbox_id}" "${event_type}" "attempts=${next_attempt_count}/${max_attempts}"
	else
		next_attempt_at=$((now_value + (RETRY_BASE_SEC * next_attempt_count)))
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'retry', attempt_count = ${next_attempt_count}, last_error = '${escaped_error}', last_status_code = ${http_status:-0}, next_attempt_at = '${next_attempt_at}', updated_at = '${now_value}' WHERE id = ${outbox_id};"
		retried=$((retried + 1))
		delivery_status "RETRY" "${outbox_id}" "${event_type}" "attempts=${next_attempt_count}/${max_attempts}"
	fi

	rm -f "${response_file}"
done <<< "${rows}"

echo "${SCRIPT_LABEL} summary: processed=${processed} delivered=${delivered} retried=${retried} dead_lettered=${dead_lettered}"
