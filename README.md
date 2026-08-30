# CMS

[![Version](https://img.shields.io/badge/version-1.0.0-black)](https://github.com/kujolang/cms)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![built with Kujo](https://img.shields.io/badge/built%20with-Kujo-white.svg)](https://github.com/kujolang/kujo)

CMS is a server-first showcase/proof app that demonstrates local Kujo application patterns for content models, delivery routes, auth boundaries, and contract-tested APIs.

It boots from `backend/runtime/main.kujo`; there is no standalone CLI wrapper to validate.

## Production Readiness Posture

CMS is production-capable as a Kujo showcase backend when deployed with rotated secrets, explicit CORS policy, durable storage/backup practices, and the documented release gate. It is not presented as universally enterprise-complete out of the box: default branch protection enforcement remains the known pre-launch governance gate, and teams should still run their own infrastructure, compliance, and threat-model review before public production use.

The current codebase is intentionally backend-first. Active source lives under `backend/config`, `backend/core`, `backend/modules`, `backend/routes`, and `backend/runtime`; empty migration-era placeholder folders are not part of the current architecture.

## Why CMS

- Server-first architecture with clear module ownership under `backend/`
- Canonical runtime entrypoint at `backend/runtime/main.kujo`
- Content-model coverage for content types, taxonomies/terms, entries, media, menus, plugins, themes, users, roles, API tokens, tenants, and workspaces
- Public delivery and discovery routes for `/.well-known/security.txt`, `/.well-known/llms.txt`, `/robots.txt`, `/sitemap.xml`, `/sitemap-index.xml`, `/rss.xml`, `/health`, `/v1`, `/v1/contract`, and `/v1/openapi.json`
- WebMCP enabled by default with a discovery manifest, same-origin browser adapter, published-content index, and four read-only content tools
- Auth-gated write routes, webhook delivery, background jobs, migration safety, and backup/restore
- Release-gate automation covering contract, smoke, startup compatibility, integration, security, and optional performance checks

## Core Capabilities

- Content types, taxonomies/terms, entries, media, menus
- Plugin registry and webhook hooks
- Theme registry and activation controls
- Portable, versioned theme and plugin manifests with validation, installation, export, discovery, settings schemas, compatibility declarations, and distribution metadata
- Official dependency-free JavaScript and PHP clients with identity, content, SEO/social, extension, media, ability, connector, sharing, and administration-navigation helpers
- Durable users and profiles with roles, account states, social links, derived credentials, and configurable open/approval/closed registration
- Framework-neutral identity links and revocable CMS sessions with core-derived permissions and administration capabilities
- Roles and API tokens with lifecycle controls
- Tenants and workspaces with isolation controls
- Public delivery and discovery routes (`/.well-known/security.txt`, `/.well-known/llms.txt`, `/robots.txt`, `/sitemap.xml`, `/sitemap-index.xml`, `/rss.xml`, `/health`, `/v1`, `/v1/contract`, `/v1/openapi.json`)
- Scheduler, revisions, rollback, and entry locking
- A namespaced Abilities API with JSON Schema contracts, permission-scoped execution, confirmation-gated mutations, audit receipts, MCP-ready tool descriptors, and a secret-safe Kujo connector registry
- Built-in WebMCP discovery and browser tools for site information, search, content listing, and exact published-record retrieval

## Showcase Positioning

- CMS proves Kujo can support a practical server-first application surface.
- CRUD API Showcase demonstrates a smaller API pattern.
- SSG demonstrates static publishing.
- Lens and ShipCheck help review and gate the result.

## Architecture

Canonical runtime and module layout:

Verified startup path:

`backend/runtime/main.kujo`

| Area | Path |
| --- | --- |
| Runtime bootstrap | `backend/runtime/main.kujo` |
| Config | `backend/config/config.kujo` |
| Core transport/persistence | `backend/core/http.kujo`, `backend/core/database.kujo`, `backend/core/migrations.kujo`, `backend/core/utils.kujo` |
| Auth/Authz modules | `backend/modules/auth.kujo`, `backend/modules/authz.kujo` |
| Domain routes | `backend/routes/*.kujo` |

Import policy:

- Use dotted backend imports for local modules (for example, `from backend.core.http import fail`).
- Do not reintroduce root-level compatibility wrapper modules.
- Start the API from the verified runtime entrypoint; there is no standalone CLI wrapper.

## Security and Operations Baseline

Security controls:

- Bearer token enforcement for write routes
- Published-only anonymous entry reads; draft/scheduled/archived details and revision history require authenticated access
- Bootstrap token hardening (production-safe defaults, entropy policy)
- Strict JSON mutation validation and body-size limits
- Rate limiting (`memory`, `sqlite`, `external`, `off` modes)
- Idempotency support for mutation retry safety
- Plugin hook URL policy controls (allowlist/denylist, scheme restrictions)
- Structured audit logging for sensitive mutations

Operations controls:

- Health, readiness, and metrics endpoints
- Webhook outbox retries + dead-letter replay
- Background job processing + dead-letter replay
- Migration safety and graceful restart validation
- Backup and restore scripts

## Verified Launch Status

Code and validation status:

- Contract tests, smoke API checks, compatibility startup, and the release gate
  all pass in the 2026-07-10 local receipt, including enabled performance and
  performance-budget checks; see
  [`docs/release-gate-evidence-2026-07-10.md`](docs/release-gate-evidence-2026-07-10.md).
- Contract coverage includes safe pagination parsing for malformed list query input across list endpoint helpers.
- The documented release gate enables performance checks by default.
- Repository code and docs are aligned to the backend-first architecture.

Open governance item before public launch:

- Branch protection/ruleset enforcement for required release-gate checks is pending repository plan/visibility constraints (documented in `docs/enterprise-production-readiness-plan.md`).

## Quick Start

1. Configure environment:

```bash
cp .env.example .env
```

2. Start the API:

```bash
cd /path/to/cms
/path/to/kujo/target/debug/kujo run --interpreter backend/runtime/main.kujo
```

Default bind: `http://127.0.0.1:4200`
Use `CMS_API_HOST` if you need an explicit non-default bind host; the reviewed showcase path defaults to `127.0.0.1`.

The API boots directly from `backend/runtime/main.kujo`; there is no standalone CLI wrapper.

Recommended env overrides:

- `CMS_API_HOST`
- `CMS_ENV`
- `CMS_API_PORT`
- `CMS_API_TOKEN`
- `CMS_DB_PATH`
- `CMS_SITE_URL`
- `CMS_CORS_ORIGIN`
- `CMS_TRUSTED_INGRESS_LIMITS`
- `CMS_RATE_LIMIT_MODE`
- `CMS_IDEMPOTENCY_ENABLED`
- `CMS_PLUGIN_HOOK_URL_ALLOWLIST`
- `CMS_PLUGIN_HOOK_URL_DENYLIST`
- `CMS_READINESS_CHECK_DB`
- `CMS_METRICS_ENABLED`
- `CMS_AI_SDK_ENDPOINT`, `CMS_AGENTS_SDK_ENDPOINT`, `CMS_MCP_ENDPOINT`, `CMS_DISPATCH_ENDPOINT`, `CMS_RAG_ENDPOINT`, `CMS_REDACT_ENDPOINT`, `CMS_WATCHDOG_ENDPOINT`, `CMS_CONTENTGRAPH_ENDPOINT`, `CMS_SEARCHBRIDGE_ENDPOINT`, `CMS_BLUEPENCIL_ENDPOINT`, `CMS_PRESSWIRE_ENDPOINT`, `CMS_READERSIGNAL_ENDPOINT`
- `CMS_WEBMCP_ENABLED`, `CMS_WEBMCP_MAX_SCAN_RECORDS`, `CMS_WEBMCP_INDEX_PAGE_SIZE_MAX`, `CMS_WEBMCP_SUMMARY_MAX_CHARS`

Bootstrap authentication has no usable default credential. Generate a unique bootstrap token for initial provisioning, then disable it and use scoped database-backed API tokens. Administrative routes require dedicated capabilities: `admin.auth`, `admin.users`, `admin.settings`, and `admin.plugins`; `cms.write` alone does not grant administrative access.

Security upgrade note: schema migration v9 deactivates all database-backed API tokens created by earlier schema versions because legacy environment-bootstrap credentials were not distinguishable from ordinary tokens after edits. Reissue the required scoped tokens after upgrading; the current environment bootstrap token remains available only when explicitly enabled and is never persisted.

Production startup also requires `CMS_TRUSTED_INGRESS_LIMITS=true` and `CMS_RATE_LIMIT_MODE=external`. The trusted ingress must enforce request-body size, connection/read timeouts, and per-client rate limits before traffic reaches Kujo; the current interpreter buffers request bodies and does not expose the socket peer address to application routes.

User APIs:

- `GET|POST /v1/users` lists or creates user records.
- `GET|PATCH /v1/users/:id` reads or updates profiles, roles, and account status.
- `GET /v1/users/:id/credentials` is a bearer-protected server-to-server credential lookup; password hashes are never included in normal user responses.
- `GET|PATCH /v1/settings/registration` reads or changes the `open`, `approval`, or `closed` signup policy and its default role.
- `GET|PATCH /v1/settings/social-sharing` reads or changes the allowed sharing networks, per-network account attribution, and the content types that display them. This setting is bearer-protected and audited like other administration settings.
- `POST /v1/auth/sessions` lets a trusted password or identity adapter exchange a verified active user for a bounded, revocable CMS session. The raw token is returned once and is sent to CMS as `X-CMS-Session`; frontend cookies remain the framework adapter's responsibility.
- `POST /v1/auth/providers/exchange` links a trusted external identity to a CMS user, optionally provisions the user under the configured registration policy, and returns the same core session contract.
- `GET /v1/auth/me` returns the session user, role permissions, and effective administration capabilities. `DELETE /v1/auth/session` immediately revokes that session.
- `GET /v1/seo/entries` returns a filterable, paginated SEO inventory with scores, issue codes, metadata lengths, taxonomy counts, and content signals.
- `PATCH /v1/entries/:id/seo` performs a focused SEO update without replacing other entry metadata; `POST /v1/seo/entries/bulk` applies the same supported fields to as many as 200 selected entries.
- `POST /v1/entries` accepts optional `term_ids` so creation and taxonomy assignment commit together. `PATCH /v1/entries/:id/compose` snapshots the current revision, applies validated entry fields, replaces the selected terms, and commits the workflow atomically. `expected_updated_at` provides optimistic concurrency protection.
- `POST /v1/taxonomies/:id/terms/bulk` creates or updates as many as 100 terms in one transaction.
- `POST /v1/media/ingest` verifies the signature of staged PNG, JPEG, GIF, WebP, or PDF media and copies it into managed filesystem storage; `/v1/media/upload` accepts the same bounded workflow as base64 JSON for administration adapters. Filesystem objects are readable from `GET /v1/media/files/:object_key` as verified base64 data so any frontend adapter can stream them with native caching headers. `POST /v1/media/register-external` records objects verified by a trusted S3, GCS, Azure, R2, or custom adapter when `CMS_MEDIA_STORAGE_ADAPTER=external`.

Agent and terminal workflows can use `bash scripts/cms-seo.sh help` for report, single-entry update, bulk update, and social-sharing settings commands.
Content adapters and terminal agents can use `bash scripts/cms-content.sh help` for atomic composition, taxonomy batching, and both media storage workflows.

Portable extension workflows:

- `GET /v1/extensions/contracts` describes the `kujo.theme/v1` and `kujo.plugin/v1` package contracts; `GET /v1/extensions/catalog` discovers installed themes and active plugins.
- Theme and plugin manifests can be validated, installed or updated, activated, and exported through versioned API routes without exposing package settings or secrets. Verified ZIP receipts bind an install to its filename, SHA-256 digest, manifest path, file count, and bounded expanded size.
- Theme packages describe framework-neutral frontend entrypoints, templates, assets, settings, content types, menu locations, branded administration artwork, and ordered sidebar contributions. Plugin packages declare connector, webhook, browser, or hybrid runtimes with explicit capabilities, events, administration links, abilities, and connector descriptors.
- `POST /v1/extensions/packages/ingest` verifies a ZIP staged in the configured server inbox; `/v1/extensions/packages/upload` provides the same authoritative path for bounded base64 administration uploads. Both use hardened archive extraction, enforce compressed/expanded size and file-count limits, validate one canonical manifest, record a SHA-256 receipt, and register the extracted package in managed storage. Package code is not executed during installation.
- `bash scripts/cms-extensions.sh help` provides API-equivalent terminal commands. Canonical manifests live under `examples/extensions/` and the authoring contract is documented in [`docs/extensions.md`](docs/extensions.md).
- Field Notes has its own forkable home in the independent `cms-field-notes-theme` repository and is bundled as the showcase default. The independent `cms-contact-form` repository demonstrates a hybrid plugin with a browser component, durable submission API, moderation CLI, discoverable abilities, signed notification delivery, and production safety controls.
- CMS Studio in `cms-example` provides separate **Themes** and **Plugins** screens with guarded ZIP upload, install-and-activate controls, installed-package status, source links, and activation controls.

AI and agent interoperability:

- `GET /v1/abilities` and `GET /v1/abilities/categories` provide authenticated discovery; `GET|PATCH /v1/abilities/:namespace/:ability` reads or administratively enables/disables one contract.
- `POST /v1/abilities/:namespace/:ability/run` executes the registered handler through its declared permission. Mutating abilities require `confirmed: true` inside the input and write an audit event.
- `GET /v1/ai/connectors` reports Kujo integration availability and configuration status without returning endpoint values or secrets; `PATCH /v1/ai/connectors/:key` activates or deactivates a configured connector.
- Active plugins can contribute secret-free ability and connector descriptors to those same discovery APIs. CMS can enable or disable each contribution, execute abilities through the plugin's configured service runtime with the same permission and confirmation boundary, probe connector health, and publish enabled abilities as MCP-ready tools. Runtime bearer credentials stay in server environment variables and never enter package manifests or browser responses.
- `GET /v1/ai/mcp/tools` translates the same registry into MCP-ready tool descriptors, keeping REST, CLI, and agent surfaces on one source of truth.
- `bash scripts/cms-ai.sh help` exposes status, connector, discovery, enable/disable, inspection, execution, and MCP descriptor commands for terminal agents. Disabled abilities cannot execute and are omitted from MCP descriptors.

Connector environment variables identify trusted server-side adapters only. Provider credentials remain in the connector or gateway process; they are not stored in CMS settings or sent to the Studio browser. Production MCP deployments still need authenticated transport, TLS, ingress rate limits, and connector-specific health checks.

WebMCP is baked into every CMS instance and enabled by default. `GET /.well-known/kujo-webmcp.json` publishes the machine-readable manifest and copyable script tag; `/assets/js/kujo-webmcp.js` registers `get_site_info`, `search_site`, `list_content`, and `get_content` through `document.modelContext.registerTool()`. The adapter calls only same-origin, read-only routes under `/v1/webmcp`, and `/.well-known/kujo-site-index.json` provides a paginated live index. Headless frontends include the manifest's script tag in their page shell; reverse proxies should serve the CMS routes on the same origin.

Only published records are exposed. Returned content is plain text, size-bounded, and stripped of arbitrary entry metadata. Set `meta.webmcp_exclude` (or `meta.webmcp.exclude`) to remove a record entirely, or `meta.search_exclude` (or `meta.webmcp.search_exclude`) to keep exact/list access while excluding search. Large repositories are capped by `CMS_WEBMCP_MAX_SCAN_RECORDS` and report `truncated: true` instead of silently implying a complete result. Set `CMS_WEBMCP_ENABLED=false` for an explicit opt-out.

Extend the public tool set at `backend/routes/webmcp.kujo:webmcp_tool_registry` and add a matching bounded, published-content handler. Keep authenticated or mutating agent operations in the Abilities API. Terminal agents can inspect the surface with `bash scripts/cms-ai.sh webmcp`, `webmcp-tools`, and `webmcp-index` without a CMS token. See [`docs/webmcp.md`](docs/webmcp.md) for the full extension and deployment contract.

The backend stores portable PBKDF2 credential material supplied by a trusted password adapter. Password verification remains in that adapter because the current Kujo runtime does not provide a password-hardening primitive; after verification, the adapter exchanges the user for a core-managed CMS session. This keeps the CMS API token and credential records out of browsers while ensuring that session expiry, revocation, role permissions, and effective capabilities have one framework-neutral source of truth.

## Validation and Release Gate

Contract tests:

```bash
cd /path/to/cms
/path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo
```

Full release gate:

```bash
cd /path/to/cms
CMS_GATE_RUN_PERF=false KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/run-release-gate.sh
```

Useful targeted checks:

```bash
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-enterprise-security.sh
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/integration-multitenant.sh
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/smoke-api.sh
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/verify-compat-startup.sh
```

## Operational Commands

Webhook pipeline:

```bash
bash scripts/process-webhook-outbox.sh
bash scripts/replay-webhook-dead-letters.sh
```

Webhook and background-job processors use renewable claim leases so overlapping workers cannot normally execute the same row. Webhook claim duration is automatically kept longer than the configured curl deadline. Receivers must still deduplicate by `X-CMS-Webhook-Id`, because a process can crash after a remote endpoint accepts a request but before local delivery state commits.

Background jobs:

```bash
bash scripts/process-background-jobs.sh
bash scripts/replay-background-job-dead-letters.sh
```

Data safety:

```bash
bash scripts/backup-db.sh
bash scripts/restore-db.sh
bash scripts/migration-safety.sh
```

## Documentation

Start with the docs index:

- `docs/README.md`

Key docs:

- `docs/backend-architecture-notes.md`
- `docs/enterprise-production-readiness-plan.md`
- `docs/enterprise-hardening-checklist.md`
- `docs/error-codes.md`
- `docs/high-sla-failure-drills.md`
- `docs/runtime-limitations.md`
- `docs/webmcp.md`
- `docs/extensions.md`
- `docs/framework-adapters.md`

## Contribution

- Use `docs/contributor-one-loop-playbook.md` for contribution flow and validation expectations.
- Keep copyable examples concise and canonical; treat tests, integration scripts, and historical records as validation evidence before shortening them.
- Keep changes scoped, behavior-compatible, and release-gate validated.
