# Changelog

## Enterprise Readiness Loops (2026-05-25)

### FEATURE

- Loop P2-04: added machine-readable API contract discovery endpoints `GET /v1/contract` and `GET /v1/openapi.json` with OpenAPI-like metadata and route/auth/query hints for v1 resources.
- Loop P2-05: standardized callback-safe non-entry list query behavior (`limit`/`offset` bounds plus allowlisted `sort_by`/`sort_dir`) across media, menus, themes, taxonomies, taxonomy terms, tenants, and workspaces, with consistent list metadata in responses.
- Loop P2-06: added generic background job primitives (`background_jobs` + `background_job_dead_letters`), worker/enqueue/replay scripts, media maintenance task script, queue observability counts in health/readiness payloads, and Stage 2 Round 3 background-jobs integration coverage wired into the release gate.

### FIX

- Loop P2-03: hardened plugin hook URL policy enforcement in callback-safe route paths to reject unsafe schemes and internal/private hosts by default while honoring configured allowlist/denylist controls.

### TWEAK

- Loop P2-07: finalized wrapper deprecation milestone sequencing and published explicit minimum root runtime footprint targets in backend architecture notes.
- Loop P2-08: added a contributor one-loop execution playbook with scoped implementation workflow, validation expectations, and done criteria.

### COMPATIBILITY

- Advanced schema migration target to `v6_background_jobs` while preserving existing startup/runtime compatibility paths.

## Enterprise Readiness Loops (2026-05-20)

### FIX

- Loop 51: completed Phase 0 gate item "Contract + integration + smoke checks pass after migration" after fixing Stage 2 Round 2 delivery route handlers that were returning default `OK` bodies on sitemap/feed variant endpoints under interpreter mode.

### TWEAK

- Loop 64: clarified that branch protection enforcement is an intentional last-mile pre-launch review step while the repository remains private, with explicit verification guidance in readiness docs and README.
- Loop 52: completed Phase 2 item "Tenant/workspace data model and isolation boundaries defined" by publishing the canonical tenant/workspace ownership and isolation rules in backend architecture notes.

### FEATURE

- Loop 63: completed Definition-of-Done validation/documentation gate by revalidating contract + Stage 1 + multi-tenant operations after backend-owned wrapper migration and documenting the remaining branch-protection platform blocker (`HTTP 403` on private free-tier repo).
- Loop 62: completed Phase 0 wrapper-hardening gate by converting root runtime modules into backend-target compatibility symlinks and updating backend config parity for tenant quota controls so contract, Stage 1, and multi-tenant integrations all pass with backend-owned logic.
- Loop 61: stabilized auth token lifecycle route handlers for Kujo interpreter mode by using runtime-safe JSON/DB primitives in `POST/PATCH /v1/auth/tokens` so one-time reveal and rotation flows execute reliably under Stage 1 integration.
- Loop 60: completed Phase 1 item "API token lifecycle upgrades (rotation, one-time reveal semantics, last-used metadata)" by adding one-time `token_secret` reveal on token create/rotate flows and Stage 1 integration checks validating rotate behavior and `last_used_at` persistence.
- Loop 59: completed Phase 2 gate item "Cross-tenant access attempts are denied and tested" by extending `scripts/integration-multitenant.sh` with scoped-token cross-tenant denial assertions for tenant mutation and workspace creation paths.
- Loop 58: completed Phase 2 item "Tenant-scoped auth enforcement (token scopes and role boundaries per tenant)" by enforcing `tenant:<id>` permission scope checks across tenant/workspace list and mutation endpoints.
- Loop 57: completed Phase 2 item "Tenant-level quotas/limits and guardrail policies enforced" by adding configurable tenant/workspace quota caps (`CMS_TENANT_MAX_COUNT`, `CMS_TENANT_WORKSPACE_MAX_COUNT`) and blocking workspace creation for disabled/archived tenants.
- Loop 56: completed Phase 2 item "Multi-tenant integration and isolation tests added" by adding `scripts/integration-multitenant.sh` and wiring it into `scripts/run-release-gate.sh`.
- Loop 55: completed Phase 2 gate item "Tenant lifecycle operations are observable and auditable" by persisting tenancy lifecycle mutation audit events in `audit_log` for tenant create/update/disable/archive and workspace create operations.
- Loop 54: completed Phase 2 item "Tenant lifecycle APIs (create, update, disable, archive) implemented" by adding tenancy endpoints (`GET/POST /v1/tenants`, `POST /v1/tenants/update`, `POST /v1/tenants/disable`, `POST /v1/tenants/archive`) and workspace management endpoints (`GET/POST /v1/workspaces`).
- Loop 53: completed Phase 1 item "Typed webhook event model with schema validation" by adding typed webhook event schema helpers and payload validation primitives in the plugins domain.

