# Kujo CMS

[![Version](https://img.shields.io/badge/version-1.2.0-black)](https://github.com/kujolang/cms/releases/tag/v1.2.0)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Built with Kujo](https://img.shields.io/badge/built%20with-Kujo-white.svg)](https://github.com/kujolang/kujo)

Kujo CMS is a content backend for websites, administration tools, integrations, and agents. It manages content and permissions through one API. You choose the frontend.

[CMS Example](https://github.com/kujolang/cms-example) supplies the public frontend and CMS Studio. This repository owns the backend, database migrations, clients, and API contracts.

**Upgrading?** Read the [1.2.0 release notes](docs/releases/1.2.0.md), especially the request-bound Ability approvals and storage compatibility notes.

## Start the backend

Install Kujo and Kennel, then:

```bash
git clone --branch v1.2.0 https://github.com/kujolang/cms.git
cd cms
kennel install
cp .env.example .env
kujo run --interpreter backend/runtime/main.kujo
```

The API listens at `http://127.0.0.1:4200`. Its entrypoint is `backend/runtime/main.kujo`; there is no separate CMS executable. To add CMS to a Kujo project, use `kennel add cms`.

Set a unique `CMS_API_TOKEN` for initial provisioning. There is no usable default credential. After provisioning, disable bootstrap access and use scoped database-backed tokens. Keep credentials on the server.

The package declares Kujo 1.2.0 or newer; CI exercises Kujo 1.2.2. The public sites use Kujo 1.8.0 for their builds. The pinned Ability dependency is installed by Kennel.

## What it provides

- Content types, entries, taxonomies, terms, media, and menus.
- Drafts, scheduled publication, revisions, rollback, entry locks, and atomic content-and-taxonomy updates.
- Users, roles, registration policies, identity links, and revocable sessions with shared permission checks.
- SEO inventory, focused and bulk updates, social-sharing settings, sitemaps, RSS, and discovery routes.
- Portable themes and plugins with versioned manifests, bounded ZIP installation, SHA-256 receipts, and administration navigation. Installation does not execute package code.
- Abilities with validated input/output contracts, scoped execution, one-time approvals, idempotency receipts, plugin contributions, and MCP-ready descriptors.
- Public, read-only WebMCP tools for site information, search, content lists, and exact published records.
- Webhook and job queues, audit records, health/readiness/metrics endpoints, migrations, and backup/restore scripts.
- Dependency-free [JavaScript and PHP clients](clients/) for frontend and server adapters.

The [Field Notes theme](https://github.com/kujolang/cms-field-notes-theme) and [contact form plugin](https://github.com/kujolang/cms-contact-form) show how to build portable extensions.

## API and agent access

Start with `/v1` for capabilities and `/v1/openapi.json` for the route contract. Anonymous content reads expose published records only. Drafts, revisions, administration, and mutations require the appropriate authority.

Administrative permissions are separate: `admin.auth`, `admin.users`, `admin.settings`, and `admin.plugins`. `cms.write` alone grants none of them. Password adapters verify credentials on the server and exchange the verified user for a CMS session. Frontend adapters own their cookies; CMS owns session expiry, revocation, and permissions.

The [Abilities API](docs/abilities.md) exposes six core operations and validated plugin contributions. Mutations require a short-lived approval bound to the exact invocation and principal. `confirmed: true` is accepted only as compatibility input and grants no authority. The CMS Ability pack is versioned separately from the application.

[WebMCP](docs/webmcp.md) is enabled by default. `/.well-known/kujo-webmcp.json` supplies the manifest and script tag; `/assets/js/kujo-webmcp.js` registers four same-origin, read-only browser tools. Headless frontends must expose those routes on the same origin. Drafts, private metadata, and authenticated mutations stay outside this surface. Bounded scans report truncation; `CMS_WEBMCP_ENABLED=false` disables it.

Connector endpoints and credentials remain server-side. Browser responses and package manifests never receive connector secrets. Authenticated MCP deployments still need transport authentication, TLS, ingress limits, and connector health checks.

## Configuration and operations

[`.env.example`](.env.example) lists the environment settings. The main controls are `CMS_API_HOST`, `CMS_API_PORT`, `CMS_ENV`, `CMS_DB_PATH`, `CMS_SITE_URL`, `CMS_CORS_ORIGIN`, and the token and storage settings. [The operator guide](HOWTO.md) covers setup and deployment.

Production startup requires `CMS_TRUSTED_INGRESS_LIMITS=true`. Configure the ingress to enforce the CMS body ceiling, connection limits, and request deadlines before forwarding. Use `CMS_RATE_LIMIT_MODE=sqlite` for durable local limits or `external` for shared ingress limits. CMS uses the direct socket peer rather than trusting forwarding headers. Kujo's `KUJO_HTTP_SERVER_READ_TIMEOUT_MS` defaults to 10000 ms and is clamped to 100–300000 ms.

Each deployment needs rotated secrets, an identity adapter, explicit CORS, durable storage, backups, monitoring, recovery tests, and repository governance. The backend's release gate does not certify that infrastructure. See the [production-readiness plan](docs/enterprise-production-readiness-plan.md) for the recorded branch-protection limitation.

Terminal helpers use the same APIs:

```bash
bash scripts/cms-content.sh help
bash scripts/cms-seo.sh help
bash scripts/cms-extensions.sh help
bash scripts/cms-ai.sh help
```

Run queue workers and recovery commands as needed:

```bash
bash scripts/process-webhook-outbox.sh
bash scripts/process-background-jobs.sh
bash scripts/replay-webhook-dead-letters.sh
bash scripts/replay-background-job-dead-letters.sh
```

Workers use renewable leases and atomic claims. They bound child processes and clean them up on termination. Webhooks remain at-least-once delivery: receivers must handle duplicate delivery after failures. See the release notes and [hardening audit](docs/audits/repository-hardening-round-2.md) for the verified failure boundaries.

## Verify a change

```bash
kujo test-run tests/cms_contract_tests.kujo
CMS_GATE_PERF_RUNS=10 bash scripts/run-release-gate.sh
```

The full gate covers contracts, JavaScript/PHP clients, startup compatibility, API integrations, security, concurrency, workers, recovery, and performance budgets. Set `KUJO_BIN` to test a specific runtime. `CMS_GATE_RUN_PERF=false` skips performance checks for a focused development run.

Keep generated databases, logs, and benchmark output in ignored `results/`. The [audit reports](docs/audits/repository-hardening.md) record the hardening changes and fixture measurements.

## Code and documentation

| Area | Location |
| --- | --- |
| Runtime and route registration | `backend/runtime/main.kujo` |
| Environment settings | `backend/config/config.kujo` |
| HTTP, persistence, migrations | `backend/core/` |
| Authentication and authorization | `backend/modules/` |
| Feature handlers | `backend/routes/` |
| Public schemas and examples | `schemas/`, `examples/extensions/`, `ability-pack.json` |
| Regression tests and operations | `tests/`, `scripts/` |

Use dotted backend imports and keep frontend concerns in the adapter repository. [AGENTS.md](AGENTS.md) provides a short code map and verification guide.

- [Framework adapters](docs/framework-adapters.md)
- [Extension contracts](docs/extensions.md)
- [Ability contracts](docs/abilities.md)
- [WebMCP](docs/webmcp.md)
- [Changelog](CHANGELOG.md)
- [Public CMS documentation](https://docs.kujolang.ai/showcases/cms/)

## License

MIT. See [LICENSE](LICENSE).
