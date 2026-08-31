# Kujo CMS Before/After Hardening Evaluation

Date: 2026-08-30  
Evaluator: Codex, using Kujo Eval v2.0.0 and Kujo runtime 1.0.0  
Verdict: **PARTIALLY**

## Executive Summary

This evaluation compares the last commit immediately before the dedicated hardening cluster, `1be7ec1f551dbecd964ce1404851276241838632`, with the tagged current release, `22570a510a0169bab2a6c3a4f3b92512f290ea57` (`v1.1.0`). The baseline was selected from Git history before benchmarks ran: it is the direct parent of `4851d21`, the first of six contiguous security and operational hardening commits made on 2026-08-25.

The empirical result is mixed but favorable on the hardening objective. CURRENT rejects an unsafe production configuration that BASELINE accepts and starts. Both revisions passed their version-native contract suite twice. A custom Kujo Eval suite scored BASELINE at 10/11 explicit behavior checks (90.9%) and CURRENT at 11/11 (100%); the added pass is the production ingress/rate-limit startup guard.

CURRENT is not uniformly faster or leaner. In the counterbalanced benchmark, median startup increased from 1,202.6 ms to 1,773.0 ms, a 570.5 ms or 47.4% regression. Startup resident memory increased consistently: 86,366 KiB to 131,588 KiB in the cleaner second full pass, or 52.4%. Those costs coincide with substantial post-hardening feature growth: after the hardening cluster ended at `ebde7e3`, CURRENT added another 3,831 lines and removed 62 across 50 files. The comparison therefore measures the shipped release, not a pure hardening-only patch.

Steady request latency is nuanced. In the counterbalanced ABBA run, health median latency increased 9.1% (110.5 → 120.5 ms), while p95 fell 3.7% (160.4 → 154.4 ms) and standard deviation fell 67.4%. For a 25-entry list against a 5,000-entry database, median latency increased 7.8% (166.8 → 179.8 ms), while p95 fell 19.2% (259.5 → 209.8 ms) and standard deviation fell 45.2%. CURRENT is slightly slower at the center but more predictable in these paired samples.

Throughput was higher for CURRENT in both full-pass orderings, but the apparent improvement changed sharply with run order. At concurrency 1, CURRENT achieved 6.22 requests/s versus 2.32 in the baseline-first pass, then 8.82 versus 7.84 in the current-first pass. The direction is consistent; the magnitude is not. This is classified as a likely throughput improvement without a headline percentage.

Agent-facing output did not become smaller. `/llms.txt` remained 477 bytes and retained the required evidence. `/v1` grew from 1,717 to 2,348 bytes (+36.8%), and OpenAPI grew from 4,512 to 9,209 bytes (+104.1%) because CURRENT exposes materially more functionality. No LLM, provider, or tokenizer participated in the run, so token, context-window, tool-call, and dollar-cost claims are **not demonstrated**. The measured output growth is a feature-surface tradeoff, not evidence of waste by itself.

For actual Kujo users, the strongest independently demonstrated benefit is safer operation: a production server no longer starts when trusted ingress and external rate limiting are absent. The strongest costs are startup time and memory. The release is better hardened, more capable, and better covered, but it is not empirically smaller or faster across the board.

## Before/After Scorecard