## Enterprise Readiness Loops (2026-05-19, Round 2)

### TWEAK

- Loops 26-50: completed 25 additional enterprise-readiness checklist items across Phase 1 security hardening, Phase 3 reliability/observability, Phase 4 CI/performance discipline, Per-PR checks, and Definition-of-Done enforcement.
- Added request ID response headers, structured request/audit logging, and metrics counters with dimensions exposed via `GET /metrics`.
- Added configurable readiness/liveness coverage via `GET /ready`, `GET /live`, and `CMS_READINESS_CHECK_DB`.
- Added graceful shutdown/restart validation automation (`scripts/validate-graceful-restart.sh`).
- Added operational load validation automation (`scripts/ops-load-validation.sh`) combining perf baseline, migration safety, and backup/restore checks.
- Expanded enterprise security integration checks for malformed payloads and replay/abuse-path scenarios.
- Added performance budget policy (`docs/perf-budget.json`) and enforcement script (`scripts/perf-budget-check.sh`), integrated into release gate and CI.
- Published Stage 3 release/sign-off artifacts and high-SLA failure drill documentation.

## Enterprise Readiness Loops (2026-05-19)

### TWEAK

- Loop 25: completed Phase 4 item "Release checklist includes migration impact and rollback validation" with release checklist addendum in enterprise hardening docs.
- Loop 24: completed Phase 1 gate item "Operator runbook covers webhook and token-lifecycle operations" with explicit README runbook guidance.
- Loop 23: completed Phase 1 item "Webhook retry policy with dead-letter handling and replay tooling" with retry/dead-letter/replay operator guidance.
- Loop 22: completed Phase 1 item "Webhook signing and signature verification documentation" with operator-facing signature format and verification guidance.
- Loop 21: completed Phase 0 item "Wrapper removal criteria defined and gated by one stable transition cycle" with explicit gate criteria in backend architecture notes.
- Loop 20: completed Phase 0 item "Consumer migration guide includes copy-only-backend usage path" by adding explicit backend-only sync steps in README.
- Loop 19: completed Phase 0 item "Wrapper deprecation timeline documented in docs and changelog" with explicit transition-cycle timeline in backend architecture notes.
- Loop 18: completed Phase 0 item "`delivery.ruff` functionality moved to `backend/routes/delivery.ruff`" by publishing backend routes target copy.
- Loop 17: completed Phase 0 item "`themes.ruff` functionality moved to `backend/routes/themes.ruff`" by publishing backend routes target copy.
- Loop 16: completed Phase 0 item "`plugins.ruff` functionality moved to `backend/routes/plugins.ruff`" by publishing backend routes target copy.
- Loop 15: completed Phase 0 item "`menus.ruff` functionality moved to `backend/routes/menus.ruff`" by publishing backend routes target copy.
- Loop 14: completed Phase 0 item "`media.ruff` functionality moved to `backend/routes/media.ruff`" by publishing backend routes target copy.
- Loop 13: completed Phase 0 item "`entries.ruff` functionality moved to `backend/routes/entries.ruff`" by publishing backend routes target copy.
- Loop 12: completed Phase 0 item "`taxonomies.ruff` functionality moved to `backend/routes/taxonomies.ruff`" by publishing backend routes target copy.
- Loop 11: completed Phase 0 item "`content_types.ruff` functionality moved to `backend/routes/content_types.ruff`" by publishing backend routes target copy.
- Loop 10: completed Phase 0 item "`authz.ruff` functionality moved to `backend/modules/authz.ruff`" by publishing backend module target copy.
- Loop 9: completed Phase 0 item "`auth.ruff` functionality moved to `backend/modules/auth.ruff`" by publishing backend module target copy.
- Loop 8: completed Phase 0 item "`utils.ruff` functionality moved to `backend/core/utils.ruff`" by publishing backend core target copy.
- Loop 7: completed Phase 0 item "`migrations.ruff` functionality moved to `backend/core/migrations.ruff`" by publishing backend core target copy.
- Loop 6: completed Phase 0 item "`database.ruff` functionality moved to `backend/core/database.ruff`" by publishing backend core target copy.
- Loop 5: completed Phase 0 item "`http.ruff` functionality moved to `backend/core/http.ruff`" by publishing backend core target copy.
- Loop 4: completed Phase 0 item "`config.ruff` functionality moved to `backend/config/config.ruff`" after validating root delegation and backend target implementation.
- Loop 3: completed Phase 0 item "`main.ruff` functionality moved to `backend/runtime/main.ruff`" by publishing backend runtime target copy.
- Loop 2: completed Phase 0 item "Confirm backend folder ownership boundaries" with explicit ownership matrix in backend architecture notes.
- Loop 1: completed Phase 0 item "Confirm and publish final old-to-new file mapping table for all root runtime modules" with final runtime mapping published in README and backend architecture notes.

