# Kujo CMS hardening audit round two

## Repository and baseline

- Repository: `cms`, branch `main`, initially clean and synchronized.
- Starting SHA: `f1d1ea6da63e0dfdf6439a42aadd046a22988fe4`.
- Ending implementation SHA: `eaebb0f23847a59e2458340b33f0c5a0173c08cd`. The documentation commit records that code revision rather than attempting to embed its own hash.
- Date: October 10, 2026, America/Detroit (October 11 UTC).
- Purpose and integrations: server-first Kujo HTTP CMS; native SQLite, filesystem and HTTP primitives; pinned Ability package; external plugin/webhook services; sibling `cms-example` owns presentation. Local validation used Kujo 1.5.0. CI remains pinned to 1.2.2; its source contains `path_is_symlink`, but this pass did not execute that binary.

The preceding audit and its measurements remain in [repository-hardening.md](repository-hardening.md). This round repeated the release baseline and concentrated independent source reviews on missed filesystem, public media, queue ownership and composition boundaries. The initial full gate passed with 39 contracts, clients, all integrations, operational checks and ten-request endpoint samples. Existing passing tests did not exercise the defects below.

Local raw evidence is under ignored `results/hardening-round2/`: baseline/final gate logs, `regression-before.log`, `security-before.log`, `media-before.log`, `claims-before.log`, focused verification logs, endpoint JSON, `worker-before.json`, `worker-after.json`, and `measure-worker.py`. Temporary fixtures contain only generated local test credentials and disposable data.

## Findings

| ID | Priority | Area | Finding and evidence | Action | Status |
|---|---|---|---|---|---|
| R2-01 | P0 | Filesystem authority | Mutable `config.storage.install_root` reached prefix-only package deletion. A valid replacement deleted an outside disposable sentinel through `/../../victim`. | Exact generated direct-child root validation, no symlink traversal, server-owned sibling ownership records bound to kind/key. | Fixed |
| R2-02 | P1 | Availability | Public media file GET bypassed request guard and returned a full base64 file after its IP quota was exhausted. | Apply public guard before lookup/read. | Fixed |
| R2-03 | P1 | Content integrity | Term-only compose left `updated_at` unchanged; two stale editors could overwrite assignments. Version/lock checks also preceded the write transaction. | Advance every compose version monotonically; recheck full entry snapshot and lock inside transaction before revision/write. | Fixed |
| R2-04 | P1 | Event delivery | Compose emitted `entry.compose`, omitted from the webhook producer; its audit metadata also lacked required routing fields. | Include compose in existing `entry.updated` mapping and emit sanitized routing metadata. | Fixed |
| R2-05 | P1 | Queue concurrency | Workers claimed current queue state but used attempt counters/payload metadata from earlier batch selection. Deterministic interleaving produced retry attempt 1 after stored attempt 2. | Select candidate IDs, then acquire and read authoritative metadata in one immediate transaction. | Fixed |
| R2-06 | P1 | Worker efficiency | Serial jobs polled child completion with `sleep 1`; five empty scheduler jobs took a 6.430s median. | Wait directly; renew leases in independently stoppable helpers. | Fixed |
| R2-07 | P2 | Resource lifetime | Normal-path-only cleanup could retain timers, job descendants and output files; DNS resolution preceded curl's bounded timeout. | Trap cleanup and reap owned processes; parent-liveness checks; bound DNS child lifetime by connection timeout. | Fixed |

R2-01's security severity is medium after accounting for required extension administration credentials, despite its high-impact filesystem consequence. R2-02 is medium. The queue/content findings are correctness and reliability issues; they are not presented as independent privilege-escalation vulnerabilities.

## Changes and proof

### Managed package cleanup

`backend/routes/extension_packages.kujo` now admits only the generated immediate child `package-<32 lowercase hex characters>` under the configured storage root. Recursive cleanup does not traverse symlinks. Before replacing an existing installation, CMS verifies a `.cms-owner-<id>.json` sibling record containing the extension kind and key. The record is written by CMS outside extracted content, so neither archive members nor mutable config establish ownership.

Live regressions in `scripts/integration-hardening.py` prove traversal and symlink targets survive, another plugin's real installation survives a forged reference, a same-key theme survives a forged plugin reference, and legitimate newly owned replacements still remove nested files. A valid-looking unmarked legacy directory is deliberately retained. Legacy installations remain usable; replacing one may leave its old unmarked directory for operator inspection rather than deleting a path whose ownership cannot be established. No database migration is needed. Keep sidecars with the installed storage directory when moving or restoring that directory.

The original sentinel deletion was reproduced before the fix. An intermediate legacy-root test exposed a missing-file native inspection error; the final implementation checks existence before symlink inspection and passes that case.