| Metric | BASELINE | CURRENT | Change | Classification |
|---|---:|---:|---:|---|
| Kujo Eval behavior checks | 10/11 (90.9%) | 11/11 (100%) | +1 check | Clear improvement |
| Unsafe production config | Became healthy | Exited 1 with focused error | Unsafe startup removed | Clear improvement |
| Paired startup median, n=10 | 1,202.6 ms | 1,773.0 ms | +570.5 ms (+47.4%) | Regression |
| Paired startup p95 | 1,336.0 ms | 2,635.1 ms | +1,299.1 ms (+97.2%) | Regression |
| Startup RSS median, pass 2 | 86,366 KiB | 131,588 KiB | +45,222 KiB (+52.4%) | Regression |
| Workload peak RSS, pass 2 | 98,760 KiB | 146,512 KiB | +47,752 KiB (+48.4%) | Regression |
| Paired health median, n=50 | 110.5 ms | 120.5 ms | +10.0 ms (+9.1%) | Likely small regression |
| Paired health p95 | 160.4 ms | 154.4 ms | −6.0 ms (−3.7%) | Neutral/noisy |
| Paired entries median, n=50 | 166.8 ms | 179.8 ms | +13.0 ms (+7.8%) | Likely small regression |
| Paired entries p95 | 259.5 ms | 209.8 ms | −49.7 ms (−19.2%) | Likely improvement |
| Throughput, concurrency 1, pass 2 | 7.84 req/s | 8.82 req/s | +0.99 req/s (+12.6%) | Likely improvement |
| DB bytes after 5,001 rows | 4,075,520 | 4,112,384 | +36,864 (+0.9%) | Neutral |
| `/llms.txt` bytes | 477 | 477 | 0 | Neutral |
| Capabilities bytes | 1,717 | 2,348 | +631 (+36.8%) | Feature tradeoff |
| OpenAPI bytes | 4,512 | 9,209 | +4,697 (+104.1%) | Feature tradeoff |
| Tracked files | 88 | 121 | +33 (+37.5%) | Feature growth |
| Tracked source bytes | 858,868 | 1,076,959 | +218,091 (+25.4%) | Feature growth |
| Backend Kujo LOC | 11,986 | 14,464 | +2,478 (+20.7%) | Feature growth |
| Contract assertions | 111 | 210 | +99 (+89.2%) | Coverage improvement |
| Version-native contract runs | 2/2 passed | 2/2 passed | No failures | Neutral/reliable |

Only measured metrics appear in this scorecard. Positive latency and memory percentages mean more time or memory and are regressions.

## Evaluation Boundary

### CURRENT

- Branch at evaluation start: `main`
- SHA: `22570a510a0169bab2a6c3a4f3b92512f290ea57`
- Commit timestamp: 2026-08-30T13:10:11-04:00
- Tag: `v1.1.0`
- Worktree at evaluation start: clean

### BASELINE

- SHA: `1be7ec1f551dbecd964ce1404851276241838632`
- Commit timestamp: 2026-08-24T22:54:28-04:00
- Tag: none
- Selection reason: direct parent of `4851d21`, where a contiguous hardening cluster starts. The next commits are scoped administration, webhook egress, bootstrap setup, credential/idempotency lifecycle, worker/recovery race safety, and production ingress controls.

Other plausible boundaries were rejected for the primary comparison:

- `v1.0.0` (`595be16`) predates unrelated feature and correctness work, so it would overstate the hardening delta.
- `ebde7e3` is the end of the hardening cluster and is useful as an intermediate in future work, but it is not the requested pre-hardening baseline.
- The direct parent of CURRENT would only measure release metadata/CI and would miss the hardening effort.

The major limitation is unavoidable in the requested BASELINE-to-CURRENT comparison: CURRENT includes post-hardening features. The hardening-only range changed 33 files with 858 insertions and 264 deletions. The later feature range, `ebde7e3..22570a5`, changed 50 files with 3,831 insertions and 62 deletions.

## What Changed

### Architecture and security controls

`4851d21` tightened authorization and administration scoping. It changed request guarding, authentication context, role/permission behavior, plugin administration, users, and runtime route wiring. The intended effect is less cross-scope privilege, not raw speed. This evaluation observed the source and expanded tests but did not isolate a cross-tenant attack workload; the benefit is therefore **observed/inferred**, not measured here.

`7176e6f` moved webhook delivery toward validated egress with bounded process behavior and more complete integration assertions. The expected effect is lower SSRF risk, bounded network time, and preserved delivery evidence. External network delivery was intentionally not exercised, so runtime/call-count savings are **not demonstrated**.

`c8064da` materially changed credential and idempotency lifecycle behavior. Idempotency keys are scoped to credential/role/permissions, stale rows are expired, pending inserts detect conflicts, and completion is explicit. Migrations added schema support. This should improve correctness under retries and credential boundaries. The version-native suites passed, but this evaluation did not run a statistically sampled concurrent idempotency benchmark; performance attribution is **not demonstrated**.

`44a587d` made backup, restore, webhook, and background-worker scripts claim-aware and race-safe. It adds coordination and evidence handling while reducing unsafe overwrite patterns. These paths should improve deterministic operations at the cost of more coordination I/O. No separate worker-contention benchmark was executed, so the result is **observed** from source and repository tests.

