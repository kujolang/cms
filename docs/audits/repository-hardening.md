# Kujo CMS repository hardening audit

Latest continuation: [hardening audit round two](repository-hardening-round-2.md).

## Repository and scope

- Repository: `cms`; branch: `main`.
- Starting SHA: `60180cd53c415393a0e4958fe76cde7fcc713b48` (clean tree).
- Ending implementation SHA: `805f38d200f11a281704d5538ea7c9039627ba01`. The subsequent documentation commit records this immutable implementation revision; a document cannot contain its own commit hash.
- Audit date: October 10–11, 2026 (America/Detroit).
- Purpose: server-first HTTP CMS with SQLite persistence, authenticated administration, public delivery, portable Abilities, extension metadata, and operator-run workers. `backend/runtime/main.kujo` assembles the actual service; `../cms-example` owns the UI.
- Dependencies: Kujo native HTTP/SQLite/crypto/filesystem primitives, pinned Kennel Ability runtime, SQLite and shell worker tools, Node and Python verification, dependency-free JavaScript/PHP clients. Local executable: Kujo 1.5.0. CI remains pinned to Kujo 1.2.2; relevant native HTTP options were checked in that source tag, but this session did not execute that older binary.

This replaces the previous audit at this path; its history and earlier activity-write coalescing measurements remain available at the starting SHA. Historical browser Core Web Vitals work belongs to `cms-example`, outside this backend write scope.

## Baseline

Before source changes, `CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh` passed: 36 contracts, all existing integration stages, migration/backup/restore, graceful restart, operational load, and endpoint performance budgets. JavaScript and PHP client scripts also passed separately. PHP's default invocation can disable assertions; the strengthened gate explicitly enables them.

The passing baseline did not cover realistic expired credentials, shared request state, withdrawn scheduler drafts, or bulk hierarchy cycles. New reproductions failed against the original behavior. Later gate retries exposed pre-existing orphan test servers and inadequate loopback port detection; these were fixed rather than treated as application failures. Intermediate failures introduced while implementing request propagation, replay compatibility, and shell launch changes were corrected before the final gate.

Evidence is retained locally under ignored `results/hardening-20261010/`: `baseline.log`, `perf-before.json`, targeted regression logs, `scheduler-measurement.json`, `measure-scheduler.py`, `final-gate.log`, `perf-after.json`, and `compat.log`. Generated databases and credential-bearing fixtures are not source artifacts.

## Findings

| ID | Priority | Area | Finding and evidence | Action | Status |
|---|---|---|---|---|---|
| H01 | P0 | Authentication | Parsed credential expiry is epoch milliseconds; `now()` is seconds. Realistically expired tokens remained valid. | Compare with `current_timestamp()` using inclusive expiry; test epoch and ISO inputs. | Fixed |
| H02 | P1 | State and observability | Kujo copies dictionary arguments; memory rate counters and metrics did not persist across calls. SQLite limiter used read/replace and fell back to ineffective memory state on errors. | Shared native in-memory database; atomic bounded increment, expired-key pruning, fail-closed persistent mode, real metric reads. | Fixed |
| H03 | P1 | Request and audit | Guard changes to request dictionaries were discarded; session audit identity, request correlation, and idempotency completion lost context. Required Ability audits unconditionally reported success. | Return/consume enriched requests, preserve verified session actor, case-insensitive headers, inspect actual audit write result, preserve replay metadata. | Fixed |
| H04 | P1 | Scheduling and locking | API scheduler and lock deadlines mixed seconds and milliseconds. Shell scheduler selected drafts instead of scheduled content. | Correct deadline clock; only publish scheduled content; test a withdrawn draft with retained publish time. | Fixed |
| H05 | P1 | Egress and resources | Plugin and connector health calls lacked native destination policy, DNS pinning and transport response bounds. Text URL checks alone cannot enforce resolved destinations. | Apply native private-destination denial, DNS pinning, no redirects and 1 MiB response bound at both transports. | Fixed |
| H06 | P1 | Hierarchy integrity | Bulk term updates could create cycles; recursive `UNION ALL` could revisit corrupted rows indefinitely. | Transactional cycle rejection/rollback and deduplicating recursive unions. | Fixed |
| H07 | P1 | Worker performance | Scheduler launched one SQLite process per due entry and did not atomically select/update the batch. | One immediate transaction with bounded updates and actual change counts. | Fixed |
| H08 | P2 | Worker resources | Webhook response was written to a temporary file but never consumed. | Discard body at curl output while retaining status/errors and retry receipts. | Fixed |
| H09 | P2 | Verification | Missing/invalid timing values became zero and could pass budgets. Client, durable-rate and new security regressions were absent from release gate. | Validate report numbers/bounds and budgets; add behavioral validator cases and gate steps; enable PHP assertions. | Fixed |
| H10 | P1 | Harness lifecycle | Killing background launcher shells left runtime servers alive; wildcard port probes missed loopback conflicts on this host. | `exec` actual servers, probe loopback, portable false executable and occupied-listener regression. | Fixed |
| H11 | P2 | Agent ergonomics | Root guide named nonexistent config/contracts paths and unsupported focused test syntax. | Correct progressive-disclosure paths and canonical command. | Fixed |

