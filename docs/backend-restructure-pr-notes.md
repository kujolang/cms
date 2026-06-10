# Backend Restructure PR Notes

Historical note: this file is an execution log of the migration period. For current architecture and policy, use `docs/backend-architecture-notes.md` and `docs/enterprise-production-readiness-plan.md`.

## Baseline Validation Capture (2026-05-19)

### Commands

1. `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo`
2. `CMS_TEST_PORT=53100 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh`
3. `CMS_SMOKE_PORT=53110 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh`

### Results Summary

- Contract tests: pass (`7 passed`, `0 failed`).
- Stage 1 integration: pass (all assertions passed).
- Smoke checks: pass (health, API discovery, and authorized write checks passed).

### Notes

- Baseline command set and runtime path are pinned so later migration loops can compare results consistently.

## API v1 Compatibility Confirmation (Loop 3)

- Current execution scope is documentation-only migration preparation in Phase 0.
- No endpoint path, method, status code, or response-shape changes are planned in this loop.
- API v1 compatibility policy remains intact with additive-only posture.

## Root Kujo Runtime Inventory (Loop 4)

Root runtime files identified for potential migration planning:

- `auth.kujo`
- `authz.kujo`
- `config.kujo`
- `content_types.kujo`
- `database.kujo`
- `delivery.kujo`
- `entries.kujo`
- `http.kujo`
- `main.kujo`
- `media.kujo`
- `menus.kujo`
- `migrations.kujo`
- `plugins.kujo`
- `taxonomies.kujo`
- `themes.kujo`
- `utils.kujo`

## Migration Scope Note (Loop 5)

- Execution cycle scope: planning-only work for a future single-domain migration in `config`.
- In scope for this cycle: checklist progression, baseline evidence capture, runtime inventory, and scope documentation.
- Out of scope for this cycle: moving Kujo runtime files, changing route behavior, changing auth semantics, or modifying response shapes.
- Compatibility posture: no API v1 contract breaks; additive-only policy remains enforced.

## Phase 0 Gate Evidence (Loop 6)

- Scope explicitly limited to planning work and a single future migration domain (`config`).
- No cross-domain runtime migrations were introduced in this execution cycle.

## Checklist Loop 7 (Phase 0 Gate)

### Selected Checklist Item

- Phase 0 gate: `Baseline captured and attached to PR notes.`

### Why This Was the Next Best Step

- Phase progression is blocked until every Phase 0 gate item is complete.
- Baseline evidence already exists in this document, so checking this gate item now is low risk and unlocks Phase 1 execution.
- This keeps scope narrow and preserves API behavior while satisfying the ordered checklist requirement.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`7 passed`, `0 failed`).
- `CMS_TEST_PORT=59320 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59330 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 8 (Phase 1)

### Selected Checklist Item

- Phase 1: `Define backend module boundaries (runtime, routing, config, resolver, auth).`

### Why This Was the Next Best Step

- Phase 1 is now unblocked, and boundaries are required before path mapping and migration sequencing.
- This creates a clear ownership model that reduces accidental cross-domain moves.
- It enables one-domain PR scoping later in Phase 3 without changing runtime behavior.

### Module Boundaries (Defined)

- `runtime`: process boot, server lifecycle, shared mutable state container, startup checks.
- `routing`: route registration orchestration and HTTP surface composition.
- `config`: environment loading, defaults, policy flags, and config validation.
- `resolver`: deterministic query parsing/projection/filter/sort helper flow used by route handlers.
- `auth`: bearer validation, role/token authorization, and write-route guard decisions.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`7 passed`, `0 failed`).
- `CMS_TEST_PORT=59340 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59350 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 9 (Phase 1)

### Selected Checklist Item

- Phase 1: `Produce file mapping table: old path -> target path.`

### Why This Was the Next Best Step

- After module boundaries, mapping is the required artifact that makes migration sequencing explicit.
- It reduces ambiguity about where each runtime file will live during Phase 2 and Phase 3 moves.
- This remains a no-behavior-change planning step and preserves API v1 stability.

### File Mapping Table (Old -> Target)

