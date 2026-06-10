#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${CMS_DB_PATH:-${ROOT_DIR}/data/cms.db}"
LIMIT="${CMS_BACKGROUND_JOB_PROCESS_LIMIT:-50}"
RETRY_BASE_SEC="${CMS_BACKGROUND_JOB_RETRY_BASE_SEC:-20}"
MAX_ATTEMPTS_DEFAULT="${CMS_BACKGROUND_JOB_MAX_ATTEMPTS:-5}"

if [[ ! -f "${DB_PATH}" ]]; then
	echo "Background job processor: database not found at ${DB_PATH}"
	exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Background job processor: sqlite3 is required"
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "Background job processor: node is required"
	exit 1
fi

if ! [[ "${LIMIT}" =~ ^[0-9]+$ ]] || [[ "${LIMIT}" -lt 1 ]]; then
	LIMIT="50"
fi

if ! [[ "${RETRY_BASE_SEC}" =~ ^[0-9]+$ ]] || [[ "${RETRY_BASE_SEC}" -lt 1 ]]; then
	RETRY_BASE_SEC="20"
fi

if ! [[ "${MAX_ATTEMPTS_DEFAULT}" =~ ^[0-9]+$ ]] || [[ "${MAX_ATTEMPTS_DEFAULT}" -lt 1 ]]; then
	MAX_ATTEMPTS_DEFAULT="5"
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

payload_field() {
	local payload_json="$1"
	local key="$2"
	local fallback="${3:-}"

	printf '%s' "${payload_json}" | node -e '
		const fs = require("fs");
		const key = process.argv[1];
		const fallback = process.argv[2] ?? "";
		let parsed;
		try {
			parsed = JSON.parse(fs.readFileSync(0, "utf8"));
		} catch {
			process.stdout.write(fallback);
			process.exit(0);
		}
		const value = parsed[key];
		if (value === undefined || value === null) {
			process.stdout.write(fallback);
			process.exit(0);
		}
		if (typeof value === "object") {
			process.stdout.write(JSON.stringify(value));
			return;
		}
		process.stdout.write(String(value));
	' "${key}" "${fallback}"
}

normalize_result_json() {
	local job_type="$1"
	local output_text="$2"

	node -e '
		const [jobType, rawOutput] = process.argv.slice(1);
		let parsedOutput = rawOutput;
		try {
			parsedOutput = JSON.parse(rawOutput);
		} catch {
			parsedOutput = { message: rawOutput };
		}
		process.stdout.write(JSON.stringify({
			job_type: jobType,
			output: parsedOutput
		}));
	' "${job_type}" "${output_text}"
}

write_audit_row() {
	local action="$1"
	local status_code="$2"
	local job_id="$3"
	local details_json="$4"

	local now_value details_sql
	now_value="$(now_epoch)"
	details_sql="$(sql_escape "${details_json}")"

	sqlite3 "${DB_PATH}" "INSERT INTO audit_log (created_at, ip, method, path, actor, action, status_code, target_type, target_id, details_json) VALUES ('${now_value}', '', 'SYSTEM', '/background-jobs/worker', 'system.background_job', '${action}', ${status_code}, 'background_job', '${job_id}', '${details_sql}');" >/dev/null 2>&1 || true
}