## Changes implemented and compatibility

### Authentication, state and audit

`backend/modules/auth.kujo`, `backend/core/http.kujo`, `backend/runtime/main.kujo`, `backend/modules/authz.kujo`, and guarded route handlers now respect native clock and value semantics. Every successful guard carries the enriched request explicitly. The broad route diff is propagation of that single context contract, not a route redesign.

The memory limiter uses an in-memory SQLite handle shared across route calls, with bounded keys and expired-key pruning. The persistent limiter uses its existing database table and an atomic capacity check/increment, so errors cannot silently remove enforcement. Metrics retain their JSON keys and now accumulate. Session audit actors use verified authentication context; bearer actor hashing remains compatible. `write_audit` returns a structured internal receipt and Ability execution checks it.

Contracts cover realistic expiry, rate exhaustion/capacity/recovery/failure, metrics and audit persistence/failure. Live tests cover epoch and ISO expiry, canonicalized header spelling, session actor/request ID persistence and metrics. Existing durable-rate tests prove restart behavior. Existing idempotency tests prove replay compatibility: completed data is retained and the established non-Ability replay marker is added where needed.

### Scheduling and hierarchical state

`backend/routes/entries.kujo` and `content_workflows.kujo` use epoch milliseconds for lock/schedule deadlines while preserving existing timestamp serialization for ordinary activity fields. The worker's `scheduler.run` transaction publishes only `scheduled` records and archives due published records, with each selection capped at 500. The same receipt keys remain available. Integration fixtures now use realistic past deadlines and explicitly retain a withdrawn draft.

Bulk taxonomy writes validate the resulting ancestry before committing. A self-cycle or multi-node cycle returns the existing `invalid_parent_id` error with HTTP 400 and rolls back the batch. Recursive term/menu readers deduplicate visited IDs even for pre-existing corrupt data. Live tests verify rejection and rollback. No schema migration is required.

### Transport and operations

`backend/routes/abilities.kujo` uses one bounded native options helper for plugin invocations and connector health. Existing private-network opt-in is preserved for plugin services. Redirects are deliberately not followed: configure the final service URL. Local integration points a dotted localhost name at a sink and verifies rejection without contacting it. Source inspection confirms destination enforcement happens at native resolution; this is not a claim of production DNS-rebinding penetration testing.

The webhook worker retains HTTP status, failure handling and retries while removing an unused body file. Integration launchers replace their shells with the server process so cleanup targets the real process. The port-safety regression proves an unrelated loopback listener remains alive when the gate refuses its occupied port.

### Verification and documentation

The release gate adds JavaScript/PHP contracts, malformed performance-report tests, live hardening tests, and persistent/memory rate behavior. CI installs PHP explicitly. Performance/load fixtures set enough request capacity for their defined sample so they measure successful requests while dedicated limiter tests verify denial. No production limit or performance budget was weakened.

`AGENTS.md`, extension transport documentation and runtime limitations now describe the actual commands, state semantics, clock convention and outbound behavior. No style-only refactor, dependency replacement, speculative cache or dead-code removal was justified.

## Performance and efficiency

The scheduler experiment ran five samples with 500 due entries, verified 500 published rows and receipt counts, and counted SQLite launches using a PATH wrapper. Before uses original draft eligibility; after uses corrected scheduled eligibility, keeping the due-work size equal. This isolates scheduler work, not complete worker queue latency.

| Measurement | Before | After |
|---|---:|---:|
| Scheduler median, 500 due records | 11.819750 s | 0.066606 s |
| SQLite processes per scheduler sample | 502 | 1 |
| Scheduler samples | 5 | 5 |
| Unused webhook response files per attempt | 1 | 0 |

| Endpoint | Before average / p95 (ms) | After average / p95 (ms) |
|---|---:|---:|
| health | 67.124 / 79.284 | 43.760 / 55.354 |
| capabilities | 63.751 / 91.293 | 44.826 / 47.319 |
| robots | 61.812 / 72.648 | 46.436 / 49.002 |
| security-txt | 70.156 / 86.435 | 47.948 / 50.276 |
| llms | 68.063 / 75.934 | 46.975 / 51.969 |
| sitemap | 70.760 / 82.619 | 44.259 / 45.887 |
| rss | 88.128 / 117.389 | 47.711 / 49.462 |
| entries-list | 82.423 / 92.931 | 49.394 / 51.719 |
| media-list | 98.917 / 107.178 | 45.074 / 48.073 |
| menus-list | 88.565 / 92.618 | 44.158 / 46.001 |
| plugins-list | 106.238 / 116.176 | 49.229 / 51.189 |
| themes-list | 89.397 / 102.880 | 44.831 / 47.310 |
| roles-list | 122.959 / 132.386 | 50.915 / 58.777 |
| tokens-list | 125.097 / 133.666 | 52.055 / 71.146 |