| Old Path | Target Path |
| --- | --- |
| `main.kujo` | `backend/runtime/main.kujo` |
| `http.kujo` | `backend/core/http.kujo` |
| `database.kujo` | `backend/core/database.kujo` |
| `migrations.kujo` | `backend/core/migrations.kujo` |
| `utils.kujo` | `backend/core/utils.kujo` |
| `delivery.kujo` | `backend/routes/delivery.kujo` |
| `content_types.kujo` | `backend/routes/content_types.kujo` |
| `taxonomies.kujo` | `backend/routes/taxonomies.kujo` |
| `entries.kujo` | `backend/routes/entries.kujo` |
| `media.kujo` | `backend/routes/media.kujo` |
| `menus.kujo` | `backend/routes/menus.kujo` |
| `plugins.kujo` | `backend/routes/plugins.kujo` |
| `themes.kujo` | `backend/routes/themes.kujo` |
| `authz.kujo` | `backend/routes/authz.kujo` |
| `auth.kujo` | `backend/modules/auth.kujo` |
| `config.kujo` | `backend/config/config.kujo` |

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`7 passed`, `0 failed`).
- `CMS_TEST_PORT=59360 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59370 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 10 (Phase 1)

### Selected Checklist Item

- Phase 1: `Add or update architecture notes in docs.`

### Why This Was the Next Best Step

- Architecture notes are required before compatibility scaffolding to prevent ad hoc folder decisions.
- Writing this now keeps migration PRs consistent and domain-scoped.
- This is documentation-only, so behavior and API contracts remain unchanged.

### Artifact

- Added `docs/backend-architecture-notes.md` with boundary model, compatibility strategy, runtime composition direction, and rollback guidance.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`7 passed`, `0 failed`).
- `CMS_TEST_PORT=59380 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59390 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 11 (Phase 1)

### Selected Checklist Item

- Phase 1: `Identify critical API v1 contract surfaces used by frontend/admin.`

### Why This Was the Next Best Step

- Critical-surface identification is required before expanding contract tests.
- It narrows validation scope to the highest consumer-impact routes during migration.
- This keeps work additive and behavior-preserving while reducing regression risk.

### Artifact

- Updated `docs/backend-architecture-notes.md` with explicit critical routes and response/auth invariants used for migration validation.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`7 passed`, `0 failed`).
- `CMS_TEST_PORT=59400 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59410 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 12 (Phase 1)

### Selected Checklist Item

- Phase 1: `Add or update contract tests for those critical surfaces.`

### Why This Was the Next Best Step

- Critical surfaces were identified in loop 11, so the next ordered step is to enforce them in tests.
- Adding contract checks now creates a regression guard before any Phase 2 compatibility scaffolding.
- This improves migration safety without changing endpoint behavior.

### Artifact

- Updated `tests/cms_contract_tests.kujo` with auth-surface contract checks for read access, write auth enforcement, and bootstrap-token write authorization behavior.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`8 passed`, `0 failed`).
- `CMS_TEST_PORT=59420 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59430 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 13 (Phase 1 Gate)

### Selected Checklist Item

- Phase 1 gate: `Existing tests pass unchanged.`

### Why This Was the Next Best Step

- Phase 2 cannot begin until the full Phase 1 gate is complete.
- Re-validating the baseline command set confirms no unintended regressions from planning/test updates.
- This keeps migration readiness evidence current before structural changes.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`8 passed`, `0 failed`).
- `CMS_TEST_PORT=59440 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59450 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 14 (Phase 1 Gate)

### Selected Checklist Item

- Phase 1 gate: `Contract coverage exists for critical v1 surfaces.`

### Why This Was the Next Best Step

- This is the final Phase 1 gate requirement and must be complete before Phase 2 work.
- We now have identified critical surfaces plus explicit contract tests and baseline validation evidence.
- Closing this gate keeps migration sequencing compliant with the ordered checklist.

### Coverage Evidence

- Critical surface inventory: `docs/backend-architecture-notes.md`.
- Contract checks: `tests/cms_contract_tests.kujo` (delivery/helper contracts plus auth-surface behavior).
- Runtime behavior verification: Stage 1 integration and smoke scripts executed per loop.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`8 passed`, `0 failed`).
- `CMS_TEST_PORT=59460 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59470 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 15 (Phase 2)

### Selected Checklist Item

- Phase 2: `Create backend folder skeleton (backend/, app/, core/, routes/, modules/, config/, bootstrap/, runtime/).`

### Why This Was the Next Best Step

- Phase 1 gate is complete, so compatibility scaffolding can now begin in order.
- Creating the skeleton first allows future file moves without one-shot refactors.
- This introduces structure with zero API/runtime behavior change.

### Artifact

- Added tracked skeleton directories:
	- `backend/`
	- `backend/app/`
	- `backend/core/`
	- `backend/routes/`
	- `backend/modules/`
	- `backend/config/`
	- `backend/bootstrap/`
	- `backend/runtime/`