`ebde7e3` added explicit production startup gates: trusted ingress limits are required, and external rate limiting is required until the runtime exposes safe per-client addressing. This was directly measured. BASELINE became healthy under the unsafe configuration; CURRENT exited with code 1 and a single focused diagnostic in 817.9 ms. This is a **measured clear improvement**.

### Post-hardening feature growth

After the hardening cluster, CURRENT added SEO operations, abilities and connectors, WebMCP, extension/package flows, identity sessions, atomic content/media workflows, portable administration, and dependency-free JavaScript/PHP clients. These additions explain much of the larger route/module surface, source size, startup work, memory, and API-description output. They make a pure code-change-to-performance attribution impossible without benchmarking the intermediate `ebde7e3` revision.

### Complexity

Complexity was not simply removed. Backend files rose from 18 to 25; backend LOC from 11,986 to 14,464; counted functions from 66 to 127; tracked files from 88 to 121. Contract test blocks rose from 21 to 33 and assertion references from 111 to 210. There were no TODO/FIXME markers in either revision under the measured scan.

The hardening scripts do consolidate safety behavior, but overall complexity is mostly expanded or relocated because the product surface grew. Calling the whole release a cleanup or simplification would not be supported.

## Benchmark Methodology

### Environment

- macOS 26.3.1, Darwin 25.3.0, x86_64
- Intel Core i7-9750H, 12 logical cores
- 16 GiB RAM
- Kujo runtime 1.0.0, tree-walking interpreter mode for both revisions
- Node.js 24.20.0 benchmark driver
- Loopback HTTP; no external network dependency
- Fresh SQLite database per startup trial; identical generated data and request paths
- Audit and structured request logs disabled; rate limit raised equally

The CMS repository is interpreted Kujo source. It has no repository-built CMS binary, so clean/incremental/release build time and binary size are not applicable. CURRENT's JavaScript and PHP clients declare no package dependencies. Direct application dependency count remains zero; the Kujo runtime is external.

### Runs and statistics

The first full pass ran BASELINE then CURRENT with three warmups, 20 measured latency samples per workload, 10 startup samples, and 50 requests per throughput level. The second reversed the order and used three warmups, 10 latency samples, 10 startup samples, and 25 throughput requests.

Those passes exposed strong order/machine-load sensitivity. In pass 1, BASELINE startup median was 6,293 ms and CURRENT 2,782 ms; in pass 2, CURRENT was 1,255 ms and BASELINE 802 ms. Presenting pass 1 as a 56% improvement would have been false confidence.

The decisive latency run therefore used five counterbalanced ABBA blocks. Each revision ran twice per block, for 10 process trials per revision. Every trial used a copied 5,000-entry database, three warmups per endpoint, and five measured requests: 50 health and 50 list samples per revision. Median is primary; min, max, mean, p95, and population standard deviation are preserved in JSON.

### Workloads

- Minimal: `/health`, measuring fixed request overhead.
- Typical: 25-entry list from a 5,000-entry database.
- Large: 100-entry response near the end of the same database.
- Scaling: 0, 10, 100, 1,000, and 5,000 rows with a fixed 100-row response cap.
- Stress: 50 or 25 requests at concurrency 1, 10, and 25.
- Failure: invalid cursor, unauthorized write, missing entry, and anonymous draft lookup.
- Production failure: start with production mode, memory rate limiting, and no trusted ingress declaration.
- Agent-facing: capabilities, OpenAPI, and `/llms.txt`, measuring bytes/lines/words and required evidence presence.

One invalid-JSON workload was excluded. Its benchmark token contained a character both revisions reject, so it measured a 401 authentication rejection rather than JSON parsing. The raw samples remain preserved; no claim relies on them.

## Runtime Performance and Scaling

### Startup

The counterbalanced startup result is a clear regression: 1,202.6 → 1,773.0 ms median (+47.4%). CURRENT p95 also increased from 1,336.0 to 2,635.1 ms. This aligns with the larger module and migration surface. It cannot be attributed to hardening alone because most new code arrived after `ebde7e3`.

### Request latency

CURRENT trades a slightly slower median for a tighter distribution in the paired sample. Health median rose 9.1%, but p95 fell 3.7% and standard deviation fell from 44.0 to 14.4 ms. Entry-list median rose 7.8%, but p95 fell 19.2% and standard deviation fell from 30.0 to 16.4 ms.