Endpoint samples are 10 sequential requests per endpoint on this local host. Real rate/metric state now performs work that the old implementation silently discarded. These samples support budget compliance, not a general endpoint speedup or production SLO. No peak-memory, CPU, binary-size or token-count improvement is claimed. Runtime dependency surface is unchanged. The in-memory state has explicit rate-key bounds; metrics have a fixed vocabulary.

Agent-facing review found an already bounded public WebMCP tool surface and selective discovery. The root guide correction improves retrieval accuracy without claiming token savings. Detailed command logs remain in artifacts with concise gate labels/receipts. No logging, error detail, validation or test assertion was removed to reduce output.

## Security review and limits

Reviewed trust boundaries include HTTP input/headers/body limits, session and bearer authentication, scoped authorization, tenancy, approval-bound Ability dispatch, SQL parameters, idempotency/audit, hierarchy writes, native outbound requests, webhook workers, media paths, archive extraction, environment loading, subprocess cleanup, CI inputs and secret projections. Independent source reviews corroborated the main findings; the final security diff review reported no additional blocker.

The Standard Codex Security record is `2d6fb708-aa11-46c8-ac78-2d7190c7152e`, targeting the starting SHA and recording six source-supported security findings remediated in this pass. Coverage is explicitly partial/risk-focused: historical generated artifacts and repetitive fixtures were not exhaustively audited line by line. Deployed ingress, TLS and host filesystem ACLs are outside this local audit. Native archive limits were inspected; replacing bounded native extraction with handwritten code was not justified.

## Public compatibility

- HTTP routes, envelopes, capability names, normal status codes and metrics keys remain stable. Bug cases now correctly reject expired credentials, exhausted/failed rate state, hierarchy cycles and prohibited outbound destinations.
- CLI worker receipt keys and command interfaces remain stable. Scheduler behavior intentionally corrects draft publication; operators should use the supported scheduled state.
- Existing data/config formats, schema revision and environment names are unchanged; no migrations or new runtime dependencies.
- Internal guard and audit return values changed; in-repository callers were updated. These are implementation modules, not the versioned HTTP or client interface.
- Plugin services that depend on redirects must configure their final URL. Private-network plugin opt-in still exists. JavaScript/PHP consumers and the sibling frontend require no rewrite.

## Cross-repository follow-ups and remaining work

No cross-repository change is required. The Kujo native dictionary behavior is an application integration constraint, not an asserted runtime defect. No sibling repository was modified.

- P0/P1/P2: no validated finding from this pass remains unfixed.
- P3: no cosmetic cleanup proposed.
- Needs more evidence: production-profile concurrent traffic and deployment-specific ingress/ACL testing; local sequential samples do not establish those properties. This is a coverage limit, not a newly confirmed defect.
- Not worth changing: bounded list loops, established helper duplication with documented runtime compatibility history, pinned dependencies, and historical fixtures without proof they are unused.

## Verification receipt

| Command | Result |
|---|---|
| `CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh > results/hardening-20261010/baseline.log 2>&1` | Passed before changes; 36 contracts |
| `kujo test-run tests/cms_contract_tests.kujo` | Final gate: 39/39 passed; targeted original-behavior reproductions failed before fixes |
| `node --test clients/javascript/test/client.test.js` | 3/3 passed |
| `php -d zend.assertions=1 -d assert.exception=1 clients/php/tests/client_test.php` | Passed with assertions enabled |
| `node scripts/test-perf-budget.mjs` | Passed valid/invalid report and budget cases |
| `python3 scripts/integration-hardening.py` | Passed live expiry, actor, metrics, cycle rollback and private-target cases; gate supplied `CMS_TEST_PORT=50517` |
| `bash scripts/integration-rate-limit-durable.sh` | Passed persistent and memory modes; gate supplied ports 50518/50519 |
| `python3 results/hardening-20261010/measure-scheduler.py` | Five before/after samples; row counts and process counts verified |
| `CMS_GATE_PORT_BASE=50500 CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh > results/hardening-20261010/final-gate.log 2>&1` | Passed all stages, smoke/WebMCP, enterprise security, audit, pagination, webhooks, idempotency, jobs, graceful restart, migration/backup/restore, load and budgets |
| `CMS_COMPAT_PORT=50680 bash scripts/verify-compat-startup.sh > results/hardening-20261010/compat.log 2>&1` | Passed |
| `bash scripts/test-release-port-safety.sh` | Passed; occupied loopback listener preserved |
| `bash -n` for each of 42 `scripts/*.sh` files | Passed |
| `git diff --check` | Passed |

A post-gate `pgrep`/`lsof` check found no CMS test runtime retaining a repository results-log descriptor. The release gate source records the exact integration subcommands and port environment. Earlier unsuccessful gate attempts and focused failures are retained in local logs; only the final completed run is the verification receipt.

The committed report records meaningful commands and outcomes. Verbose intermediate logs, database fixtures and raw measurements stay in ignored `results/`; final source checks use `git diff --check`. All claims above distinguish measured behavior from source-supported inference and untested deployment conditions.