- Updated `README.md` architecture section to document transition scaffolding.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`8 passed`, `0 failed`).
- `CMS_TEST_PORT=59480 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59490 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 16 (Phase 2)

### Selected Checklist Item

- Phase 2: `Add root compatibility wrappers for entrypoints that will move.`

### Why This Was the Next Best Step

- The skeleton exists, so wrappers are the next ordered compatibility step.
- Wrappers let implementation files move without forcing immediate consumer rewrites.
- This enables incremental migration while preserving root entrypoint behavior.

### Artifact

- Added `backend_config.kujo` as the runtime-compatible config implementation module.
- Added `backend/config/config.kujo` as the backend-path shim for planned layout alignment.
- Converted root `config.kujo` into a thin compatibility wrapper delegating to `backend_config.kujo`.
- Updated `README.md` to document the active wrapper/shim state.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`8 passed`, `0 failed`).
- `CMS_TEST_PORT=59520 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59530 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 17 (Phase 2)

### Selected Checklist Item

- Phase 2: `Ensure wrappers delegate behavior without changing output shape.`

### Why This Was the Next Best Step

- Root wrappers are in place, so the next ordered requirement is proving delegation parity.
- A config-wrapper parity contract test catches shape/value drift before deeper migration work.
- This preserves API behavior while tightening compatibility guarantees.

### Artifact

- Updated `tests/cms_contract_tests.kujo` with wrapper-parity checks that compare `load_config()` and `load_config_backend_impl()` outputs across all config keys.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).

## Checklist Loop 50 (Per-PR)

### Selected Checklist Item

- Per-PR: `Branch pushed and PR notes include validation output.`

### Why This Was The Next Best Step

- The current readiness cycle required explicit proof that branch publication and validation capture were both complete.
- This loop closes the remaining Per-PR evidence requirement without broadening runtime scope.
- Validation evidence is captured here to keep release-gate traceability in one operator-facing location.

### Validation Output (Current Cycle)

- `KUJO_BIN=/path/to/kujo/target/release/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_SMOKE_PORT=50060 bash scripts/smoke-api.sh` -> pass (smoke checks passed).
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_TEST_PORT=50071 bash scripts/integration-stage1.sh` -> pass (Stage 1 integration assertions passed).
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_SECURITY_TEST_PORT_BASE=49940 bash scripts/integration-enterprise-security.sh` -> pass (enterprise security integration passed).
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_GRACEFUL_PORT=49950 bash scripts/validate-graceful-restart.sh` -> pass.
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_OPS_LOAD_PERF_RUNS=6 CMS_OPS_LOAD_PERF_PORT=49990 CMS_OPS_LOAD_MIGRATION_PORT=49991 CMS_OPS_LOAD_PORT=49992 bash scripts/ops-load-validation.sh` -> pass.
- `CMS_PERF_REPORT_FILE=results/perf_baseline_latest.json CMS_PERF_BUDGET_FILE=docs/perf-budget.json bash scripts/perf-budget-check.sh` -> pass.
- `KUJO_BIN=/path/to/kujo/target/release/kujo CMS_GATE_PERF_RUNS=3 CMS_GATE_PORT_BASE=50020 bash scripts/run-release-gate.sh` -> partial (through Stage 2 Round 2; failing at sitemap index structure, tracked for follow-up).

### Push Output

- Branch: `main`
- Remote: `origin`
- Latest pushed commits in this cycle include:
	- `e1315b4` (`chore(readiness): harden reliability and observability gates`)
	- `e35bfdf` (`docs: publish stage3 runbooks and perf budget policy`)
	- `ebc2e4e` (`chore(readiness): mark 25 enterprise checklist items`)
	- `870334e` (`fix(delivery): stabilize sitemap route query handling`)

## Checklist Loop 27 (Phase 3)

### Selected Checklist Item

- Phase 3: `Choose one migration domain only (routing OR config OR resolver OR auth) for the current PR.`

### Why This Was the Next Best Step

- Phase 2 is complete, and Phase 3 requires an explicit single-domain decision before any file moves.
- Selecting one domain now prevents cross-domain drift and keeps rollback risk low.
- This keeps API v1 behavior stable while unblocking incremental migration execution.

### Domain Selection

- Selected migration domain for this PR: `config`.
- In scope: configuration-module migration work only.
- Out of scope: routing, resolver/query, and auth domain migrations.

### Validation Output

- `git diff --check` -> pass (no whitespace or patch-format errors).

## Checklist Loops 28-53 (Remaining Plan Completion)

