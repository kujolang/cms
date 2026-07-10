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
- Content-model coverage for content types, taxonomies/terms, entries, media, menus, plugins, themes, roles, API tokens, tenants, and workspaces
- Public delivery and discovery routes for `/.well-known/security.txt`, `/.well-known/llms.txt`, `/robots.txt`, `/sitemap.xml`, `/sitemap-index.xml`, `/rss.xml`, `/health`, `/v1`, `/v1/contract`, and `/v1/openapi.json`
- Auth-gated write routes, webhook delivery, background jobs, migration safety, and backup/restore
- Release-gate automation covering contract, smoke, startup compatibility, integration, security, and optional performance checks

## Core Capabilities

- Content types, taxonomies/terms, entries, media, menus
- Plugin registry and webhook hooks
- Theme registry and activation controls
- Roles and API tokens with lifecycle controls
- Tenants and workspaces with isolation controls
- Public delivery and discovery routes (`/.well-known/security.txt`, `/.well-known/llms.txt`, `/robots.txt`, `/sitemap.xml`, `/sitemap-index.xml`, `/rss.xml`, `/health`, `/v1`, `/v1/contract`, `/v1/openapi.json`)
- Scheduler, revisions, rollback, and entry locking

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
- `CMS_RATE_LIMIT_MODE`
- `CMS_IDEMPOTENCY_ENABLED`
- `CMS_PLUGIN_HOOK_URL_ALLOWLIST`
- `CMS_PLUGIN_HOOK_URL_DENYLIST`
- `CMS_READINESS_CHECK_DB`
- `CMS_METRICS_ENABLED`

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

## Contribution

- Use `docs/contributor-one-loop-playbook.md` for contribution flow and validation expectations.
- Keep copyable examples concise and canonical; treat tests, integration scripts, and historical records as validation evidence before shortening them.
- Keep changes scoped, behavior-compatible, and release-gate validated.