The median regressions are operationally visible but small relative to the interpreter's 100–200 ms request cost. The tail/variance improvement matters for predictability. The evidence does not justify saying CURRENT is simply faster.

### Throughput and concurrency

CURRENT produced higher throughput in both orderings:

| Concurrency | Pass 1 BASELINE → CURRENT | Pass 2 BASELINE → CURRENT |
|---:|---:|---:|
| 1 | 2.32 → 6.22 req/s | 7.84 → 8.82 req/s |
| 10 | 2.62 → 6.55 req/s | 8.02 → 9.76 req/s |
| 25 | 3.86 → 6.33 req/s | 8.63 → 9.68 req/s |

The consistent direction supports **likely improvement**. The unstable magnitude prevents a single percentage claim. At concurrency 25, both versions have multi-second p95 because the interpreter/server processes this workload with limited effective parallelism.

### Scaling

With response size capped at 100 rows, neither revision showed pathological growth through 5,000 rows. In the cleaner reversed pass, BASELINE medians ranged from 106.4 to 125.1 ms and CURRENT from 106.8 to 172.4 ms without monotonic growth. Within this range, response serialization and fixed interpreter overhead dominate the database count/offset cost. Complexity appears approximately constant for the tested bounded response, but this does not prove behavior beyond 5,000 rows or with unbounded response construction.

## Memory, Storage, and Build Footprint

Memory is a reproducible regression. Startup RSS median increased 52.5% in pass 1 and 52.4% in pass 2. Peak workload RSS increased from 98,760 to 146,512 KiB (+48.4%) in pass 2. The likely cause is the expanded loaded module/route surface, not a measured allocation leak.

The populated database increased only 36,864 bytes, 4,075,520 → 4,112,384 (+0.9%). This is neutral and consistent with added schema metadata/indexes.

Tracked repository bytes increased 25.4%. There is no CMS binary or compiled artifact to compare. Native contract test duration was longer for CURRENT in both passes, but CURRENT's version-native suite has 33 test blocks versus 21 and 210 assertion references versus 111. That is not a same-workload build-performance regression and is not scored as one.

## Token, Context, and Agent Efficiency

No LLM call occurred, no provider/model was configured, and no tokenizer was authoritative for this evaluation. Therefore:

- input, output, total, and cached tokens: **not demonstrated**
- context-window reduction: **not demonstrated**
- tool calls, retries, reasoning/action cycles, and completion rate: **not demonstrated**
- model cost savings: **not demonstrated**

Measured agent-facing bytes show expansion, not compression:

| Output | BASELINE | CURRENT | Change | Required evidence |
|---|---:|---:|---:|---|
| Capabilities | 1,717 B | 2,348 B | +36.8% | Present in both |
| OpenAPI | 4,512 B | 9,209 B | +104.1% | Present in both |
| `/llms.txt` | 477 B | 477 B | 0% | Present in both |

OpenAPI growth tracks more functionality. It should not be called a context regression without a real agent task showing reduced completion quality or context exhaustion. A future agent benchmark should compare task success using full versus selectively retrieved API descriptions.

## Reliability and Determinism

Both revisions passed their native contract suite in both full passes. CURRENT's request latency variance was lower in the paired health and entries workloads. CURRENT also fails closed under the tested unsafe production configuration, while BASELINE starts.

After the reproducibility package was added, CURRENT also passed 32/32 contract tests and the complete repository release gate with `CMS_GATE_RUN_PERF=false`. That gate still executed its embedded 30-run operational endpoint baseline, migration restart, backup/restore, Stage 1/2/3 integrations, security, audit, pagination, webhook, idempotency, background-job, and graceful-restart checks; all passed.

The source includes stronger idempotency, worker claims, egress validation, and recovery workflows. Those are important, but this evaluation did not independently stress each concurrency property. They remain source/test observations rather than new measured benchmark claims.

## Kujo Eval Report

Kujo Eval v2.0.0 executed 11 explicit criteria per revision:

- two independent native contract-suite passes
- minimal, typical, and large workload success
- invalid-cursor, unauthorized-write, and missing-entry failure behavior
- anonymous draft non-disclosure
- required agent evidence presence
- unsafe production configuration rejection