### Public media admission

`backend/routes/media_storage.kujo` invokes the normal public guard before database lookup or whole-file read. Anonymous reads still return the existing JSON/base64 envelope. A live regression uploads a PNG, reads it anonymously, exhausts the persistent rate bucket, and requires HTTP 429. The same request returned HTTP 200 before this change. Existing ingress, filesystem configuration and media-size limits remain unchanged.

### Composition integrity and webhooks

`backend/routes/content_workflows.kujo` re-reads the entry and lock after `BEGIN IMMEDIATE`. An intervening snapshot change or lock returns the existing conflict family and rolls back before recording a revision. Every successful composition advances `updated_at`, including term-only operations. Values remain epoch seconds in the existing text field, with millisecond fractional precision and a minimum 0.001-second advance. Consumers should preserve the returned value as an opaque `expected_updated_at` token rather than round it.

Composition audit details now include the content type, slug, status and publication timestamp consumed by `scripts/enqueue-webhook-outbox.sh`. The producer maps compose to the existing `entry.updated` event. Tests verify term-only version advancement, stale-write rejection, rapid content version advancement, two update events, and no duplicates on a second enqueue run. The transactional recheck is additionally source-verified; no deterministic live scheduler race was forced in this pass.

### Queue claims, waiting and cleanup

Both worker scripts select candidate IDs only. The claim update and ownership-filtered metadata read occur in one immediate SQLite transaction; retry/backoff calculations therefore use the state actually claimed. This avoids adding a SQLite CLI `RETURNING` version requirement. The deterministic `scripts/test-worker-claims.py` fixture advances attempt metadata between candidate selection and claim: original code wrote retry attempt 1, corrected code dead-letters attempt 3 for both queues. Existing dual-worker integrations continue to test ordinary competing claims.

`scripts/worker-lifecycle.sh` centralizes timer ownership, heartbeat start/stop, normal completion and signal cleanup. Background jobs use `wait` instead of completion polling. Renewal checks the worker PID before and after its timer, preventing renewal from continuing indefinitely after a worker crash. Timers are killed and reaped via the helper's job table, including the signal window before a timer PID assignment. Background termination also stops owned job descendants and removes its temporary output. Python 3 is now checked explicitly by the background worker; it was already required by the repository's webhook pipeline. No third-party package was added.

`scripts/test-worker-lifecycle.py` uses a FIFO readiness handshake, not arbitrary sleeps, to prove timer termination closes captured pipes and SIGTERM removes the owned child and temporary file. One intermediate captured-output test found a timer cleanup race; the final tests cover that lifetime. SIGKILL cannot execute shell cleanup; renewal stops when the helper next checks parent liveness, and claims remain reclaimable after their bounded lease. Worker effects retain the existing at-least-once semantics after a crash.

Webhook DNS runs in a bounded child process before curl, using the existing connection timeout; failed/expired resolution takes the existing egress-denial path. Destination classification, DNS pinning, proxy exclusion, signature and delivery timeout remain intact.

## Measured performance and efficiency

The complete background worker processed five empty `scheduler.run` jobs in each of three samples. Each sample used a fresh SQLite schema and asserted all five jobs completed once with released claims. This measures full worker completion, unlike round one's isolated 500-entry scheduler SQL benchmark.

| Full worker measurement | Before | After |
|---|---:|---:|
| Median seconds, five jobs | 6.429926 | 1.966914 |
| Samples | 3 | 3 |
| Completion polling | One-second loop per job | Direct child wait |

| Endpoint | Before avg / p95 (ms) | After avg / p95 (ms) |
|---|---:|---:|
| health | 47.632 / 53.397 | 44.312 / 47.062 |
| capabilities | 53.521 / 66.443 | 46.043 / 48.287 |
| robots | 49.902 / 52.321 | 46.259 / 50.938 |
| security-txt | 55.634 / 64.609 | 50.662 / 52.492 |
| llms | 55.006 / 60.065 | 53.933 / 76.358 |
| sitemap | 53.338 / 57.025 | 53.639 / 60.383 |
| rss | 56.105 / 59.079 | 71.282 / 107.168 |
| entries-list | 58.585 / 62.488 | 65.773 / 77.343 |
| media-list | 54.021 / 60.097 | 52.172 / 64.536 |
| menus-list | 53.155 / 56.285 | 49.454 / 53.798 |
| plugins-list | 59.175 / 63.207 | 55.471 / 58.082 |
| themes-list | 77.940 / 205.113 | 49.990 / 53.577 |
| roles-list | 67.621 / 117.220 | 59.407 / 68.326 |
| tokens-list | 62.609 / 66.852 | 57.205 / 61.750 |

