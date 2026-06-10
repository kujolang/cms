#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_FILE="${CMS_PERF_REPORT_FILE:-${ROOT_DIR}/results/perf_baseline_latest.json}"
BUDGET_FILE="${CMS_PERF_BUDGET_FILE:-${ROOT_DIR}/docs/perf-budget.json}"

if [[ ! -f "${REPORT_FILE}" ]]; then
	echo "Performance report not found: ${REPORT_FILE}"
	exit 1
fi

if [[ ! -f "${BUDGET_FILE}" ]]; then
	echo "Performance budget file not found: ${BUDGET_FILE}"
	exit 1
fi

node -e '
const fs = require("fs");

const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const budget = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));

const defaults = budget.defaults || {};
const overrides = budget.overrides || {};
const rows = Array.isArray(report.results) ? report.results : [];

if (!rows.length) {
	console.error("No performance rows found in report.");
	process.exit(1);
}

const failures = [];
for (const row of rows) {
	const name = String(row.name || "");
	const limits = Object.assign({}, defaults, overrides[name] || {});
	const avg = Number(row.avg_s || 0);
	const p95 = Number(row.p95_s || 0);
	const max = Number(row.max_s || 0);

	if (typeof limits.avg_s === "number" && avg > limits.avg_s) {
		failures.push(`${name}: avg_s ${avg.toFixed(6)} > budget ${limits.avg_s.toFixed(6)}`);
	}
	if (typeof limits.p95_s === "number" && p95 > limits.p95_s) {
		failures.push(`${name}: p95_s ${p95.toFixed(6)} > budget ${limits.p95_s.toFixed(6)}`);
	}
	if (typeof limits.max_s === "number" && max > limits.max_s) {
		failures.push(`${name}: max_s ${max.toFixed(6)} > budget ${limits.max_s.toFixed(6)}`);
	}
}

if (failures.length) {
	console.error("[FAIL] Performance budgets exceeded:");
	for (const failure of failures) {
		console.error(`- ${failure}`);
	}
	process.exit(1);
}

console.log("[PASS] Performance budgets satisfied.");
' "${REPORT_FILE}" "${BUDGET_FILE}"