#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

if [[ ! -x "${KUJO_BIN_PATH}" ]]; then
	echo "Kujo runtime binary is not executable: ${KUJO_BIN_PATH}"
	exit 1
fi

BASE_PORT="${CMS_GATE_PORT_BASE:-49390}"
STAGE1_PORT="${BASE_PORT}"
STAGE2_R1_PORT="$((BASE_PORT + 1))"
STAGE2_SITEMAP_PORT="$((BASE_PORT + 2))"
STAGE2_FEEDS_PORT="$((BASE_PORT + 3))"
STAGE2_CURSOR_PORT="$((BASE_PORT + 4))"
STAGE2_PROJECTION_PORT="$((BASE_PORT + 5))"
STAGE3_R1_PORT="$((BASE_PORT + 6))"
STAGE3_R2_PORT="$((BASE_PORT + 7))"
STAGE3_SCHEDULER_PORT="$((BASE_PORT + 8))"
STAGE3_LOCKING_PORT="$((BASE_PORT + 9))"
MULTITENANT_PORT="$((BASE_PORT + 10))"
SMOKE_PORT="$((BASE_PORT + 11))"
AUDIT_CONSISTENCY_PORT="$((BASE_PORT + 12))"
PAGINATION_PARITY_PORT="$((BASE_PORT + 13))"
WEBHOOK_PIPELINE_PORT="$((BASE_PORT + 14))"
IDEMPOTENCY_PIPELINE_PORT="$((BASE_PORT + 15))"
BACKGROUND_JOBS_PIPELINE_PORT="$((BASE_PORT + 16))"
SECURITY_BASE_PORT="$((BASE_PORT + 20))"
PERF_PORT="$((BASE_PORT + 30))"
GRACEFUL_PORT="$((BASE_PORT + 40))"
OPS_LOAD_PERF_PORT="$((BASE_PORT + 50))"
OPS_LOAD_MIGRATION_PORT="$((BASE_PORT + 51))"
OPS_LOAD_PORT="$((BASE_PORT + 52))"
WEBHOOK_SINK_PORT="$((WEBHOOK_PIPELINE_PORT + 100))"

RUN_PERF="${CMS_GATE_RUN_PERF:-true}"
PERF_RUNS="${CMS_GATE_PERF_RUNS:-5}"
RUN_PERF_BUDGET="${CMS_GATE_RUN_PERF_BUDGET:-true}"

run_step() {
	label="$1"
	shift
	echo "[Gate] ${label}"
	"$@"
}

require_port_available() {
	local port="$1"
	if ! node -e '
		const net = require("node:net");
		const port = Number(process.argv[1]);
		const server = net.createServer();
		server.once("error", () => process.exit(1));
		server.listen(port, "127.0.0.1", () => server.close(() => process.exit(0)));
	' "${port}"; then
		echo "Release gate port ${port} is already in use. Set CMS_GATE_PORT_BASE to an unused range; no existing process was stopped." >&2
		exit 1
	fi
}

cd "${ROOT_DIR}"

for offset in $(seq 0 16) 20 21 22 23 24 25 30 40 50 51 52; do
	require_port_available "$((BASE_PORT + offset))"
done
require_port_available "${WEBHOOK_SINK_PORT}"

run_step "Brand isolation" \
	bash scripts/check-brand-isolation.sh

run_step "Contract tests" \
	"${KUJO_BIN_PATH}" test-run tests/cms_contract_tests.kujo

run_step "Stage 1 integration" \
	env CMS_TEST_PORT="${STAGE1_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage1.sh

run_step "Stage 2 Round 1 integration" \
	env CMS_TEST_PORT="${STAGE2_R1_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round1.sh

run_step "Stage 2 Round 2 sitemap integration" \
	env CMS_TEST_PORT="${STAGE2_SITEMAP_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round2-sitemaps.sh