The same ten-request endpoint sample was run before and after; this is local budget evidence, not a production SLO or a claim that every endpoint improved. No memory, CPU, binary-size, build-time or token-count improvement is claimed. New ownership sidecars add a small record per installation; legitimate replacement removes the old owned record. Logs and raw measurements remain available under `results/` with short test receipts.

Agent-facing instructions, tool discovery and public WebMCP scope were reviewed against the first pass. No new prompt/schema/context expansion or speculative token optimization was justified. Existing bounded discovery, compact root instructions, dependency pins and client contracts were preserved. No unused dependency or compatibility code removal was justified by evidence.

## Security coverage and compatibility

The independent Standard security scan is `49980e3b-dadf-4563-b48a-fbbf3a2a257b`, targeting the starting SHA. It records the two validated security findings above. Independent reviews covered auth/session/provider identity, media, extension cleanup, public WebMCP, queue egress, capabilities, input helpers and configuration; additional authz, tenancy, entry, plugin/theme, Ability, runtime/schema and CI paths were traced where needed. Coverage is explicitly risk-focused/partial: historical generated reports and every repetitive handler were not fully reviewed. Native archive limits inspected in the previous round were retained as dependency evidence, not reclassified as a new vulnerability. Production TLS, ingress and host ACLs remain deployment responsibilities.

- HTTP routes, response envelopes, capability names and ordinary success codes are unchanged. Media now honors configured rejection; stale composition produces conflict rather than silent replacement.
- Compose `updated_at` gains fractional-second precision; retain exact values when using optimistic checks. No column, schema revision or environment variable was added.
- Existing webhook event names/schema are unchanged; compose now emits the already supported `entry.updated` event.
- Queue CLI arguments, summary fields and retry policy remain stable; claims use current counters and completion is faster.
- Installed storage gains server-owned sidecars. Missing/untrusted legacy ownership prevents automatic cleanup, not installation or use.
- No sibling repository was modified; no required cross-repository rewrite or follow-up.

## Remaining work

- P0/P1/P2: no validated defect from this round remains unfixed.
- P3: no cosmetic changes proposed.
- Needs more evidence: deployed ingress/ACL posture, crash/fault injection under production concurrency, and execution with the pinned CI runtime version. Existing at-least-once delivery is not a promise of exactly-once remote side effects.
- Not worth changing: established dependencies, broad route style, generated history, and bounded algorithms without workload evidence.

## Verification receipt

| Command | Result |
|---|---|
| `CMS_GATE_PORT_BASE=50700 CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh > results/hardening-round2/baseline.log 2>&1` | Baseline passed; 39 contracts and complete existing gate |
| `CMS_TEST_PORT=50917 python3 scripts/integration-hardening.py` | Before: term-only version, cleanup traversal and exhausted media regressions reproduced in separate runs; after: all cases passed |
| `CMS_WORKER_SCRIPT_ROOT="$PWD/results/hardening-round2/baseline-source" python3 scripts/test-worker-claims.py` | Original worker deterministically failed with stale retry count 1 |
| `python3 scripts/test-worker-claims.py` | Both authoritative-claim cases passed on final code |
| `python3 scripts/test-worker-lifecycle.py` | Captured pipe closure, timer reaping and TERM cleanup passed |
| `python3 results/hardening-round2/measure-worker.py before` and `... after` | Three samples each, five completed jobs verified per sample; final after run occurred after the gate |
| `CMS_GATE_PORT_BASE=50900 CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh > results/hardening-round2/final-gate.log 2>&1` | Passed 39/39 contracts, JS/PHP clients, budget validator, new hardening/claim/lifecycle tests, durable rates, all integrations, WebMCP/smoke, security, audit, pagination, jobs/webhooks/idempotency, graceful restart, migration/backup/restore/load and performance budgets |
| `CMS_COMPAT_PORT=51080 bash scripts/verify-compat-startup.sh > results/hardening-round2/compat.log 2>&1` | Passed |
| `bash scripts/test-release-port-safety.sh` | Passed |
| `bash -n` for all 43 shell scripts; Python AST parse for changed tests | Passed |
| `git diff --check` | Passed |

Post-gate process inspection found no CMS test runtime retaining repository results-log descriptors. The gate's claim/lifecycle tests also capture subprocess output with deadlines, so retained helper pipes cannot silently pass. Core endpoint budgets were unchanged.

The sealed Standard scan reports 13,516,045 total rollout tokens across four threads, including 13,122,688 cached input tokens (measurement source `codex_rollout`). This is the scanner's accounting, not a repository token-efficiency result or a Codex goal budget.
