# Stage 2 + Stage 3 Execution Roadmap

This roadmap defines ordered implementation rounds from the current Stage 1 baseline through Stage 3 completion.

Status legend:
- [x] complete
- [ ] not started
- [~] in progress

## Round 1: Discovery and Query Foundations (Stage 2)

- [x] Introduce first-class entry SEO metadata model (title/description/canonical/social fields).
- [x] Add structured SEO response endpoint (JSON-LD projection from stored metadata).
- [x] Add deterministic sorting/filtering support for entry list APIs.
- [x] Add Stage 2 integration checks covering SEO and query behavior.

## Round 2: Delivery Expansion (Stage 2)

- [x] Segmented sitemap indexes (by content type and date buckets).
- [x] Feed variants (content-type and taxonomy scoped feeds).
- [x] Cursor pagination contract for high-volume lists.
- [x] Sparse fieldsets/include-related response options.

## Round 3: Editorial Governance (Stage 2 -> Stage 3 bridge)

- [x] Revisions schema + revision APIs.
- [x] Rollback workflow and integration tests.
- [x] Scheduled publish/unpublish orchestration.
- [x] Content locking and conflict responses.

## Round 4: Integrations and Security Hardening (Stage 3)

- [x] Typed webhook event model and signing.
- [x] Retry + dead-letter handling for webhook delivery.
- [x] API token lifecycle upgrades (rotation, one-time secret reveal semantics).
- [x] Expanded audit model for sensitive auth/integration operations.

## Round 5: Enterprise Operations and Completion (Stage 3)

- [x] Migration CLI and safety validation flows.
- [x] Backup/restore scripts and operational runbook.
- [x] Request IDs, structured logs, and latency/error metrics hooks.
- [x] CI expansion to integration depth, smoke, and perf budget checks.
- [x] Stage 3 release notes and final completion sign-off.

### Stage 3 Completion Validation Snapshot (2026-05-26)

- PASS: `CMS_TEST_PORT=53114 bash scripts/integration-stage2-round3-webhooks.sh`
- PASS: `CMS_TEST_PORT=53115 bash scripts/integration-stage1.sh`
- PASS: `CMS_TEST_PORT=53116 bash scripts/integration-audit-consistency.sh`
- PASS: `CMS_MIGRATION_TEST_PORT=53117 bash scripts/migration-safety.sh`
- PASS: `CMS_OPS_LOAD_PERF_PORT=53118 CMS_OPS_LOAD_MIGRATION_PORT=53119 CMS_OPS_LOAD_PORT=53120 bash scripts/ops-load-validation.sh`

## Non-Negotiable Guardrails

1. Preserve backward compatibility for existing Stage 1 clients.
2. Keep API responses deterministic and contract-tested.
3. Keep release notes/changelog updated every round.
4. Validate every round with contract tests plus integration checks.
