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
const names = new Set();
for (const row of rows) {
	const name = String(row.name || "");
	const limits = Object.assign({}, defaults, overrides[name] || {});
	if (!name || names.has(name)) failures.push(`Invalid or duplicate performance row: ${name}`);
	names.add(name);
	for (const metric of ["min_s", "avg_s", "p95_s", "max_s"]) {
		if (typeof row[metric] !== "number" || !Number.isFinite(row[metric]) || row[metric] < 0) failures.push(`${name}: invalid ${metric}`);
	}
	for (const metric of ["avg_s", "p95_s", "max_s"]) {
		if (typeof limits[metric] !== "number" || !Number.isFinite(limits[metric]) || limits[metric] <= 0) failures.push(`${name}: invalid ${metric} budget`);
	}
	const avg = row.avg_s;
	const p95 = row.p95_s;
	const max = row.max_s;
	if (row.min_s > avg || avg > max || row.min_s > p95 || p95 > max) failures.push(`${name}: inconsistent timing statistics`);

	if (typeof limits.avg_s === "number" && avg > limits.avg_s) {
		failures.push(`${name}: avg_s ${Number(avg).toFixed(6)} > budget ${limits.avg_s.toFixed(6)}`);
	}
	if (typeof limits.p95_s === "number" && p95 > limits.p95_s) {
		failures.push(`${name}: p95_s ${Number(p95).toFixed(6)} > budget ${limits.p95_s.toFixed(6)}`);
	}
	if (typeof limits.max_s === "number" && max > limits.max_s) {
		failures.push(`${name}: max_s ${Number(max).toFixed(6)} > budget ${limits.max_s.toFixed(6)}`);
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