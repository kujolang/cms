#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/cms.db}"
LIMIT="${CMS_WEBHOOK_ENQUEUE_LIMIT:-200}"
MAX_ATTEMPTS="${CMS_WEBHOOK_MAX_ATTEMPTS:-5}"
SCRIPT_LABEL="Webhook enqueue"

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

if [[ ! -f "${DB_PATH}" ]]; then
	fail "database not found at ${DB_PATH}"
fi

require_command sqlite3
require_command node

sqlite3() {
	command sqlite3 -cmd ".timeout 5000" "$@"
}

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}

decode_hex() {
	printf '%s' "$1" | xxd -r -p
}

parse_detail_field() {
	local details_json="$1"
	local key="$2"
	if [[ -z "${details_json}" ]]; then
		printf ''
		return 0
	fi
	printf '%s' "${details_json}" | node -e '
		const fs = require("fs");
		const key = process.argv[1];
		const raw = fs.readFileSync(0, "utf8");
		let parsed;
		try {
			parsed = JSON.parse(raw);
		} catch {
			process.stdout.write("");
			process.exit(0);
		}
		const value = parsed[key];
		if (value === undefined || value === null) {
			process.stdout.write("");
			process.exit(0);
		}
		if (typeof value === "object") {
			process.stdout.write(JSON.stringify(value));
		} else {
			process.stdout.write(String(value));
		}
	' "${key}"
}

build_payload_json() {
	local event_id="$1"
	local event_type="$2"
	local event_action="$3"
	local entry_id="$4"
	local content_type_key="$5"
	local slug="$6"
	local status="$7"
	local published_at="$8"

	node -e '
		const [eventId, eventType, eventAction, entryIdRaw, contentTypeKey, slug, status, publishedAt] = process.argv.slice(1);
		const nowSec = Math.floor(Date.now() / 1000).toString();
		const entryId = Number.parseInt(entryIdRaw, 10);
		const data = {
			entry_id: Number.isNaN(entryId) ? 0 : entryId,
			content_type_key: contentTypeKey,
			slug,
			status
		};
		if (publishedAt) {
			data.published_at = publishedAt;
		}
		const payload = {
			event_id: eventId,
			event_type: eventType,
			occurred_at: nowSec,
			resource: "entry",
			action: eventAction,
			data
		};
		process.stdout.write(JSON.stringify(payload));
	' "${event_id}" "${event_type}" "${event_action}" "${entry_id}" "${content_type_key}" "${slug}" "${status}" "${published_at}"
}

insert_outbox_for_event() {
	local event_type="$1"
	local event_action="$2"
	local entry_id="$3"
	local content_type_key="$4"
	local slug="$5"
	local status="$6"
	local published_at="$7"
	local audit_id="$8"

	local hooks
	hooks="$(sqlite3 -separator '|' "${DB_PATH}" "SELECT ph.id, hex(ph.handler_url), hex(ph.shared_secret) FROM plugin_hooks ph INNER JOIN plugins p ON p.id = ph.plugin_id WHERE ph.enabled = 1 AND ph.hook_name = '${event_type}' AND p.status = 'active' ORDER BY ph.id ASC;")"
	if [[ -z "${hooks}" ]]; then
		return 0
	fi

	while IFS='|' read -r hook_id handler_url_hex shared_secret_hex; do
		[[ -z "${hook_id}" ]] && continue
		local handler_url shared_secret now_ts event_seed event_id payload_json inserted
		handler_url="$(decode_hex "${handler_url_hex}")"
		shared_secret="$(decode_hex "${shared_secret_hex}")"
		now_ts="$(date +%s)"
		event_seed="${event_type}:${audit_id}:${hook_id}"
		event_id="$(printf '%s' "${event_seed}" | shasum -a 256 | awk '{print substr($1, 1, 24)}')"
		payload_json="$(build_payload_json "${event_id}" "${event_type}" "${event_action}" "${entry_id}" "${content_type_key}" "${slug}" "${status}" "${published_at}")"

		local payload_sql handler_url_sql shared_secret_sql
		payload_sql="$(sql_escape "${payload_json}")"
		handler_url_sql="$(sql_escape "${handler_url}")"
		shared_secret_sql="$(sql_escape "${shared_secret}")"

		inserted="$(sqlite3 "${DB_PATH}" "INSERT OR IGNORE INTO webhook_outbox (hook_id, source_audit_id, event_id, event_type, payload_json, handler_url, shared_secret, status, attempt_count, max_attempts, next_attempt_at, last_error, last_status_code, delivered_at, created_at, updated_at) VALUES (${hook_id}, ${audit_id}, '${event_id}', '${event_type}', '${payload_sql}', '${handler_url_sql}', '${shared_secret_sql}', 'pending', 0, ${MAX_ATTEMPTS}, '${now_ts}', '', 0, '', '${now_ts}', '${now_ts}'); SELECT changes();")"
		if [[ "${inserted}" == "1" ]]; then
			ENQUEUED_TOTAL=$((ENQUEUED_TOTAL + 1))
		fi
	done <<< "${hooks}"
}

