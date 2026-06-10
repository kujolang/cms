# Next Session Enterprise Enhancement Checklist (v0.1 -> v0.2)

## Purpose

This checklist captures the highest-value follow-up work after Stage 1-3 completion and full release-gate validation.

Use it as the execution source for the next improvement loop so each item can be implemented and validated with low regression risk.

## Baseline Evidence (Current State)

Validation baseline captured on 2026-05-26:

- Full release gate: pass (`scripts/run-release-gate.sh`)
- Contract tests: pass (`tests/cms_contract_tests.ruff`)
- Stage 1/2/3 integration matrix: pass
- Multi-tenant, enterprise security, webhook/idempotency/background-jobs pipelines: pass
- Performance budget checks: pass

Current conclusion:

- Kujo CMS is production-capable for v0.1 deployments when standard hardening controls are configured.
- Remaining work below is focused on enterprise optimization, stronger misuse resistance, and DX clarity for wider adoption.

## Execution Protocol (One Item Per Loop)

1. Pick the first unchecked item.
2. Implement only that item (or explicit coupled mini-scope).
3. Run the listed validation commands.
4. Update README/CHANGELOG if behavior changes.
5. Mark item complete with date + commit hash + short summary.

## Tier A - Immediate (Security + Scale)

### [x] E-01: Remove N+1 term loading in entries include path

- **Implementation expectations**:
  - Replace per-entry taxonomy term lookups in `GET /v1/entries?include=terms` with one batched term query.
  - Use entry ID collection + `IN (...)` query + in-memory merge by `entry_id`.
  - Keep response shape unchanged.
- **Acceptance criteria**:
  - Entry list with included terms executes constant query count (no O(n) growth).
  - Existing projection and filter behavior stays compatible.
- **Validation/testing expectations**:
  - `CMS_TEST_PORT=53010 bash scripts/integration-stage2-round2-projection.sh`
  - `CMS_TEST_PORT=53011 bash scripts/integration-stage1.sh`
  - Optional query-count probe for `GET /v1/entries?limit=50&include=terms`
- **Dependencies/unknowns**:
  - Ensure SQLite parameter count remains safe for higher limits.

### [x] E-02: Harden bootstrap token policy defaults for production

- **Implementation expectations**:
  - Keep dev ergonomics intact but make production posture stricter by default.
  - Enforce bootstrap-token rotation when `CMS_ENV=production` unless explicitly disabled.
  - Reject unchanged default token and add stronger minimum token quality checks.
- **Acceptance criteria**:
  - Production cannot run with `change-me-in-production` bootstrap token.
  - Existing explicit override knobs still work for controlled environments.
- **Validation/testing expectations**:
  - `CMS_TEST_PORT=53012 bash scripts/integration-enterprise-security.sh`
  - `KUJO_BIN=/Users/robertdevore/2026/ruff/target/debug/ruff test-run tests/cms_contract_tests.ruff -v`
- **Dependencies/unknowns**:
  - Decide final entropy rule (length-only vs. character-class rule).

### [x] E-03: Add durable/shared rate-limit mode option

- **Implementation expectations**:
  - Introduce optional SQLite-backed rate state in addition to `memory|external|off` modes.
  - Preserve current in-memory behavior as default for simple deployments.
  - Keep key-cap guard semantics clear per mode.
- **Acceptance criteria**:
  - Rate-limit behavior can survive process restart in durable mode.
  - No regression in existing memory-mode behavior.
- **Validation/testing expectations**:
  - Add focused integration script for restart persistence in durable mode.
  - `CMS_TEST_PORT=53013 bash scripts/integration-enterprise-security.sh`
  - `CMS_GATE_PORT_BASE=53020 bash scripts/run-release-gate.sh`
- **Dependencies/unknowns**:
  - Clarify multi-instance coordination expectations when using SQLite.

## Tier B - Near-Term (Reliability + API Consistency)

### [x] E-04: Expand idempotency coverage beyond entry create/delete

- **Implementation expectations**:
  - Extend idempotency to additional write endpoints with stable replay semantics.
  - Keep replay headers/envelope consistent with existing behavior.
- **Acceptance criteria**:
  - Retried writes for selected endpoints avoid duplicate side effects.
  - Conflict and in-progress responses remain deterministic.
