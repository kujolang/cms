# Backend Architecture Notes

This document defines the stable architecture contract for CMS internals.

## Objectives

- Keep API v1 behavior stable while internal modules evolve
- Preserve clear ownership boundaries for runtime, core, route, and security logic
- Keep downstream adoption simple through backend-first module layout

## Canonical Module Layout

| Area | Responsibility | Paths |
| --- | --- | --- |
| Runtime | Bootstrap, context wiring, route registration | `backend/runtime/main.kujo` |
| Config | Environment and policy defaults | `backend/config/config.kujo` |
| Core | Transport, persistence, migration, utility primitives | `backend/core/*.kujo` |
| Modules | Reusable domain/security logic | `backend/modules/*.kujo` |
| Routes | API endpoint composition and request handling | `backend/routes/*.kujo` |

## Import and Execution Policy

- Use dotted backend imports only (for example, `from backend.core.http import fail`).
- Do not use root-level compatibility wrapper modules.
- Start the service with `backend/runtime/main.kujo`.

## Runtime Composition Rules

1. Runtime module owns process startup and shared context wiring.
2. Route modules own endpoint behavior and envelope compatibility.
3. Core modules stay dependency-light and reusable.
4. Module helpers encapsulate auth and cross-domain security logic.

## API Compatibility Invariants

The following must remain stable unless explicitly versioned:

- Endpoint paths and HTTP methods
- Success/error envelope structure
- Auth semantics for write routes
- Pagination and filtering response metadata semantics

## Multi-Tenant Isolation Rules

- Tenant and workspace context must be resolved before domain mutation.
- Cross-tenant access attempts must be denied before business logic executes.
- Audit events for tenant/workspace mutations must be preserved.

## Operational Invariants

- Health/readiness endpoints must remain available and deterministic.
- Structured logs and request identifiers must remain consistent.
- Migration safety and restart behavior must remain release-gate validated.

## Rollback Guidance

For high-risk internal refactors:

1. Revert only the affected module/domain scope.
2. Preserve API response shape and status semantics.
3. Re-run contract tests, integration suites, and smoke checks.
4. Update release notes with rollback impact.

## Current State

- Root compatibility wrapper `.kujo` files have been removed.
- Backend module imports and runtime entrypoint migration are complete.
- Architecture is aligned to a backend-first, enterprise-ready layout.