sqlite3 "${DB_PATH}" "INSERT OR IGNORE INTO webhook_dispatch_state (id, last_audit_id, updated_at) VALUES (1, 0, strftime('%s','now'));"
LAST_AUDIT_ID="$(sqlite3 "${DB_PATH}" "SELECT last_audit_id FROM webhook_dispatch_state WHERE id = 1;")"
if [[ -z "${LAST_AUDIT_ID}" ]]; then
	LAST_AUDIT_ID="0"
fi

AUDIT_ROWS="$(sqlite3 -separator '|' "${DB_PATH}" "SELECT id, action, target_id, hex(details_json) FROM audit_log WHERE id > ${LAST_AUDIT_ID} AND status_code >= 200 AND status_code < 300 AND action IN ('entry.create', 'entry.update', 'entry.patch', 'entry.delete') ORDER BY id ASC LIMIT ${LIMIT};")"

if [[ -z "${AUDIT_ROWS}" ]]; then
	echo "${SCRIPT_LABEL}: no new audit events"
	exit 0
fi

PROCESSED_TOTAL=0
ENQUEUED_TOTAL=0
SKIPPED_TOTAL=0
HIGHEST_AUDIT_ID="${LAST_AUDIT_ID}"

while IFS='|' read -r audit_id action target_id details_hex; do
	[[ -z "${audit_id}" ]] && continue
	PROCESSED_TOTAL=$((PROCESSED_TOTAL + 1))
	HIGHEST_AUDIT_ID="${audit_id}"

	details_json="$(decode_hex "${details_hex}")"
	content_type_key="$(parse_detail_field "${details_json}" "content_type_key")"
	slug="$(parse_detail_field "${details_json}" "slug")"
	status="$(parse_detail_field "${details_json}" "status")"
	published_at="$(parse_detail_field "${details_json}" "published_at")"

	if [[ "${action}" == "entry.create" ]]; then
		if [[ -z "${content_type_key}" || -z "${slug}" ]]; then
			SKIPPED_TOTAL=$((SKIPPED_TOTAL + 1))
			continue
		fi
		insert_outbox_for_event "entry.created" "created" "${target_id}" "${content_type_key}" "${slug}" "${status}" "" "${audit_id}"
		if [[ "${status}" == "published" ]]; then
			insert_outbox_for_event "entry.published" "published" "${target_id}" "${content_type_key}" "${slug}" "${status}" "${published_at}" "${audit_id}"
		fi
		continue
	fi

	if [[ "${action}" == "entry.update" || "${action}" == "entry.patch" ]]; then
		if [[ -z "${content_type_key}" || -z "${slug}" ]]; then
			SKIPPED_TOTAL=$((SKIPPED_TOTAL + 1))
			continue
		fi
		insert_outbox_for_event "entry.updated" "updated" "${target_id}" "${content_type_key}" "${slug}" "${status}" "" "${audit_id}"
		continue
	fi

	if [[ "${action}" == "entry.delete" ]]; then
		if [[ -z "${content_type_key}" ]]; then
			SKIPPED_TOTAL=$((SKIPPED_TOTAL + 1))
			continue
		fi
		insert_outbox_for_event "entry.deleted" "deleted" "${target_id}" "${content_type_key}" "${slug}" "deleted" "" "${audit_id}"
		continue
	fi

done <<< "${AUDIT_ROWS}"

sqlite3 "${DB_PATH}" "UPDATE webhook_dispatch_state SET last_audit_id = CASE WHEN last_audit_id < ${HIGHEST_AUDIT_ID} THEN ${HIGHEST_AUDIT_ID} ELSE last_audit_id END, updated_at = strftime('%s','now') WHERE id = 1;"

echo "${SCRIPT_LABEL} summary: processed=${PROCESSED_TOTAL} enqueued=${ENQUEUED_TOTAL} skipped=${SKIPPED_TOTAL} last_audit_id=${HIGHEST_AUDIT_ID}"