- **Validation/testing expectations**:
  - Extend `scripts/integration-stage2-round3-idempotency.sh`
  - `CMS_TEST_PORT=53014 bash scripts/integration-stage1.sh`
  - `KUJO_BIN=/Users/robertdevore/2026/ruff/target/debug/ruff test-run tests/cms_contract_tests.ruff -v`
- **Dependencies/unknowns**:
  - Prioritize endpoints by write criticality and external retry frequency.

### [x] E-05: Strengthen plugin hook outbound URL policy against SSRF bypasses

- **Implementation expectations**:
  - Replace simple wildcard host matching with stricter CIDR-aware/private-range checks.
  - Add optional resolve-time verification before dispatch to reduce DNS rebinding risk.
  - Keep existing allowlist/denylist controls backward-compatible.
- **Acceptance criteria**:
  - Internal/private metadata endpoints are reliably blocked.
  - Existing legitimate public webhook hosts continue to register and dispatch.
- **Validation/testing expectations**:
  - Extend `scripts/integration-enterprise-security.sh` with denylist edge cases.
  - `CMS_TEST_PORT=53015 bash scripts/integration-stage2-round3-webhooks.sh`
- **Dependencies/unknowns**:
  - Confirm acceptable DNS resolution behavior in offline/air-gapped environments.

### [x] E-06: Optimize cursor pagination continuation check

- **Implementation expectations**:
  - Replace extra continuation query with `limit + 1` fetch strategy.
  - Keep `next_cursor` semantics and ordering behavior unchanged.
- **Acceptance criteria**:
  - Cursor list endpoint performs fewer queries without changing results.
- **Validation/testing expectations**:
  - `CMS_TEST_PORT=53016 bash scripts/integration-stage2-round2-cursor.sh`
  - Query-count verification on cursor endpoint
- **Dependencies/unknowns**:
  - Ensure compatibility with existing cursor parsing and sort constraints.

### [x] E-07: Add HEAD support for core public GET endpoints

- **Implementation expectations**:
  - Register HEAD routes for key public GET endpoints (`/health`, `/v1`, delivery docs).
  - Ensure HEAD responses do not include full bodies.
- **Acceptance criteria**:
  - `HEAD` requests return expected status/headers for supported endpoints.
- **Validation/testing expectations**:
  - Add targeted HEAD checks in smoke/integration scripts.
  - `CMS_SMOKE_PORT=53017 bash scripts/smoke-api.sh`
- **Dependencies/unknowns**:
  - Decide full vs. selective HEAD coverage for internal endpoints.

## Tier C - Backlog (DX + Migration Clarity)

### [x] E-08: Formalize error code contract documentation

- **Implementation expectations**:
  - Add `docs/error-codes.md` with status/code/message patterns and representative payloads.
  - Cross-check endpoint usage for consistency.
- **Acceptance criteria**:
  - Common failure paths map to documented codes and response shape.
- **Validation/testing expectations**:
  - Run contract tests and representative integration scripts after documentation-aligned cleanups.

### [x] E-09: Add pagination parity for content types listing

- **Implementation expectations**:
  - Add `limit/offset/sort` controls to `GET /v1/content-types` similar to other list endpoints.
  - Maintain compatible defaults and response envelope.
- **Acceptance criteria**:
  - Large content-type sets return paginated, stable results.
- **Validation/testing expectations**:
  - `CMS_TEST_PORT=53018 bash scripts/integration-stage1.sh`
  - Extend pagination parity coverage.

### [x] E-10: Document root-wrapper removal and backend import policy

- **Implementation expectations**:
  - Keep root wrapper removal status current in architecture/readme docs.
  - Document consumer migration guidance for canonical `backend/runtime/main.ruff` startup and dotted `from backend...` imports.
  - Add contribution guidance for preferred backend import targets in new code.
- **Acceptance criteria**:
  - Wrapper-removal intent is clear; migration consumers know what to adopt now.
- **Validation/testing expectations**:
  - Docs consistency review in README + backend architecture notes.

## Completion Log Template

For each completed item, append:

- Completed on: YYYY-MM-DD
- Commit: <hash>
- Summary: <1-3 lines>
- Validation run:
  - `<command 1>`
  - `<command 2>`
