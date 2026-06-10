# Stage 2 Plan (Adjusted After Stage 1 Hardening)

This Stage 2 plan reflects the upgraded Stage 1 baseline, including delivery endpoints, slug-based lookup, and stronger validation behavior.

## Stage 2 Objective

Build enterprise-grade content platform capabilities on top of the stable Stage 1 headless API contract, without breaking existing clients.

## Current Progress

- Round 1 is complete: entry SEO metadata is persisted and projected via `GET /v1/entries/:id/seo`.
- Round 1 is complete: entry list APIs now support deterministic sort/filter controls (`sort_by`, `sort_dir`, `author_id`, `content_type`, `status`).
- Round 1 is complete: Stage 2 integration coverage is in place via `scripts/integration-stage2-round1.sh`.
- Round 2 item 1 is complete: segmented sitemap indexes are available by content type and date bucket.
- Round 2 item 1 is complete: delivery integration coverage is in place via `scripts/integration-stage2-round2-sitemaps.sh`.
- Round 2 item 2 is complete: feed variants are available via content-type and taxonomy-scoped RSS routes.
- Round 2 item 2 is complete: feed variant integration coverage is in place via `scripts/integration-stage2-round2-feeds.sh`.
- Round 2 item 3 is complete: cursor pagination mode is available for high-volume `GET /v1/entries` workflows.
- Round 2 item 3 is complete: cursor integration coverage is in place via `scripts/integration-stage2-round2-cursor.sh`.
- Round 2 item 4 is complete: sparse fieldsets and include-related terms are available on `GET /v1/entries`.
- Round 2 item 4 is complete: projection integration coverage is in place via `scripts/integration-stage2-round2-projection.sh`.

## Stage 2 Priority Tracks

## 1) SEO and Discovery System

- Introduce first-class SEO metadata schema for entries and content types.
- Add canonical URL, title/description overrides, and social card fields.
- Generate structured schema payloads (JSON-LD) from stored metadata.
- Expand sitemap support into segmented indexes (content types, tags, dates).
- Add feed variants (Atom, per-taxonomy feeds, per-content-type feeds).

## 2) Content Query and Delivery Expansion

- Add robust sorting options for all list endpoints.
- Add richer filters (date ranges, taxonomy filters, author filters, status sets).
- Add stable cursor pagination mode for high-volume lists.
- Add optional sparse fieldsets and include-related support.

## 3) Editorial Workflow and Governance

- Add entry revisions and rollback support.
- Add scheduled publish/unpublish orchestration.
- Add content locking and conflict detection.
- Add approval workflows and role-based moderation actions.

## 4) Extensibility and Integrations

- Add webhook event model with signing, retries, dead-letter policy.
- Expand plugin hook contracts with typed payload schemas.
- Add API key lifecycle improvements (rotation, one-time secrets, last-used telemetry).

## 5) Platform Operations

- Expand integration coverage depth (multi-step stateful workflows and rollback scenarios).
- Add migration CLI flows for schema/state operations.
- Add observability hooks (request IDs, latency metrics, structured logs).
- Add backup/restore utilities for SQLite and future storage backends.

## Stage 2 Exit Criteria

1. Stage 1 routes remain backward compatible.
2. SEO and discovery model is complete and documented.
3. Query/filter/sort behavior is deterministic and integration-tested.
4. Workflow features have migration-safe schema support.
5. Plugin/webhook integrations are resilient and verifiable.
6. CI enforces contract + integration coverage for all critical modules.