run_scheduler_job() {
	local payload_json="$1"
	local now_ms now_epoch_sec published_ids unpublished_ids published_count unpublished_count

	now_epoch_sec="$(date +%s)"
	now_ms="$((now_epoch_sec * 1000))"

	published_ids="$(sqlite3 "${DB_PATH}" "SELECT id FROM entries WHERE status = 'draft' AND published_at IS NOT NULL AND CASE WHEN instr(CAST(published_at AS TEXT), '-') > 0 THEN CAST(strftime('%s', published_at) AS INTEGER) * 1000 ELSE CAST(published_at AS INTEGER) END <= ${now_ms} ORDER BY id ASC LIMIT 500;")"
	published_count=0
	if [[ -n "${published_ids}" ]]; then
		while IFS= read -r entry_id; do
			[[ -z "${entry_id}" ]] && continue
			sqlite3 "${DB_PATH}" "UPDATE entries SET status = 'published', updated_at = '${now_epoch_sec}' WHERE id = ${entry_id};"
			published_count=$((published_count + 1))
		done <<< "${published_ids}"
	fi

	unpublished_ids="$(sqlite3 "${DB_PATH}" "SELECT id FROM entries WHERE status = 'published' AND unpublish_at IS NOT NULL AND CASE WHEN instr(CAST(unpublish_at AS TEXT), '-') > 0 THEN CAST(strftime('%s', unpublish_at) AS INTEGER) * 1000 ELSE CAST(unpublish_at AS INTEGER) END <= ${now_ms} ORDER BY id ASC LIMIT 500;")"
	unpublished_count=0
	if [[ -n "${unpublished_ids}" ]]; then
		while IFS= read -r entry_id; do
			[[ -z "${entry_id}" ]] && continue
			sqlite3 "${DB_PATH}" "UPDATE entries SET status = 'archived', unpublish_at = NULL, updated_at = '${now_epoch_sec}' WHERE id = ${entry_id};"
			unpublished_count=$((unpublished_count + 1))
		done <<< "${unpublished_ids}"
	fi

	echo "{\"task\":\"scheduler.run\",\"ok\":true,\"processed_at\":\"${now_epoch_sec}\",\"published_count\":${published_count},\"unpublished_count\":${unpublished_count}}"
	return 0
}

run_webhook_enqueue_job() {
	CMS_DB_PATH="${DB_PATH}" \
	bash "${ROOT_DIR}/scripts/enqueue-webhook-outbox.sh"
}

run_webhook_process_job() {
	CMS_DB_PATH="${DB_PATH}" \
	CMS_WEBHOOK_CONNECT_TIMEOUT_SEC="${CMS_WEBHOOK_CONNECT_TIMEOUT_SEC:-3}" \
	CMS_WEBHOOK_MAX_TIME_SEC="${CMS_WEBHOOK_MAX_TIME_SEC:-10}" \
	bash "${ROOT_DIR}/scripts/process-webhook-outbox.sh"
}

run_media_maintenance_job() {
	CMS_DB_PATH="${DB_PATH}" \
	bash "${ROOT_DIR}/scripts/media-background-maintenance.sh"
}

run_job_by_type() {
	local job_type="$1"
	local payload_json="$2"

	if [[ "${job_type}" == "scheduler.run" ]]; then
		run_scheduler_job "${payload_json}"
		return $?
	fi

	if [[ "${job_type}" == "webhook.enqueue" ]]; then
		run_webhook_enqueue_job
		return $?
	fi

	if [[ "${job_type}" == "webhook.process" ]]; then
		run_webhook_process_job
		return $?
	fi

	if [[ "${job_type}" == "media.maintain" ]]; then
		run_media_maintenance_job
		return $?
	fi

	echo "unsupported job_type ${job_type}"
	return 1
}

rows="$(sqlite3 -separator '|' "${DB_PATH}" "SELECT id, job_type, hex(payload_json), attempt_count, max_attempts FROM background_jobs WHERE status IN ('pending','retry') AND CAST(run_after AS INTEGER) <= CAST(strftime('%s','now') AS INTEGER) ORDER BY id ASC LIMIT ${LIMIT};")"

if [[ -z "${rows}" ]]; then
	echo "Background job processor: no due jobs"
	exit 0
fi

processed=0
completed=0
retried=0
dead_lettered=0