## Backend Restructure Execution (2026-05-19)

### TWEAK

- Checklist loops 28-53: completed all remaining backend-restructure checklist items across Phase 3 migration closure, Phase 4 documentation/guidance updates, Phase 5 deprecation policy/gates, and Per-PR finalization checks.
- Config-domain migration step: documented backend target-path mapping (`config.ruff` -> `backend/config/config.ruff`) with runtime bridge guidance for current Kujo import limitations.
- Checklist loop 27: completed Phase 3 item "Choose one migration domain only (routing OR config OR resolver OR auth) for the current PR".
- Checklist loop 26: completed Per-PR checklist item "Smoke tests run and pass".
- Checklist loop 25: completed Per-PR checklist item "Integration tests run and pass".
- Checklist loop 24: completed Per-PR checklist item "Contract tests run and pass".
- Checklist loop 23: completed Per-PR checklist item "No API v1 breaking changes introduced".
- Checklist loop 22: completed Per-PR checklist item "Scope limited to one domain".
- Checklist loop 21: completed Phase 2 gate item "No endpoint/status/response-shape regressions".
- Checklist loop 20: completed Phase 2 gate item "Existing startup commands still work".
- Checklist loop 19: completed Phase 2 item "Add tests or checks proving old commands still work".
- Checklist loop 18: completed Phase 2 item "Update internal load/import flow so old and new paths can coexist during transition".
- Checklist loop 17: completed Phase 2 item "Ensure wrappers delegate behavior without changing output shape".
- Checklist loop 1: completed Phase 0 item "Confirm current branch and ensure working tree is clean".
- Checklist loop 2: completed Phase 0 item "Capture baseline test command outputs for comparison" and added baseline PR notes.
- Checklist loop 3: completed Phase 0 item "Confirm no planned API v1 breaking change in current work scope".
- Checklist loop 4: completed Phase 0 item "List all root Kujo runtime files that may be migrated".
- Checklist loop 5: completed Phase 0 item "Create a short migration scope note for this execution cycle".
- Checklist loop 6: completed Phase 0 gate item "Scope for this cycle is explicit and limited".
- Checklist loop 7: completed Phase 0 gate item "Baseline captured and attached to PR notes".
- Checklist loop 8: completed Phase 1 item "Define backend module boundaries (runtime, routing, config, resolver, auth)".
- Checklist loop 9: completed Phase 1 item "Produce file mapping table: old path -> target path".
- Checklist loop 10: completed Phase 1 item "Add or update architecture notes in docs".
- Checklist loop 11: completed Phase 1 item "Identify critical API v1 contract surfaces used by frontend/admin".
- Checklist loop 12: completed Phase 1 item "Add or update contract tests for critical v1 surfaces".
- Checklist loop 13: completed Phase 1 gate item "Existing tests pass unchanged".
- Checklist loop 14: completed Phase 1 gate item "Contract coverage exists for critical v1 surfaces".
- Checklist loop 15: completed Phase 2 item "Create backend folder skeleton".
- Checklist loop 16: completed Phase 2 item "Add root compatibility wrappers for entrypoints that will move".

## Stage 3 Round 3

### FEATURE

- Added scheduler orchestration endpoint: `POST /v1/entries/scheduler/run` for due publish and due unpublish transitions.
- Added support for `unpublish_at` entry scheduling metadata on create/update/list flows.
- Added Stage 3 Round 3 scheduler integration coverage script: `scripts/integration-stage3-round3-scheduler.sh`.
- Added content lock lifecycle endpoints: `GET /v1/entry-locks/state`, `POST /v1/entry-locks/acquire`, and `POST /v1/entry-locks/release`.
- Added restore conflict guard to block `POST /v1/entries/:id/revisions/:revision_id/restore` while an entry lock is active.
- Added Stage 3 Round 3 locking integration coverage script: `scripts/integration-stage3-round3-locking.sh`.

### COMPATIBILITY