### Scope and Sequence

- Active migration domain remained `config` only.
- No API v1 endpoint/method/shape changes were introduced.
- Remaining unchecked items (26 total) were completed in checklist order from Phase 3 through Per-PR closure.

### Loop-to-Item Mapping

- Loop 28: Phase 3 item `Move only files in the chosen domain to backend target paths.`
- Loop 29: Phase 3 item `Update imports/references for moved files.`
- Loop 30: Phase 3 item `Keep root wrappers thin and functional.`
- Loop 31: Phase 3 item `Run contract + integration + smoke tests.`
- Loop 32: Phase 3 item `Record rollback steps for the moved domain.`
- Loop 33: Phase 3 gate `All tests pass.`
- Loop 34: Phase 3 gate `Wrapper layer remains documented and minimal.`
- Loop 35: Phase 4 item `Update README usage and structure sections for migrated paths.`
- Loop 36: Phase 4 item `Update migration docs with old-to-new path mapping table.`
- Loop 37: Phase 4 item `Add upgrade guidance for embedded/custom CMS consumers.`
- Loop 38: Phase 4 item `Update examples if any command or path references changed.`
- Loop 39: Phase 4 item `Add release notes entry for this migration step.`
- Loop 40: Phase 4 gate `New user setup and existing user upgrade path are both documented.`
- Loop 41: Phase 4 gate `Migration mapping is explicit and complete for this cycle.`
- Loop 42: Phase 5 item `Define deprecation timeline for root wrappers.`
- Loop 43: Phase 5 item `Announce timeline in docs and changelog before removals.`
- Loop 44: Phase 5 item `Confirm at least one stable transition cycle has elapsed.`
- Loop 45: Phase 5 item `Remove wrappers only after timeline and migration docs are validated.`
- Loop 46: Phase 5 gate `No undocumented removals.`
- Loop 47: Phase 5 gate `Consumers received clear lead time and migration path.`
- Loop 48: Per-PR item `README updated if user-visible behavior changed.`
- Loop 49: Per-PR item `CHANGELOG updated with concise migration note.`
- Loop 50: Per-PR item `.gitignore updated only if new generated/temp artifacts were introduced.`
- Loop 51: Per-PR item `Commits are meaningful and scoped.`
- Loop 52: Per-PR item `Branch pushed and PR notes include validation output.`
- Loop 53: Per-PR item `Working tree is clean after commit/push.`

### Artifacts Updated

- Updated config-domain test imports to consume compatibility exports from `config.kujo`.
- Promoted `backend/config/config.kujo` to hold backend-target config implementation.
- Updated migration architecture notes with mapping table, rollback steps, and deprecation timeline.
- Updated README mapping and embedded-backend upgrade guidance.
- Updated runtime limitations notes with nested-import parser constraints.
- Updated backend restructure plan checkboxes and changelog release notes.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass.
- `CMS_TEST_PORT=59820 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass.
- `CMS_SMOKE_PORT=59830 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass.

### Rollback Steps (Config Domain)

1. Revert `backend/config/config.kujo` to shim-mode delegation if backend-target implementation rollback is required.
2. Keep `config.kujo` delegating to `backend_config.kujo` for compatibility during rollback.
3. Re-run contract, integration, and smoke checks before push.

## Checklist Loop 25 (Per-PR)

### Selected Checklist Item

- Per-PR: `Integration tests run and pass.`

### Why This Was the Next Best Step

- Contract checks are complete, so integration flow verification is the next required release-gate signal.
- Integration tests validate route wiring and persistence behavior beyond unit/contract helpers.
- This keeps per-PR compliance evidence complete and ordered.

### Validation Output

- `CMS_TEST_PORT=59700 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all Stage 1 integration checks passed).

## Checklist Loop 26 (Per-PR)

### Selected Checklist Item

- Per-PR: `Smoke tests run and pass.`

### Why This Was the Next Best Step

- Contract and integration requirements are complete, so smoke verification is the final required runtime sanity gate in this 10-loop batch.
- Smoke checks verify startup, discovery, and write-auth behavior quickly on a clean runtime.
- Completing this item finalizes the requested 10 checklist completions.

### Validation Output

- `CMS_SMOKE_PORT=59710 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).
- `CMS_TEST_PORT=59540 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59550 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 18 (Phase 2)

### Selected Checklist Item

- Phase 2: `Update internal load/import flow so old and new paths can coexist during transition.`

### Why This Was the Next Best Step

- Wrapper delegation parity is covered, so the next ordered Phase 2 task is coexistence flow.
- Adding compatible symbol exports keeps transition imports flexible without changing config behavior.
- This minimizes migration risk while preserving current runtime entrypoints.

### Artifact

- Updated `config.kujo` to export both `load_config` and `load_config_impl` compatibility symbols.
- Updated `backend/config/config.kujo` to export both `load_config` and `load_config_impl` while delegating to the same backend implementation.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
- `CMS_TEST_PORT=59560 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59570 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 19 (Phase 2)

