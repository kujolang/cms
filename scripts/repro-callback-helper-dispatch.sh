#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

if [[ -n "${KUJO_BIN:-}" ]]; then
	KUJO_BIN_PATH="${KUJO_BIN}"
elif command -v kujo >/dev/null 2>&1; then
	KUJO_BIN_PATH="$(command -v kujo)"
elif [[ -x "${ROOT_DIR}/../kujo/target/debug/kujo" ]]; then
	KUJO_BIN_PATH="${ROOT_DIR}/../kujo/target/debug/kujo"
else
	echo "Unable to locate Kujo runtime binary. Set KUJO_BIN to continue."
	exit 1
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kujo-cms-callback-helper-repro.XXXXXX")"
WORK_DIR="${WORK_ROOT}/work"

pick_free_port() {
	local candidate="$1"
	while lsof -iTCP:"${candidate}" -sTCP:LISTEN -t >/dev/null 2>&1; do
		candidate="$((candidate + 1))"
	done
	echo "${candidate}"
}

BASE_PORT="${CMS_REPRO_PORT_BASE:-$((52100 + RANDOM % 400))}"
DELIVERY_PORT="${CMS_REPRO_DELIVERY_PORT:-$(pick_free_port "$((BASE_PORT + 1))")}"
TENANCY_PORT="${CMS_REPRO_TENANCY_PORT:-$(pick_free_port "$((BASE_PORT + 2))")}"
DELIVERY_LOG="${RESULTS_DIR}/repro_callback_helper_dispatch_delivery.log"
TENANCY_LOG="${RESULTS_DIR}/repro_callback_helper_dispatch_tenancy.log"

cleanup() {
	rm -rf "${WORK_ROOT}" || true
}
trap cleanup EXIT

prepare_worktree() {
	rm -rf "${WORK_DIR}" || true
	mkdir -p "${WORK_DIR}"
	rsync -a --exclude '.git' --exclude 'results' "${ROOT_DIR}/" "${WORK_DIR}/"
}

apply_delivery_repro_patch() {
	local delivery_file="${WORK_DIR}/backend/routes/delivery.kujo"
	perl -0pi -e 's/\t\tif type\(err\) != "null" \{\n\t\t\treturn fail\(cfg, 500, "db_query_failed", "Failed to build sitemap", \{\}\)\n\t\t\}\n\n\t\txml := "\<\?xml version=\\"1\.0\\" encoding=\\"UTF-8\\"\?\>\\n"/\t\tif type\(err\) != "null" \{\n\t\t\treturn fail\(cfg, 500, "db_query_failed", "Failed to build sitemap", \{\}\)\n\t\t\}\n\n\t\thelper_err := null\n\t\txml := ""\n\t\ttry {\n\t\t\txml = build_sitemap_xml\(cfg, rows\)\n\t\t} except e {\n\t\t\thelper_err = e\n\t\t}\n\t\tif type\(helper_err\) != "null" {\n\t\t\treturn api_text\(500, "debug-helper-error: " + to_string\(helper_err\), cfg\)\n\t\t}\n\t\treturn api_text\(200, xml, cfg\)\n\n\t\txml := "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>\\n"/s' "${delivery_file}"

	if ! grep -q 'xml = build_sitemap_xml(cfg, rows)' "${delivery_file}"; then
		echo "Failed to apply delivery callback-helper repro patch"
		exit 1
	fi
}

apply_tenancy_repro_patch() {
	local tenancy_file="${WORK_DIR}/backend/routes/tenancy.kujo"
	perl -0pi -e 's/scope_global := false\n\t\tauth_context := dict_get_or\(guard, "auth", \{\}\)\n\t\tpermissions := dict_get_or\(auth_context, "permissions", \[\]\)\n\t\tif type\(permissions\) == "array" \{\n\t\t\tfor permission in permissions \{\n\t\t\t\tif trim\(to_string\(permission\)\) == "\*" \{\n\t\t\t\t\tscope_global = true\n\t\t\t\t\}\n\t\t\t\}\n\t\t\}\n\t\tif scope_global == false \{\n\t\t\treturn fail\(cfg, 403, "tenant_scope_denied", "This token is not allowed to perform global tenant actions", \{\n\t\t\t\t"required_scope": "global"\n\t\t\t\}\)\n\t\t\}/auth_context := dict_get_or\(guard, "auth", \{\}\)\n\t\tscope_check := {"ok": false}\n\t\thelper_err := null\n\t\ttry {\n\t\t\tscope_check = ensure_global_tenant_access\(auth_context, cfg\)\n\t\t} except e {\n\t\t\thelper_err = e\n\t\t}\n\t\tif type\(helper_err\) != "null" {\n\t\t\treturn api_text\(500, "debug-tenant-helper-error: " + to_string\(helper_err\), cfg\)\n\t\t}\n\t\tif scope_check\["ok"\] == false \{\n\t\t\treturn scope_check\["response"\]\n\t\t\}/s' "${tenancy_file}"

	if ! grep -q 'scope_check = ensure_global_tenant_access(auth_context, cfg)' "${tenancy_file}"; then
		echo "Failed to apply tenancy callback-helper repro patch"
		exit 1
	fi
}

run_expect_failure() {
	local label="$1"
	local port="$2"
	local script_path="$3"
	local fail_marker="$4"
	local log_path="$5"
	local extra_marker="$6"

	set +e
	(
		cd "${WORK_DIR}"
		CMS_TEST_PORT="${port}" KUJO_BIN="${KUJO_BIN_PATH}" bash "${script_path}"
	) >"${log_path}" 2>&1
	local exit_code=$?
	set -e

	if [[ "${exit_code}" -eq 0 ]]; then
		echo "[FAIL] ${label}: expected failure but command succeeded"
		echo "Log: ${log_path}"
		exit 1
	fi

	if ! grep -Fq "${fail_marker}" "${log_path}"; then
		echo "[FAIL] ${label}: expected marker not found: ${fail_marker}"
		echo "Log: ${log_path}"
		exit 1
	fi

	if ! grep -Fq "${extra_marker}" "${log_path}"; then
		echo "[FAIL] ${label}: expected runtime marker not found: ${extra_marker}"
		echo "Log: ${log_path}"
		exit 1
	fi

	echo "[PASS] ${label}: reproduced expected callback-helper regression"
}

echo "Running callback-helper dispatch repro in isolated worktree: ${WORK_ROOT}"

echo "[Step] Delivery helper-dispatch regression"
prepare_worktree
apply_delivery_repro_patch
run_expect_failure \
	"delivery /sitemap.xml helper-dispatch" \
	"${DELIVERY_PORT}" \
	"scripts/integration-stage2-round2-sitemaps.sh" \
	"[FAIL] base sitemap: expected status 200, got 500" \
	"${DELIVERY_LOG}" \
	"Undefined variable: build_sitemap_xml"

echo "[Step] Tenancy helper-dispatch regression"
prepare_worktree
apply_tenancy_repro_patch
run_expect_failure \
	"tenancy POST /v1/tenants helper-dispatch" \
	"${TENANCY_PORT}" \
	"scripts/integration-multitenant.sh" \
	"[FAIL] create tenant alpha: expected status 201, got 500" \
	"${TENANCY_LOG}" \
	"Undefined variable: ensure_global_tenant_access"

echo "Repro complete. Logs:"
echo "- ${DELIVERY_LOG}"
echo "- ${TENANCY_LOG}"
