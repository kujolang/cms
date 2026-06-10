#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
LIMIT="${CMS_WEBHOOK_PROCESS_LIMIT:-50}"
RETRY_BASE_SEC="${CMS_WEBHOOK_RETRY_BASE_SEC:-30}"
CONNECT_TIMEOUT_SEC="${CMS_WEBHOOK_CONNECT_TIMEOUT_SEC:-3}"
MAX_TIME_SEC="${CMS_WEBHOOK_MAX_TIME_SEC:-10}"

if [[ ! -f "${DB_PATH}" ]]; then
	echo "Webhook outbox processor: database not found at ${DB_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Webhook outbox processor: sqlite3 is required"
	exit 1
fi

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}

decode_hex() {
	printf '%s' "$1" | xxd -r -p
}

now_epoch() {
	date +%s
}

rows="$(sqlite3 -separator '|' "${DB_PATH}" "SELECT id, hook_id, event_id, event_type, hex(payload_json), hex(handler_url), hex(shared_secret), attempt_count, max_attempts FROM webhook_outbox WHERE status IN ('pending','retry') AND CAST(next_attempt_at AS INTEGER) <= CAST(strftime('%s','now') AS INTEGER) ORDER BY id ASC LIMIT ${LIMIT};")"

if [[ -z "${rows}" ]]; then
	echo "Webhook outbox processor: no due deliveries"
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

	set +e
	http_status="$(curl -sS -o "${response_file}" -w "%{http_code}" -X POST "${handler_url}" \
		-H "Content-Type: application/json" \
		-H "X-Kujo-Webhook-Event: ${event_type}" \
		-H "X-Kujo-Webhook-Id: ${event_id}" \
		-H "X-Kujo-Webhook-Signature: sha256=${signature}" \
		--connect-timeout "${CONNECT_TIMEOUT_SEC}" \
		--max-time "${MAX_TIME_SEC}" \
		--data "${payload_json}")"
	curl_exit_code=$?
	set -e

	now_value="$(now_epoch)"
	if [[ ${curl_exit_code} -eq 0 && "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
		next_attempt_count=$((attempt_count + 1))
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'delivered', attempt_count = ${next_attempt_count}, last_error = NULL, last_status_code = ${http_status}, delivered_at = '${now_value}', updated_at = '${now_value}' WHERE id = ${outbox_id};"
		delivered=$((delivered + 1))
		echo "[DELIVERED] outbox_id=${outbox_id} event=${event_type} status=${http_status}"
		rm -f "${response_file}"
		continue
	fi

	next_attempt_count=$((attempt_count + 1))
	error_message=""
	if [[ ${curl_exit_code} -ne 0 ]]; then
		error_message="curl_exit_${curl_exit_code}"
	else
		error_message="http_${http_status}"
	fi
	escaped_error="$(sql_escape "${error_message}")"

	if [[ ${next_attempt_count} -ge ${max_attempts} ]]; then
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'dead_letter', attempt_count = ${next_attempt_count}, last_error = '${escaped_error}', last_status_code = ${http_status:-0}, updated_at = '${now_value}' WHERE id = ${outbox_id};"
		sqlite3 "${DB_PATH}" "INSERT OR REPLACE INTO webhook_dead_letters (outbox_id, hook_id, event_id, event_type, payload_json, handler_url, shared_secret, attempt_count, last_error, last_status_code, failed_at, created_at) SELECT id, hook_id, event_id, event_type, payload_json, handler_url, shared_secret, attempt_count, '${escaped_error}', ${http_status:-0}, '${now_value}', '${now_value}' FROM webhook_outbox WHERE id = ${outbox_id};"
		dead_lettered=$((dead_lettered + 1))
		echo "[DEAD-LETTER] outbox_id=${outbox_id} event=${event_type} attempts=${next_attempt_count}/${max_attempts}"
	else
		next_attempt_at=$((now_value + (RETRY_BASE_SEC * next_attempt_count)))
		sqlite3 "${DB_PATH}" "UPDATE webhook_outbox SET status = 'retry', attempt_count = ${next_attempt_count}, last_error = '${escaped_error}', last_status_code = ${http_status:-0}, next_attempt_at = '${next_attempt_at}', updated_at = '${now_value}' WHERE id = ${outbox_id};"
		retried=$((retried + 1))
		echo "[RETRY] outbox_id=${outbox_id} event=${event_type} attempts=${next_attempt_count}/${max_attempts}"
	fi

	rm -f "${response_file}"
done <<< "${rows}"

echo "Webhook outbox processor summary: processed=${processed} delivered=${delivered} retried=${retried} dead_lettered=${dead_lettered}"