while IFS='|' read -r job_id job_type payload_hex attempt_count max_attempts; do
	[[ -z "${job_id}" ]] && continue

	processed=$((processed + 1))
	payload_json="$(decode_hex "${payload_hex}")"
	if [[ -z "${payload_json}" ]]; then
		payload_json="{}"
	fi

	if ! [[ "${attempt_count}" =~ ^[0-9]+$ ]]; then
		attempt_count="0"
	fi

	if ! [[ "${max_attempts}" =~ ^[0-9]+$ ]] || [[ "${max_attempts}" -lt 1 ]]; then
		max_attempts="${MAX_ATTEMPTS_DEFAULT}"
	fi

	now_value="$(now_epoch)"
	sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'running', started_at = '${now_value}', updated_at = '${now_value}' WHERE id = ${job_id} AND status IN ('pending','retry');"

	current_status="$(sqlite3 "${DB_PATH}" "SELECT status FROM background_jobs WHERE id = ${job_id};")"
	if [[ "${current_status}" != "running" ]]; then
		continue
	fi

	write_audit_row "background.job.started" "202" "${job_id}" "{\"job_type\":\"${job_type}\",\"attempt\":$((attempt_count + 1))}"

	set +e
	job_output="$(run_job_by_type "${job_type}" "${payload_json}" 2>&1)"
	job_exit_code=$?
	set -e

	next_attempt_count=$((attempt_count + 1))

	if [[ ${job_exit_code} -eq 0 ]]; then
		result_json="$(normalize_result_json "${job_type}" "${job_output}")"
		result_sql="$(sql_escape "${result_json}")"
		now_value="$(now_epoch)"
		sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'completed', attempt_count = ${next_attempt_count}, last_error = NULL, result_json = '${result_sql}', completed_at = '${now_value}', updated_at = '${now_value}' WHERE id = ${job_id};"
		write_audit_row "background.job.completed" "200" "${job_id}" "${result_json}"
		completed=$((completed + 1))
		echo "[COMPLETED] job_id=${job_id} type=${job_type}"
		continue
	fi

	error_message="${job_output}"
	if [[ -z "${error_message}" ]]; then
		error_message="job_exit_${job_exit_code}"
	fi
	error_sql="$(sql_escape "${error_message}")"
	now_value="$(now_epoch)"

	if [[ ${next_attempt_count} -ge ${max_attempts} ]]; then
		sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'dead_letter', attempt_count = ${next_attempt_count}, last_error = '${error_sql}', updated_at = '${now_value}' WHERE id = ${job_id};"
		sqlite3 "${DB_PATH}" "INSERT OR REPLACE INTO background_job_dead_letters (job_id, job_type, payload_json, attempt_count, max_attempts, last_error, failed_at, created_at) SELECT id, job_type, payload_json, attempt_count, max_attempts, '${error_sql}', '${now_value}', '${now_value}' FROM background_jobs WHERE id = ${job_id};"
		write_audit_row "background.job.dead_letter" "500" "${job_id}" "{\"job_type\":\"${job_type}\",\"error\":\"${error_sql}\",\"attempt\":${next_attempt_count},\"max_attempts\":${max_attempts}}"
		dead_lettered=$((dead_lettered + 1))
		echo "[DEAD-LETTER] job_id=${job_id} type=${job_type}"
		continue
	fi

	next_run_after=$((now_value + (RETRY_BASE_SEC * next_attempt_count)))
	sqlite3 "${DB_PATH}" "UPDATE background_jobs SET status = 'retry', attempt_count = ${next_attempt_count}, last_error = '${error_sql}', run_after = '${next_run_after}', updated_at = '${now_value}' WHERE id = ${job_id};"
	write_audit_row "background.job.retry" "429" "${job_id}" "{\"job_type\":\"${job_type}\",\"attempt\":${next_attempt_count},\"next_run_after\":\"${next_run_after}\"}"
	retried=$((retried + 1))
	echo "[RETRY] job_id=${job_id} type=${job_type}"
done <<< "${rows}"

echo "Background job processor summary: processed=${processed} completed=${completed} retried=${retried} dead_lettered=${dead_lettered}"
