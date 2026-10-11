import assert from 'node:assert/strict';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const dir = mkdtempSync(join(tmpdir(), 'cms-perf-budget-'));
const report = join(dir, 'report.json');
const budget = join(dir, 'budget.json');
const limits = {defaults: {avg_s: 1, p95_s: 2, max_s: 3}};
const row = {name: 'health', min_s: .1, avg_s: .2, p95_s: .3, max_s: .4};
function check(results, expected, config = limits) {
  writeFileSync(report, JSON.stringify({results}));
  writeFileSync(budget, JSON.stringify(config));
  const run = spawnSync('bash', ['scripts/perf-budget-check.sh'], {encoding: 'utf8', env: {...process.env, CMS_PERF_REPORT_FILE: report, CMS_PERF_BUDGET_FILE: budget}});
  assert.equal(run.status, expected, run.stdout + run.stderr);
}
try {
  check([row], 0);
  check([], 1);
  check([row, row], 1);
  for (const value of [undefined, null, 'invalid', -1]) check([{...row, avg_s: value}], 1);
  check([{...row, p95_s: 4, max_s: 5}], 1);
  check([{...row, min_s: .8}], 1);
  check([row], 1, {defaults: {}});
  console.log('Performance budget validation regressions passed');
} finally { rmSync(dir, {recursive: true, force: true}); }