- Added forward migration step (`v4_entries_unpublish_at`) and advanced schema target to `4` while preserving Stage 1/2/3 compatibility.
- Added forward migration step (`v5_entry_locks`) and advanced schema target to `5` while preserving Stage 1/2/3 compatibility.

### TWEAK

- Removed stale mirrored source trees (`core/` and `modules/`) to keep a single canonical root-level module layout.
- Updated README architecture wording to reflect the canonical root-level runtime source model.

## Stage 3 Round 1

### FEATURE

- Added immutable revision persistence schema (`entry_revisions`) with migration support (schema target `3`).
- Added revision APIs: `GET /v1/entries/:id/revisions` and `POST /v1/entries/:id/revisions`.
- Added Stage 3 Round 1 revision integration coverage script: `scripts/integration-stage3-round1-revisions.sh`.

### COMPATIBILITY

- Added forward migration step (`v3_entry_revisions`) while preserving Stage 1/2 compatibility.

## Stage 3 Round 2

### FEATURE

- Added rollback endpoint: `POST /v1/entries/:id/revisions/:revision_id/restore`.
- Rollback now snapshots pre-restore entry state as an immutable backup revision before applying the restore.
- Added Stage 3 Round 2 rollback integration coverage script: `scripts/integration-stage3-round2-rollback.sh`.

## Stage 2 Round 2

### FEATURE

- Added segmented sitemap delivery endpoints: `GET /sitemap-index.xml`, `GET /sitemaps/content-types.xml`, `GET /sitemaps/content-type/:content_type_key`, `GET /sitemaps/dates.xml`, and `GET /sitemaps/date/:bucket`.
- Enhanced base sitemap generation to include published entry URLs with `lastmod` values.
- Added Stage 2 Round 2 integration coverage script: `scripts/integration-stage2-round2-sitemaps.sh`.
- Added feed variant endpoints: `GET /rss/content-type/:content_type_key` and `GET /rss/taxonomy/:taxonomy_key/:term_slug`.
- Added Stage 2 Round 2 feed integration coverage script: `scripts/integration-stage2-round2-feeds.sh`.
- Added cursor pagination contract for `GET /v1/entries` using `pagination=cursor` and `cursor` tokens (with `sort_by=id`).
- Added Stage 2 Round 2 cursor integration coverage script: `scripts/integration-stage2-round2-cursor.sh`.
- Added sparse fieldset projection and include-related response options (`fields`, `include=terms`) for `GET /v1/entries`.
- Added Stage 2 Round 2 projection integration coverage script: `scripts/integration-stage2-round2-projection.sh`.

### FIX

- Normalized date-bucket derivation for sitemap segmentation to support both ISO datetime text and epoch-millisecond timestamps.
- Updated entry create behavior to preserve explicit `published_at` values when provided.

## Stage 2 Round 1

### FEATURE

- Added entry SEO metadata support on create flows and normalized SEO projection endpoint: `GET /v1/entries/:id/seo`.
- Added deterministic filter/sort support for entries list queries (`content_type`, `status`, `author_id`, `sort_by`, `sort_dir`).
- Added Stage 2 Round 1 integration coverage script: `scripts/integration-stage2-round1.sh`.

### TWEAK

- Exposed entry SEO endpoint and capability metadata in API discovery/options responses.

## Stage 1 Freeze

### FEATURE

- Added public delivery/discovery endpoints: `robots.txt`, `sitemap.xml`, `rss.xml`, `llms.txt`, and `/.well-known/llms.txt`.
- Added slug-based entry lookup endpoint: `GET /v1/entries/by-slug/:content_type/:slug`.
- Added Stage 1 integration matrix script: `scripts/integration-stage1.sh`.
- Added API smoke verification script: `scripts/smoke-api.sh`.
- Added performance baseline script with JSON reporting: `scripts/perf-baseline.sh`.
- Added CI workflow gates for contract + integration verification: `.github/workflows/ci.yml`.

### FIX

- Hardened entry term assignment validation with explicit `invalid_term_ids` error details.
- Added strict existence checks for plugin hook creation, theme activation, and token deactivation not-found paths.
- Improved taxonomy term integrity checks (parent validation and child-term delete blocking).
- Stabilized critical route handlers for interpreter-mode runtime constraints in Stage 1 verification flows.

### TWEAK

- Expanded list endpoint pagination behavior and response metadata across key domains.
- Updated project documentation for Stage 1 completion, runtime limitations, and Stage 2 handoff.

### PERFORMANCE

- Introduced repeatable latency baseline tooling for delivery and list endpoints (`results/perf_baseline_latest.json`).
