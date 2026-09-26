# Repository hardening audit

## Repository

- Name: `cms`
- Purpose: server-first Kujo CMS runtime, persistence, delivery API, identity, extensions, and operational tooling
- Branch: `main`
- Starting SHA: `b16d22ead14e86484d99ead07fc13a5ad3be49e8`
- Ending implementation SHA: `e2e1d7f43547d5bf2ea95a393c93ced93ec2693c`
- Important integrations: Kujo runtime, SQLite, Kennel packages, CMS extension packages, sibling `cms-example`

## Baseline

The starting tree was clean and synchronized with `origin/main`. The complete
release gate passed before changes: 36 contract tests, every integration stage,
migration/backup/restore checks, operational load, graceful restart, and
performance budgets. A 10-run endpoint sample recorded average latency from
69.6 ms (`/health`) to 83.1 ms (`/v1/entries`); all sampled endpoint p95 values
were at or below 107.4 ms. The larger operational sample had one 1.30 s media
outlier, while the repeated 10-run media sample averaged 70.1 ms with a 90.6 ms
p95. These are local end-to-end process measurements, not production SLOs.

The repository had no compact root agent guide. Its README was 20,849 bytes,
so an agent needed to load a broad document before locating runtime, security,
schema, and verification boundaries.

## Findings

| ID | Priority | Area | Finding | Evidence | Action | Status |
|---|---|---|---|---|---|---|
| CMS-001 | P1 | Runtime/resource | Session and database API-token authentication updated activity timestamps on every authorized request, turning reads into writes and increasing SQLite contention. | Unconditional `UPDATE` statements in both authentication paths. | Throttle activity writes to at most once per credential per 60 seconds and add a regression assertion. | Fixed |
| CMS-002 | P2 | Agent context | No root task map existed; the 20,849-byte README was the smallest repository overview. | No starting `AGENTS.md`. | Add a 1,385-byte progressive-disclosure guide with code boundaries and canonical verification. | Fixed |
| CMS-003 | P2 | Dependencies/supply chain | Runtime and package installation inputs are externally sourced. | CI setup action and Kennel checkout inspected. | Confirmed both are commit-pinned; no change justified. | Verified |
| CMS-004 | Needs more evidence | Browser performance | Core Web Vitals could not be traced in this environment. | Chrome DevTools MCP was unavailable. | Preserve API/process baselines and run the browser trace when the browser performance integration is available. | Open |

## Changes implemented

### Authentication activity write coalescing

- Problem: successful session and database-token reads always performed a
  SQLite update.
- Root cause: `last_seen_at` and `last_used_at` were treated as exact per-request
  telemetry rather than coarse activity markers.
- Implementation: update only when the prior value is null or older than 60
  seconds, using the runtime's epoch timestamp representation.
- Files: `backend/modules/auth.kujo`, `tests/cms_contract_tests.kujo`.
- Compatibility: authorization, response envelopes, expiry, permissions, and
  credential formats are unchanged. Activity timestamps may be up to 60 seconds
  behind, which matches their operational purpose.
- Measured impact: authenticated activity writes change from one per request to
  at most one per credential per 60-second window. No latency percentage is
  claimed because the endpoint performance suite uses the bootstrap credential,
  not database sessions/tokens.

### Progressive agent context

- Problem: task routing required broad README loading.
- Implementation: added a root map of runtime, config, schema, auth, HTTP,
  routes, public contracts, and verification entry points.
- File: `AGENTS.md`.
- Measured impact: the first-hop repository guide is 1,385 bytes versus the
  20,849-byte general README (93.4% smaller), while the README remains available
  on demand.

## Performance and efficiency

- Baseline 10-run p95 range: 84.1-107.4 ms across sampled API/delivery routes.
- Baseline 10-run average range: 69.6-83.1 ms.
- Final 10-run p95 range: 67.6-146.2 ms; average range: 61.4-111.0 ms.
  The suite passed its budgets. This short local sample shows run-to-run variance
  and is not used to claim a general endpoint latency improvement.
- Authenticated database activity writes: one/request before; at most
  one/credential/60 seconds after.
- Agent first-hop context: 20,849 bytes before; 1,385 bytes after.
- No memory, binary-size, or token-count percentage is claimed beyond these
  directly measured dimensions.

## Security

Manual review covered bearer/session parsing, credential hashing and expiry,
production bootstrap-token policy, rate-limit bounds, CORS/security headers,
body limits, database parameterization, path/archive validation, webhook/SSRF
controls, subprocess scripts, temporary files, and secret-bearing API records.
No new P0 vulnerability was validated. Existing production configuration fails
closed for unsafe bootstrap policy, rate-limit state is bounded, credential
secrets are hashed at rest, and extension/media paths have dedicated validation.
The user explicitly asked to skip Codex DeepScan; this report does not claim a
DeepScan result.

## Compatibility

- Public APIs changed: no.
- CLI behavior changed: no.
- File formats or schemas changed: no.
- Configuration or environment variables changed: no.
- External consumers affected: only activity timestamps may refresh less often;
  authorization and audit behavior are unchanged.

## Cross-repository follow-ups

None required. The sibling frontend can consume this change without updates.

## Remaining work

- P0/P1/P2: none validated and left unfixed.
- Needs more evidence: browser Core Web Vitals trace when Chrome DevTools MCP is
  available; production-profile load testing under concurrent database-token
  traffic.
- Not worth changing: micro-optimizing bounded list loops or replacing pinned,
  established dependencies without workload evidence.

## Verification receipt

| Command | Result |
|---|---|
| `KUJO_BIN=/Users/robertdevore/.local/bin/kujo CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh` (baseline and final) | Passed twice |
| `/Users/robertdevore/.local/bin/kujo test-run tests/cms_contract_tests.kujo` | 36/36 passed |
| `git diff --check` | Passed |

Generated benchmark evidence remains under ignored `results/` paths rather than
being committed.
