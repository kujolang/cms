# Changelog

## Unreleased

- Pin the production-stable Ability 1.0.1 runtime with validated replay and
  terminal idempotency hardening.
- Replace boolean Ability confirmation as a security boundary with durable,
  short-lived, request-bound, one-time approvals; bind approvals to canonical
  invocation digests and tenant-aware principals; and migrate approval storage
  in schema version 13.

## 1.1.0 - 2026-08-30

- Add framework-neutral identity providers, revocable CMS sessions, role-derived permissions, and administration capabilities.
- Add granular SEO inventory, focused and bulk SEO updates, configurable social-sharing networks and accounts, and matching terminal workflows.
- Add the Abilities API, connector controls, plugin-contributed abilities and connectors, MCP-ready descriptors, and WebMCP discovery and browser tools.
- Add portable theme and plugin contracts, branded administration navigation, verified ZIP upload and installation, package export, and extension lifecycle controls.
- Add atomic content composition, taxonomy batching, managed and externally verified media ingestion, and optimistic concurrency checks.
- Add dependency-free JavaScript and PHP clients plus framework-adapter guidance for portable administration and frontend implementations.
- Harden authentication, authorization, production ingress, idempotency, webhook egress, background work, migration safety, tenancy, and unpublished-content boundaries.
- Restrict anonymous entry reads to published content and require authentication for revision history.
- Reject malformed tenant/workspace keys, scope workspace-key uniqueness per tenant, and migrate existing databases to schema version 7.
- Reject invalid media sizes and return `not_found` when deleting a missing media record.
- Prevent taxonomy-term and menu-item parent cycles, and preserve the active theme when an active-theme create fails.
- Make safe database helpers convert SQLite exceptions into structured error results.
- Harden list-query parsing so malformed pagination and sort input falls back to bounded defaults instead of risking direct cast failures.
- Remove stale tracked backend placeholder files after the backend-first source layout became canonical.
- Expand `.env.example` and README production-readiness notes to better reflect the operational surface and remaining governance gate.
- Add the v0.2 -> v0.3 enterprise enhancement checklist for the next improvement loop.

## 1.0.0

- TWEAK: Tighten canonical CMS docs and runtime banner output patterns for agent/human readability without changing API behavior.
- Promote CMS to the 1.0.0 release with aligned service, seed, and contract version defaults.
- Keep the Kujo runtime and release-gate surfaces consistent with the release version.