run_step "Stage 2 Round 2 feed integration" \
	env CMS_TEST_PORT="${STAGE2_FEEDS_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round2-feeds.sh

run_step "Stage 2 Round 2 cursor integration" \
	env CMS_TEST_PORT="${STAGE2_CURSOR_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round2-cursor.sh

run_step "Stage 2 Round 2 projection integration" \
	env CMS_TEST_PORT="${STAGE2_PROJECTION_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round2-projection.sh

run_step "Stage 3 Round 1 revisions integration" \
	env CMS_TEST_PORT="${STAGE3_R1_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage3-round1-revisions.sh

run_step "Stage 3 Round 2 rollback integration" \
	env CMS_TEST_PORT="${STAGE3_R2_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage3-round2-rollback.sh

run_step "Stage 3 Round 3 scheduler integration" \
	env CMS_TEST_PORT="${STAGE3_SCHEDULER_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage3-round3-scheduler.sh

run_step "Stage 3 Round 3 locking integration" \
	env CMS_TEST_PORT="${STAGE3_LOCKING_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage3-round3-locking.sh

run_step "Multi-tenant isolation integration" \
	env CMS_TEST_PORT="${MULTITENANT_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-multitenant.sh

run_step "Smoke checks" \
	env CMS_SMOKE_PORT="${SMOKE_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/smoke-api.sh

run_step "Enterprise security integration" \
	env CMS_SECURITY_TEST_PORT_BASE="${SECURITY_BASE_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-enterprise-security.sh

run_step "Audit consistency integration" \
	env CMS_TEST_PORT="${AUDIT_CONSISTENCY_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-audit-consistency.sh

run_step "Pagination parity integration" \
	env CMS_TEST_PORT="${PAGINATION_PARITY_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-pagination-parity.sh

run_step "Webhook pipeline integration" \
	env CMS_TEST_PORT="${WEBHOOK_PIPELINE_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round3-webhooks.sh

run_step "Idempotency pipeline integration" \
	env CMS_TEST_PORT="${IDEMPOTENCY_PIPELINE_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round3-idempotency.sh

run_step "Background jobs pipeline integration" \
	env CMS_TEST_PORT="${BACKGROUND_JOBS_PIPELINE_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/integration-stage2-round3-background-jobs.sh

run_step "Graceful shutdown/restart validation" \
	env CMS_GRACEFUL_PORT="${GRACEFUL_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/validate-graceful-restart.sh

run_step "Operational load validation" \
	env CMS_OPS_LOAD_PERF_PORT="${OPS_LOAD_PERF_PORT}" CMS_OPS_LOAD_MIGRATION_PORT="${OPS_LOAD_MIGRATION_PORT}" CMS_OPS_LOAD_PORT="${OPS_LOAD_PORT}" KUJO_BIN="${KUJO_BIN_PATH}" \
	bash scripts/ops-load-validation.sh

if [[ "${RUN_PERF}" == "true" ]]; then
	run_step "Performance baseline" \
		env CMS_PERF_PORT="${PERF_PORT}" CMS_PERF_RUNS="${PERF_RUNS}" KUJO_BIN="${KUJO_BIN_PATH}" \
		bash scripts/perf-baseline.sh

	if [[ "${RUN_PERF_BUDGET}" == "true" ]]; then
		run_step "Performance budget checks" \
			env CMS_PERF_REPORT_FILE="${ROOT_DIR}/results/perf_baseline_latest.json" CMS_PERF_BUDGET_FILE="${ROOT_DIR}/docs/perf-budget.json" \
			bash scripts/perf-budget-check.sh
	else
		echo "[Gate] Performance budget checks skipped (CMS_GATE_RUN_PERF_BUDGET=${RUN_PERF_BUDGET})"
	fi
else
	echo "[Gate] Performance baseline skipped (CMS_GATE_RUN_PERF=${RUN_PERF})"
fi

echo "[Gate] All release checks passed."
