# Next Session Enterprise Enhancement Checklist (v0.2 -> v0.3)

## Purpose

This checklist captures the next high-leverage improvements after the v0.2 hardening loop. It is intended to keep CMS moving toward a stronger, more universally useful Kujo showcase while preserving compatibility and release-gate confidence.

## Baseline Evidence (Current State)

Validation baseline captured on 2026-06-19:

- Contract tests: pass (`kujo test-run tests/cms_contract_tests.kujo -v`)
- Release gate: pass with performance budget skipped (`PATH=/Users/robertdevore/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH CMS_GATE_RUN_PERF=false KUJO_BIN=kujo bash scripts/run-release-gate.sh`)
- Smoke API: pass (`PATH=/Users/robertdevore/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH KUJO_BIN=kujo bash scripts/smoke-api.sh`)
- Compatibility startup: pass (`PATH=/Users/robertdevore/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH KUJO_BIN=kujo bash scripts/verify-compat-startup.sh`)
- List endpoints now use bounded parsing for malformed `limit`, `offset`, `sort_by`, and `sort_dir` inputs instead of direct query casts.
- Active backend source is under `backend/config`, `backend/core`, `backend/modules`, `backend/routes`, and `backend/runtime`.
- Empty migration-era backend placeholders were removed from the tracked tree.

Current conclusion:

- CMS is production-capable for carefully configured deployments and is a strong Kujo server-first showcase.
- It is not yet universally enterprise-complete without repository governance, infrastructure review, and deeper misuse-resistance coverage.

## Execution Protocol (One Item Per Loop)

1. Pick the first unchecked item or an explicitly coupled mini-scope.
2. Keep API response shapes backward-compatible unless versioned.
3. Add focused contract or integration coverage for behavior changes.
4. Run the listed validation commands.
5. Update README, CHANGELOG, and this checklist with date, commit hash, and validation evidence.

## Tier A - Immediate (Robustness + Security)

### [ ] E-11: Add black-box negative-query coverage for list endpoints

- **Implementation expectations**:
  - Add HTTP-level checks for malformed `limit`, `offset`, `sort_by`, and `sort_dir` values across representative public and auth-gated list endpoints.
  - Verify stable 200/400 behavior by endpoint contract and confirm no server crash or malformed envelope.
- **Acceptance criteria**:
  - Representative content, taxonomy, media, menu, plugin, authz, tenancy, and delivery lists have negative-query coverage.
  - Existing integration scripts keep passing without response-shape changes.
- **Validation/testing expectations**:
  - `kujo test-run tests/cms_contract_tests.kujo -v`
  - `KUJO_BIN=kujo bash scripts/smoke-api.sh`
  - Targeted negative-query checks for at least menus, plugins, roles, tenants, and delivery feeds.

### [ ] E-12: Add explicit production configuration doctor output

- **Implementation expectations**:
  - Add a lightweight script or runtime route-safe helper that validates production-critical settings before launch.
  - Check bootstrap token posture, CORS wildcard usage, site URL, security contact, rate-limit mode, DB path, readiness checks, and plugin hook policy.
- **Acceptance criteria**:
  - Operators get actionable pass/warn/fail output without starting a long integration suite.
  - Development defaults remain easy to use.
- **Validation/testing expectations**:
  - Add focused script tests or contract tests for safe/unsafe config examples.
  - Run contract tests and release gate with `CMS_GATE_RUN_PERF=false`.

### [ ] E-13: Harden CORS defaults for production mode

- **Implementation expectations**:
  - Keep `CMS_CORS_ORIGIN=*` convenient in development.
  - Warn or fail in production when wildcard CORS is paired with credentials-sensitive deployment posture.
  - Document the expected explicit-origin configuration.
- **Acceptance criteria**:
  - Production operators receive clear feedback before exposing permissive CORS.
  - Existing development smoke scripts remain compatible.
- **Validation/testing expectations**:
  - Extend enterprise security integration coverage.
  - Run `scripts/integration-enterprise-security.sh` and contract tests.

## Tier B - Near-Term (Performance + Operability)

### [ ] E-14: Add query-count regression probes for expensive read paths

- **Implementation expectations**:
  - Add a lightweight diagnostic mode or integration helper to verify constant-query behavior for entries with included terms, menus with items, and taxonomy term lists.
  - Keep probes advisory unless the harness can make them deterministic.
- **Acceptance criteria**:
  - Future N+1 regressions are visible before release.
  - Probe output is concise and saved under ignored `results/`.
- **Validation/testing expectations**:
  - Run projection, menu, taxonomy, and smoke integrations.

### [ ] E-15: Add backup/restore integrity checksum evidence

- **Implementation expectations**:
  - Extend backup/restore scripts to record checksum and row-count summaries.
  - Preserve existing script flags and local-only behavior.
- **Acceptance criteria**:
  - Restore validation proves data shape and key counts, not only file existence.
  - Operator docs show the expected evidence.
- **Validation/testing expectations**:
  - `KUJO_BIN=kujo bash scripts/ops-load-validation.sh`
  - `bash scripts/backup-db.sh` and `bash scripts/restore-db.sh` with a disposable DB.

## Tier C - Showcase Polish (Adoption + Funnel)

### [ ] E-16: Add a concise API tour for Kujo-curious users

- **Implementation expectations**:
  - Create a short doc that maps CMS capabilities to the Kujo language features demonstrated by each area.
  - Link from README without turning the README into a marketing page.
- **Acceptance criteria**:
  - A new user can understand why CMS is a compelling Kujo example in under five minutes.
  - The tour links to real source files and runnable commands.
- **Validation/testing expectations**:
  - Docs consistency review.
  - Contract tests if any examples or commands change.

### [ ] E-17: Generate a minimal OpenAPI export compatibility fixture

- **Implementation expectations**:
  - Add a fixture or script that fetches `/v1/openapi.json` and checks it can be parsed by common JSON tooling.
  - Keep the current contract route unchanged unless gaps are discovered.
- **Acceptance criteria**:
  - API consumers have a simple compatibility artifact for SDK/client work.
  - Failures explain the exact incompatible field.
- **Validation/testing expectations**:
  - Smoke API check.
  - New OpenAPI fixture check.

## Completion Log Template

For each completed item, append:

- Completed on: YYYY-MM-DD
- Commit: <hash>
- Summary: <1-3 lines>
- Validation run:
  - `<command 1>`
  - `<command 2>`
