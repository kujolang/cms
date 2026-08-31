#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.cwd(), "benchmarks/hardening");
const pass1 = JSON.parse(readFileSync(resolve(root, "raw/comparison-input.json"), "utf8"));
const pass2 = JSON.parse(readFileSync(resolve(root, "raw/pass2/comparison-input.json"), "utf8"));
const paired = JSON.parse(readFileSync(resolve(root, "raw/paired/paired-results.json"), "utf8"));

function summarize(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  const mean = sorted.reduce((sum, value) => sum + value, 0) / sorted.length;
  const midpoint = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2;
  const variance = sorted.reduce((sum, value) => sum + ((value - mean) ** 2), 0) / sorted.length;
  return {
    n: sorted.length,
    min: sorted[0],
    max: sorted.at(-1),
    mean,
    median,
    p95: sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1)],
    stddev: Math.sqrt(variance),
  };
}

function delta(baseline, current) {
  return { absolute: current - baseline, percent: ((current - baseline) / baseline) * 100 };
}

function pairedSummary(label, field) {
  const samples = paired.samples[label];
  if (field === "startup_ms") return summarize(samples.map((sample) => sample.startup_ms));
  return summarize(samples.flatMap((sample) => sample[field]));
}

function workload(source, label, name) {
  return source[label].workloads.find((item) => item.name === name);
}