| Category | BASELINE | CURRENT | Change |
|---|---:|---:|---:|
| Correctness/workload success | 5/5 | 5/5 | Neutral |
| Reliability/native repeated passes | 2/2 | 2/2 | Neutral |
| Failure behavior | 3/3 | 3/3 | Neutral |
| Agent evidence | 1/1 | 1/1 | Neutral |
| Production safety | 0/1 | 1/1 | +1 clear improvement |
| Overall literal Eval checks | 10/11 (90.9%) | 11/11 (100%) | +9.1 percentage points |

The category rows overlap the 11 checks conceptually; the authoritative overall count is 10/11 versus 11/11. Performance, token efficiency, context efficiency, and maintainability are deliberately unscored because Kujo Eval has no defensible threshold for them in this run.

Kujo Eval's generated baseline Markdown displays `Pass Rate | 0%` despite `summary.json` correctly recording 90. This is an Eval report-rendering defect, not a CMS result. The pass/fail counts and machine summary are used here.

## Change-to-Result Mapping

| Code change | Behavioral change | Evidence | Engineering consequence |
|---|---|---|---|
| `ebde7e3`: production startup guard in config/runtime | Rejects deployment without trusted ingress and external rate limiting | BASELINE reached health; CURRENT exited 1 in 817.9 ms with one diagnostic | Clear prevention of an unsafe production state |
| `4851d21` + `c8064da`: authorization and credential/idempotency scoping | Narrower permission and replay boundaries | Source diff, expanded contract/security tests; both native suites passed | Stronger correctness/security; performance effect not isolated |
| `44a587d`: worker/recovery claim and overwrite safety | Safer concurrent operations and restore behavior | Source diff and repository integration coverage | Lower race/recovery risk; added coordination cost not separately measured |
| Post-`ebde7e3` module/route expansion | More startup initialization and resident code | 18 → 25 backend files; 66 → 127 functions; startup +47.4%; startup RSS +52.4% | Larger capability surface with measurable startup/memory cost |
| Expanded API contract | More agent-discoverable endpoints | OpenAPI 4,512 → 9,209 bytes with required evidence preserved | Better discoverability, larger active-context payload if fetched whole |
| Runtime/request-path changes plus larger release | Tighter request latency distribution | Entry p95 259.5 → 209.8 ms; stddev 30.0 → 16.4 ms | More predictable tail behavior in paired local workload |

The startup and memory mappings are derived from correlation with surface growth; the benchmark does not prove a specific function caused the delta.

## Commit Attribution

| Commit | Change | Intended effect | Observed/measured effect |
|---|---|---|---|
| `4851d21` | Scoped CMS administration | Prevent cross-scope administration | Observed in source/tests; no isolated attack benchmark |
| `7176e6f` | Validated webhook egress | Prevent unsafe destinations and bound delivery | Observed in source/tests; external egress not measured |
| `216dd6c` | Deliberate bootstrap setup docs | Reduce insecure operator setup | Documentation only; runtime effect not measured |
| `c8064da` | Credential/idempotency lifecycle | Scoped replay, expiration, race-safe completion | Observed in source/tests; no isolated performance result |
| `44a587d` | Race-safe workers/recovery | Deterministic claims, backup, restore, replay | Observed in source/tests; contention not measured |
| `ebde7e3` | Trusted production ingress gate | Fail closed on unsafe deployment | Measured clear improvement |
| `90e7080..9003e76` | SEO, AI, WebMCP, extensions, identity, workflows, clients | Broader CMS capability | Measured surface, startup, memory, and contract-output growth |
| `002c031` | v1.1.0 metadata | Align release version | Observed metadata only |
| `22570a5` | Pinned runtime install in CI | Reproducible CI runtime | Observed CI change; local runtime performance unaffected |

## Regressions and Tradeoffs

### Startup latency

- BASELINE: 1,202.6 ms median
- CURRENT: 1,773.0 ms median
- Change: +570.5 ms (+47.4%)
- Severity: moderate for cold starts and ephemeral deployments
- Likely cause: expanded route/module/migration surface
- Recommended action: benchmark `1be7ec1`, `ebde7e3`, and CURRENT in one counterbalanced run; then profile route registration and migration initialization before optimizing.

### Memory

- BASELINE startup RSS: 86,366 KiB
- CURRENT startup RSS: 131,588 KiB
- Change: +45,222 KiB (+52.4%)
- Severity: moderate for dense local deployments
- Likely cause: expanded loaded program surface
- Recommended action: add an RSS budget and test lazy registration/loading only if profiling confirms benefit.

