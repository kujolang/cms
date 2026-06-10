# Stage 3 Plan (Enterprise Completion Track)

Stage 3 finalizes CMS as an enterprise-grade, API-first platform by delivering governance, reliability, and secure extensibility on top of Stage 2 feature completeness.

## Stage 3 Objective

Ship production-grade operational guarantees and workflow governance while preserving backward compatibility for Stage 1/Stage 2 clients.

## Current Progress

- Round 3 item 1 is complete: immutable entry revision snapshots are persisted via `entry_revisions` schema support.
- Round 3 item 1 is complete: revision list/create APIs are available at `GET /v1/entries/:id/revisions` and `POST /v1/entries/:id/revisions`.
- Round 3 item 1 is complete: integration coverage is in place via `scripts/integration-stage3-round1-revisions.sh`.
- Round 3 item 2 is complete: rollback workflow is available at `POST /v1/entries/:id/revisions/:revision_id/restore`.
- Round 3 item 2 is complete: rollback integration coverage is in place via `scripts/integration-stage3-round2-rollback.sh`.
- Round 3 item 3 is complete: scheduler orchestration endpoint is available at `POST /v1/entries/scheduler/run`.
- Round 3 item 3 is complete: scheduled unpublish metadata is persisted via `entries.unpublish_at` with schema target `4`.
- Round 3 item 3 is complete: scheduler integration coverage is in place via `scripts/integration-stage3-round3-scheduler.sh`.
- Round 3 item 4 is complete: entry lock lifecycle endpoints are available at `GET /v1/entry-locks/state`, `POST /v1/entry-locks/acquire`, and `POST /v1/entry-locks/release`.
- Round 3 item 4 is complete: restore conflict enforcement blocks `POST /v1/entries/:id/revisions/:revision_id/restore` while locks are active.
- Round 3 item 4 is complete: lock persistence is migrated via `v5_entry_locks` with schema target `5`.
- Round 3 item 4 is complete: integration coverage is in place via `scripts/integration-stage3-round3-locking.sh`.

## Stage 3 Priority Tracks

## 1) Workflow Governance

- Revisions with rollback and immutable revision history.
- Editorial state machine with approval gates.
- Scheduled publish/unpublish orchestration.
- Content locking and conflict handling for concurrent editors.

## 2) Secure Integrations

- Typed webhook event contracts per resource domain.
- Retry policy with dead-letter handling and observability.
- API token rotation and one-time reveal semantics.
- Token scope hardening and audit trail expansion.

## 3) Reliability and Operations

- Request correlation IDs and structured access/error logs.
- Backup/restore workflows and disaster recovery runbooks.
- Migration CLI flows with validation and rollback checks.
- Performance budgets and SLO-aligned alert thresholds.

## 4) Multi-Tenant and Access Boundaries

- Workspace/site tenancy boundaries.
- Tenant-scoped auth and data partitioning.
- Tenant lifecycle APIs and isolation validation tests.

## 5) Compliance and Release Discipline

- Expanded CI/CD gates (integration, smoke, perf budgets, migration checks).
- Security test matrix and abuse-path validation.
- Release checklist automation and signed release artifacts.

## Stage 3 Exit Criteria

1. Workflow features are deterministic, migration-safe, and integration-tested.
2. Integration events are authenticated, retried, and observable.
3. Operational tooling (backup/restore/migrations) is documented and verified.
4. Tenant boundaries are enforced by tests and runtime checks.
5. CI gates prevent regression across reliability, performance, and security baselines.
6. Stage 1 and Stage 2 API compatibility remains intact.