function agent(source, label, name) {
  return source[label].agent_outputs.find((item) => item.name === name);
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

const pairedMetrics = {};
for (const metric of ["startup_ms", "health_ms", "entries_ms"]) {
  const baseline = pairedSummary("baseline", metric);
  const current = pairedSummary("current", metric);
  pairedMetrics[metric] = { baseline, current, delta: delta(baseline.median, current.median) };
}

const passSummaries = [pass1, pass2].map((source, index) => ({
  pass: index + 1,
  order: index === 0 ? "baseline-first" : "current-first",
  baseline: {
    startup_median_ms: source.baseline.startup.latency_ms.median,
    health_median_ms: workload(source, "baseline", "minimal-health").latency_ms.median,
    entries_median_ms: workload(source, "baseline", "typical-entries").latency_ms.median,
    startup_rss_median_kb: source.baseline.startup.rss_kb.median,
    peak_rss_kb: source.baseline.process.peak_rss_kb,
  },
  current: {
    startup_median_ms: source.current.startup.latency_ms.median,
    health_median_ms: workload(source, "current", "minimal-health").latency_ms.median,
    entries_median_ms: workload(source, "current", "typical-entries").latency_ms.median,
    startup_rss_median_kb: source.current.startup.rss_kb.median,
    peak_rss_kb: source.current.process.peak_rss_kb,
  },
}));

const baselineCriteria = {
  native_contract_pass_1: pass1.baseline.native_tests.status === 0,
  native_contract_pass_2: pass2.baseline.native_tests.status === 0,
  minimal_success: workload(pass1, "baseline", "minimal-health").statuses["200"] === 20,
  typical_success: workload(pass1, "baseline", "typical-entries").statuses["200"] === 20,
  large_success: workload(pass1, "baseline", "large-entries").statuses["200"] === 20,
  invalid_cursor_rejected: workload(pass1, "baseline", "failure-invalid-cursor").statuses["400"] === 20,
  unauthorized_write_rejected: workload(pass1, "baseline", "failure-unauthorized-write").statuses["401"] === 20,
  missing_entry_is_404: workload(pass1, "baseline", "failure-missing-entry").statuses["404"] === 20,
  anonymous_draft_not_disclosed: workload(pass1, "baseline", "privacy-anonymous-draft").statuses["404"] === 20,
  agent_evidence_present: pass1.baseline.agent_outputs.every((item) => item.required_evidence_present && item.status === 200),
  unsafe_production_config_rejected: pass1.baseline.production_safety.exit_code === 1 && pass1.baseline.production_safety.output.includes("trusted ingress"),
};
const currentCriteria = {
  native_contract_pass_1: pass1.current.native_tests.status === 0,
  native_contract_pass_2: pass2.current.native_tests.status === 0,
  minimal_success: workload(pass1, "current", "minimal-health").statuses["200"] === 20,
  typical_success: workload(pass1, "current", "typical-entries").statuses["200"] === 20,
  large_success: workload(pass1, "current", "large-entries").statuses["200"] === 20,
  invalid_cursor_rejected: workload(pass1, "current", "failure-invalid-cursor").statuses["400"] === 20,
  unauthorized_write_rejected: workload(pass1, "current", "failure-unauthorized-write").statuses["401"] === 20,
  missing_entry_is_404: workload(pass1, "current", "failure-missing-entry").statuses["404"] === 20,
  anonymous_draft_not_disclosed: workload(pass1, "current", "privacy-anonymous-draft").statuses["404"] === 20,
  agent_evidence_present: pass1.current.agent_outputs.every((item) => item.required_evidence_present && item.status === 200),
  unsafe_production_config_rejected: pass1.current.production_safety.exit_code === 1 && pass1.current.production_safety.output.includes("trusted ingress"),
};

function score(criteria) {
  const passed = Object.values(criteria).filter(Boolean).length;
  const total = Object.keys(criteria).length;
  return { passed, total, percent: (passed / total) * 100 };
}

const results = {
  schema_version: "1.0.0",
  generated_at: new Date().toISOString(),
  evaluation_boundary: {
    baseline_sha: pass1.baseline.metadata.sha,
    baseline_timestamp: pass1.baseline.metadata.commit_timestamp,
    baseline_reason: "Direct parent of the six-commit hardening cluster beginning at 4851d21; selected before running benchmarks.",
    current_sha: pass1.current.metadata.sha,
    current_timestamp: pass1.current.metadata.commit_timestamp,
    current_tag: "v1.1.0",
    current_branch: "main",
    initial_current_worktree_clean: true,
    hardening_range: "4851d21..ebde7e3 inclusive",
    confounder: "CURRENT also contains 3,831 insertions and 62 deletions of post-hardening feature work after ebde7e3.",
  },
  environment: pass1.environment,
  methodology: {
    interpreter_mode: true,
    warmups: 3,
    full_passes: [
      { order: "baseline-first", measured_runs_per_latency_workload: 20, startup_runs: 10, throughput_requests: 50 },
      { order: "current-first", measured_runs_per_latency_workload: 10, startup_runs: 10, throughput_requests: 25 },
    ],
    paired_pass: { design: paired.design, blocks: paired.blocks, trials_per_version: paired.trials_per_version, endpoint_samples_per_version: paired.trials_per_version * paired.requests_per_trial },
    statistics: "Median is primary for latency; min, max, mean, p95, population standard deviation, and n are retained. Counterbalanced ABBA results supersede order-biased full-pass latency deltas.",
    known_invalid_measurement: "The invalid-JSON probe used a token containing a character rejected by both revisions and therefore measured authentication rejection (401), not JSON parsing. It is excluded from scores and conclusions.",
  },
  headline_measurements: {
    paired: pairedMetrics,
    memory: {
      pass_1: {
        baseline_startup_rss_median_kb: pass1.baseline.startup.rss_kb.median,
        current_startup_rss_median_kb: pass1.current.startup.rss_kb.median,
        delta_percent: delta(pass1.baseline.startup.rss_kb.median, pass1.current.startup.rss_kb.median).percent,
        baseline_peak_rss_kb: pass1.baseline.process.peak_rss_kb,
        current_peak_rss_kb: pass1.current.process.peak_rss_kb,
      },
      pass_2: {
        baseline_startup_rss_median_kb: pass2.baseline.startup.rss_kb.median,
        current_startup_rss_median_kb: pass2.current.startup.rss_kb.median,
        delta_percent: delta(pass2.baseline.startup.rss_kb.median, pass2.current.startup.rss_kb.median).percent,
        baseline_peak_rss_kb: pass2.baseline.process.peak_rss_kb,
        current_peak_rss_kb: pass2.current.process.peak_rss_kb,
      },
      classification: "REGRESSION",
    },
    agent_context_bytes: {
      baseline: Object.fromEntries(pass1.baseline.agent_outputs.map((item) => [item.name, item.bytes])),
      current: Object.fromEntries(pass1.current.agent_outputs.map((item) => [item.name, item.bytes])),
      capabilities_delta_percent: delta(agent(pass1, "baseline", "capabilities").bytes, agent(pass1, "current", "capabilities").bytes).percent,
      openapi_delta_percent: delta(agent(pass1, "baseline", "openapi").bytes, agent(pass1, "current", "openapi").bytes).percent,
      llms_delta_percent: delta(agent(pass1, "baseline", "llms").bytes, agent(pass1, "current", "llms").bytes).percent,
      token_measurement: "NOT DEMONSTRATED: no model/provider/tokenizer was involved; bytes, lines, and words are measured instead.",
    },
    database_bytes_after_5001_entries: {
      baseline: pass2.baseline.process.database_bytes,
      current: pass2.current.process.database_bytes,
      delta_percent: delta(pass2.baseline.process.database_bytes, pass2.current.process.database_bytes).percent,
    },
    native_contract_tests: {
      baseline: [pass1.baseline.native_tests, pass2.baseline.native_tests].map((item) => ({ status: item.status, duration_ms: item.duration_ms, output_bytes: item.output_bytes })),
      current: [pass1.current.native_tests, pass2.current.native_tests].map((item) => ({ status: item.status, duration_ms: item.duration_ms, output_bytes: item.output_bytes })),
      comparability: "Version-native suites both passed twice, but CURRENT has more tests; durations are not a same-workload performance comparison.",
    },
    production_safety: {
      baseline: pass1.baseline.production_safety,
      current: pass1.current.production_safety,
      classification: "CLEAR IMPROVEMENT",
    },
  },
  order_bias_evidence: passSummaries,
  scaling: {
    pass_1: { baseline: pass1.baseline.scaling, current: pass1.current.scaling },
    pass_2: { baseline: pass2.baseline.scaling, current: pass2.current.scaling },
    conclusion: "No pathological size-dependent growth was observed through 5,000 rows; run-order effects exceeded input-size effects.",
  },
  throughput: {
    pass_1: { baseline: pass1.baseline.throughput, current: pass1.current.throughput },
    pass_2: { baseline: pass2.baseline.throughput, current: pass2.current.throughput },
    conclusion: "CURRENT throughput was higher in both orderings, but magnitudes differed sharply; classify as likely improvement, not a stable percentage claim.",
  },
  structural: {
    baseline: { tracked_files: 88, tracked_bytes: 858868, backend_kujo_files: 18, backend_loc: 11986, test_loc: 659, functions: 66, contract_test_blocks: 21, contract_assertions: 111, todo_fixme: 0 },
    current: { tracked_files: 121, tracked_bytes: 1076959, backend_kujo_files: 25, backend_loc: 14464, test_loc: 910, functions: 127, contract_test_blocks: 33, contract_assertions: 210, todo_fixme: 0 },
    full_diff: { files_changed: 71, insertions: 4686, deletions: 323 },
    hardening_only_diff: { files_changed: 33, insertions: 858, deletions: 264 },
    post_hardening_feature_diff: { files_changed: 50, insertions: 3831, deletions: 62 },
    direct_package_dependencies: { baseline: 0, current: 0, note: "CURRENT adds dependency-free JavaScript and PHP client manifests; Kujo is an external runtime." },
    build_artifact: "NOT APPLICABLE: CMS is interpreted Kujo source and ships no repository-built binary.",
  },
  eval: {
    criteria: { baseline: baselineCriteria, current: currentCriteria },
    score: { baseline: score(baselineCriteria), current: score(currentCriteria) },
    note: "Scores are literal Kujo Eval pass counts for explicit behavior criteria, not invented 1-10 ratings. Performance, token efficiency, and maintainability remain unscored where Eval has no defensible pass threshold.",
  },
  verification: {
    current_worktree_contract_tests: { command: "kujo test-run tests/cms_contract_tests.kujo", status: 0, passed: 32, failed: 0 },
    current_release_gate: { command: "CMS_GATE_RUN_PERF=false KUJO_BIN=~/.local/bin/kujo bash scripts/run-release-gate.sh", status: 0, result: "All release checks passed; operational load validation still ran its embedded 30-run endpoint baseline." },
  },
  regressions: [
    { metric: "paired startup median", baseline: pairedMetrics.startup_ms.baseline.median, current: pairedMetrics.startup_ms.current.median, unit: "ms", change_percent: pairedMetrics.startup_ms.delta.percent, severity: "moderate", classification: "REGRESSION", likely_cause: "More modules, routes, migrations, and feature initialization in CURRENT; attribution to hardening alone is not possible." },
    { metric: "startup RSS median", baseline: pass2.baseline.startup.rss_kb.median, current: pass2.current.startup.rss_kb.median, unit: "KiB", change_percent: delta(pass2.baseline.startup.rss_kb.median, pass2.current.startup.rss_kb.median).percent, severity: "moderate", classification: "REGRESSION", likely_cause: "The application surface grew from 18 to 25 backend Kujo files and 66 to 127 functions." },
    { metric: "OpenAPI bytes returned to agents", baseline: agent(pass1, "baseline", "openapi").bytes, current: agent(pass1, "current", "openapi").bytes, unit: "bytes", change_percent: delta(agent(pass1, "baseline", "openapi").bytes, agent(pass1, "current", "openapi").bytes).percent, severity: "low", classification: "TRADEOFF", likely_cause: "Expanded documented API surface; evidence remained complete rather than compressed." },
  ],
  not_demonstrated: [
    "LLM input/output/cached token savings or dollar savings",
    "tool-call, retry, reasoning-cycle, or completion-rate improvements for a real model/provider",
    "network-call reductions under external integrations",
    "allocation counts or steady-state memory under hours-long load",
    "binary size, clean build time, incremental build time, or transitive compile dependency changes",
    "performance attribution to individual hardening commits",
  ],
  final_answer: {
    verdict: "PARTIALLY",
    rationale: "Independent evidence shows materially safer production startup, stronger guarded behavior, and broader passing contract coverage. It does not show a uniformly leaner system: startup and memory regress, agent-facing OpenAPI output grows with the feature surface, and latency results require counterbalancing because sequential runs were order-sensitive.",
  },
  evidence: {
    files: [
      { path: "benchmarks/hardening/raw/comparison-input.json", sha256: sha256(resolve(root, "raw/comparison-input.json")) },
      { path: "benchmarks/hardening/raw/pass2/comparison-input.json", sha256: sha256(resolve(root, "raw/pass2/comparison-input.json")) },
      { path: "benchmarks/hardening/raw/paired/paired-results.json", sha256: sha256(resolve(root, "raw/paired/paired-results.json")) },
    ],
  },
};

writeFileSync(resolve(root, "evaluation-results.json"), `${JSON.stringify(results, null, 2)}\n`);
console.log(JSON.stringify({ output: "benchmarks/hardening/evaluation-results.json", verdict: results.final_answer.verdict, eval: results.eval.score }, null, 2));
