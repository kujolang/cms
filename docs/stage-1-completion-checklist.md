# Stage 1 Completion Checklist

This checklist defines what must be true before Stage 1 is considered complete for the CMS API foundation.

Status legend:
- [x] completed in current implementation
- [ ] not completed yet
- [~] deferred to Stage 2+

## Stage 1 Goals

- Deliver a stable headless CMS API foundation for content modeling, entry lifecycle, navigation, theming, and authorization.
- Provide machine-readable public delivery documents for downstream frontend and crawler interoperability.
- Ensure predictable validation and error behavior for relational write flows.
- Establish practical contract tests and explicit next-stage handoff.

## Completion Matrix

### API Foundation

- [x] Content type CRUD routes with validation and usage guards.
- [x] Taxonomy and term routes with parent-term validation and not-found handling.
- [x] Entry CRUD routes with status and slug validation.
- [x] Entry term assignment with strict term ID validation.
- [x] Slug-based entry lookup route for frontend/router consumption.
- [x] Media, menu, plugin, theme, and auth route groups available.
- [x] Paginated list responses across key route groups (content, media, menus, plugins, themes, auth).

### Headless Delivery Surface

- [x] Robots endpoint (`GET /robots.txt`).
- [x] Sitemap endpoint (`GET /sitemap.xml`).
- [x] RSS endpoint (`GET /rss.xml`).
- [x] LLM guidance endpoint (`GET /llms.txt` and `GET /.well-known/llms.txt`).

### Security and Integrity

- [x] Guarded write endpoints via bearer token auth.
- [x] Role/permission checks for token-based callers.
- [x] Request-level rate limiting.
- [x] Audit event persistence for mutating operations.
- [x] Existence checks added before destructive operations in key modules.
- [x] Theme activation hardened to avoid global deactivation on invalid ID.

### Testing and Verification

- [x] Contract tests for utility/auth/migration baselines.
- [x] Contract tests for delivery document generation helpers.
- [x] Full endpoint-level integration and negative-path matrix.
- [x] Automated CI pipeline for contract/integration verification.
- [x] API smoke script for startup and critical route checks.
- [x] Performance baseline script for delivery/list endpoints.
- [x] Stage 1 release notes and changelog entry.

## Stage 1 Freeze Status

All Stage 1 freeze tasks are now complete:

1. [x] End-to-end integration tests exercising real HTTP requests (`scripts/integration-stage1.sh`).
2. [x] CI workflow gates for contract + integration checks (`.github/workflows/ci.yml`).
3. [x] API smoke script for startup and critical route validation (`scripts/smoke-api.sh`).
4. [x] Performance baseline tooling for delivery/list endpoints (`scripts/perf-baseline.sh`).
5. [x] Stage 1 release notes and changelog artifacts.

## Deferred To Stage 2+

- [~] Rich SEO entity model and first-class schema markup generation.
- [~] Full-text search indexing and advanced query DSL.
- [~] Webhook delivery/retry subsystem and event queue.
- [~] Media upload pipeline with async processing jobs.
- [~] Versioned content workflow (revisions, preview states, scheduled publish orchestration).
- [~] Multi-site workspace tenancy.
- [~] GraphQL API surface and advanced filtering/sorting contracts.

## Kujo Runtime and Platform Dependencies

Known platform-level constraints are tracked in `docs/runtime-limitations.md`.