### Agent-facing contract volume

- OpenAPI: 4,512 → 9,209 bytes (+104.1%)
- Capabilities: 1,717 → 2,348 bytes (+36.8%)
- Severity: low in HTTP terms; potentially meaningful in agent context
- Tradeoff: substantially more documented capability
- Recommended action: offer filtered or capability-scoped discovery while retaining the complete raw contract.

### Median request latency

- Health: +9.1%
- Entry list: +7.8%
- Severity: low in this interpreter-bound local workload
- Counterpoint: p95 and variance improved
- Recommended action: keep both median and tail budgets; do not optimize from these samples alone.

## Top Improvements

1. **Unsafe production startup is prevented.** This is the most important result because it changes a dangerous accepted state into a deterministic failure with a focused diagnostic.
2. **Tail behavior is more predictable.** Entry-list p95 fell 19.2% and standard deviation fell 45.2% in the counterbalanced run, despite a slower median.
3. **Throughput direction is favorable under concurrency.** CURRENT was higher at concurrency 1, 10, and 25 in both run orders, although the size of the gain is not stable enough for a headline claim.
4. **Contract coverage is broader.** Assertion references increased from 111 to 210 and native suites passed twice for both revisions.
5. **Agent guidance remained complete.** `/llms.txt` stayed fixed at 477 bytes and all required evidence checks passed while the API surface expanded.

## Remaining Opportunities

- **P1:** Isolate the hardening-only revision (`ebde7e3`) in the counterbalanced benchmark. This is required to distinguish hardening cost from feature cost.
- **P1:** Add real agent tasks with a fixed provider/model and trace tokens, tool calls, retries, completion success, and context growth. Current token-efficiency claims are unsupported.
- **P1:** Profile cold startup and resident memory before attempting lazy loading or registration changes.
- **P2:** Add long-duration steady-state RSS and allocation sampling to distinguish loaded-code growth from leaks.
- **P2:** Add focused contention benchmarks for idempotency keys, webhook claims, background jobs, backup, and restore.
- **P2:** Provide capability-scoped OpenAPI/agent discovery to avoid placing the full 9.2 KB contract in every task context.
- **P3:** Extend scaling beyond 5,000 rows and include search filters, cursor pagination, and larger stored bodies.

No P0 correctness failure was found in the tested CURRENT workloads.

## Cost Modeling

No measured token reduction or compute reduction supports dollar modeling. It would be misleading to convert byte counts to provider cost without a fixed tokenizer/model and actual prompts. Therefore per-100, per-1,000, and per-10,000 execution savings are **not estimated**.

The measurable resource cost per cold process is approximately 44 MiB more startup RSS and 0.57 seconds more median startup time in the paired environment. Translating that to infrastructure cost requires deployment density, restart frequency, and provider pricing not present in the repository.

## Reproduction Guide

See [`benchmarks/hardening/README.md`](../benchmarks/hardening/README.md). It defines worktree creation, both full-pass orders, the counterbalanced run, result generation, and Kujo Eval execution. Raw JSON, agent-facing payloads, Eval artifacts, and SHA-256 checksums are preserved under `benchmarks/hardening/`.

## Evidence Classification Summary

- **Measured:** startup, request latency distribution, throughput, RSS, DB size, output bytes/lines/words, repeated contract exit status, production startup behavior, Eval check counts.
- **Observed:** Git changes, route/module growth, test growth, worker/idempotency/egress implementation changes.
- **Derived:** percentages, source counts, pass rates, tracked-byte deltas.
- **Inferred:** expanded loaded surface is the primary startup/RSS cause; tighter distributions reflect more deterministic request behavior.
- **Not demonstrated:** token/cost savings, real agent task efficiency, allocation counts, external-network call reductions, binary/build improvements, and per-commit performance causality.

## Final Question

> If we erase the commit messages and ignore what the hardening work intended to accomplish, does the empirical evidence independently demonstrate that CURRENT is a better engineered version than BASELINE?

**PARTIALLY.**

The independent evidence demonstrates a meaningful production safety improvement, complete workload behavior, repeated passing contract suites, and better tail consistency/likely throughput. It also demonstrates regressions in startup and memory, a slightly slower median request path, and larger agent-facing contracts. CURRENT is better hardened and more capable, but not unconditionally faster, smaller, or cheaper.