### Selected Checklist Item

- Phase 2: `Add tests or checks proving old commands still work.`

### Why This Was the Next Best Step

- Wrapper/load-flow scaffolding is complete, so startup compatibility evidence is the next ordered requirement.
- A dedicated startup compatibility check makes root entrypoint support explicit during transition.
- This reduces migration risk without altering endpoint contracts.

### Artifact

- Added `scripts/verify-compat-startup.sh` to verify root `main.kujo` startup and core endpoint availability (`/health`, `/v1`).
- Updated `README.md` testing section with the startup compatibility check command.

### Validation Output

- `CMS_COMPAT_PORT=59580 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/verify-compat-startup.sh` -> pass (`Compatibility startup checks passed.`).
- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
- `CMS_TEST_PORT=59590 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59610 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 20 (Phase 2 Gate)

### Selected Checklist Item

- Phase 2 gate: `Existing startup commands still work.`

### Why This Was the Next Best Step

- All Phase 2 scaffold tasks are now complete, so gate validation is required before progressing.
- Explicitly re-validating startup commands confirms transition scaffolding did not break boot behavior.
- This preserves migration sequencing discipline and reduces rollout risk.

### Validation Output

- `CMS_COMPAT_PORT=59620 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/verify-compat-startup.sh` -> pass (`Compatibility startup checks passed.`).
- `CMS_TEST_PORT=59630 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59640 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 21 (Phase 2 Gate)

### Selected Checklist Item

- Phase 2 gate: `No endpoint/status/response-shape regressions.`

### Why This Was the Next Best Step

- This is the final Phase 2 gate requirement and must be complete before Phase 3 items.
- Contract + integration + smoke validation confirms status and envelope stability during scaffolding.
- Closing this gate keeps migration progression compliant with ordered phase execution.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
- `CMS_TEST_PORT=59650 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59660 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> pass (smoke checks passed).

## Checklist Loop 22 (Per-PR)

### Selected Checklist Item

- Per-PR: `Scope limited to one domain.`

### Why This Was the Next Best Step

- After closing Phase 2 gate items, per-PR compliance evidence is required for migration readiness.
- Explicitly fixing scope to config-only work prevents cross-domain drift.
- This keeps wrapper compatibility changes isolated and reversible.

### Scope Statement

- Active migration domain: `config`.
- Included paths in this execution window: `config.kujo`, `backend_config.kujo`, `backend/config/config.kujo`, compatibility verification scripts/docs.
- Excluded domains: routing, resolver/query, auth/authz behavior, and content module logic.

### Validation Output

- `CMS_COMPAT_PORT=59670 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/verify-compat-startup.sh` -> pass (`Compatibility startup checks passed.`).
- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).

## Checklist Loop 23 (Per-PR)

### Selected Checklist Item

- Per-PR: `No API v1 breaking changes introduced.`

### Why This Was the Next Best Step

- Per-PR compatibility compliance must be explicit before concluding this migration execution set.
- Current changes are config-wrapper and validation-only, so route contracts should remain stable.
- Re-verification ensures no accidental path/status/envelope changes were introduced.

### Compatibility Statement

- No v1 endpoint path or method changes were made.
- No successful/failed response envelope shape changes were introduced.
- No write-route auth semantic changes were introduced.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
- `CMS_TEST_PORT=59680 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-stage1.sh` -> pass (all assertions passed).
- `CMS_SMOKE_PORT=59690 KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh` -> initial failure (`Address already in use`), re-run on `CMS_SMOKE_PORT=59691` -> pass (smoke checks passed).

## Checklist Loop 24 (Per-PR)

### Selected Checklist Item

- Per-PR: `Contract tests run and pass.`

### Why This Was the Next Best Step

- Per-PR test evidence must be explicit for release-gate completeness.
- Contract tests are the fastest guardrail for response-shape and helper invariants.
- Locking this item before integration/smoke keeps validation traceability clean.

### Validation Output

- `KUJO_BIN=/path/to/kujo/target/debug/kujo /path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo` -> pass (`9 passed`, `0 failed`).
