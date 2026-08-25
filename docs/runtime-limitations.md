# Kujo Runtime Limitations Impacting CMS Evolution

This document tracks runtime or platform constraints that may need Kujo-level improvements for full enterprise CMS parity.

## Current Constraints

1. Interpreter route closures can fail to resolve some helper symbols
- During Stage 1 integration hardening, multiple route closures returned runtime 500s due to undefined helper symbols.
- Failures were observed with module-local handlers and selected imported helper wrappers.
- Practical workaround in this codebase: inline critical route logic in closures using runtime-native primitives (`db_query`, `db_execute`, `json_response`) where needed.
- A runtime-level fix for closure symbol resolution would reduce boilerplate and prevent hidden production failures.

2. HTTP requests are buffered before application body limits
- The current Kujo HTTP server reads the full request body before CMS route code can enforce `CMS_MAX_BODY_BYTES`.
- Production startup therefore requires `CMS_TRUSTED_INGRESS_LIMITS=true`; the trusted ingress must enforce body-size and connection/read-time limits before Kujo.

3. Socket peer address is not exposed to CMS routes
- The current request dictionary does not provide a reliable remote socket address, so application-local anonymous rate limiting collapses callers into one bucket.
- Production startup requires `CMS_RATE_LIMIT_MODE=external`; enforce per-client limits at the trusted ingress without trusting client-supplied forwarding headers unless the ingress overwrites them.

4. Background processing is shell-operated
- The CMS includes leased SQLite workers for jobs and webhook retries, but they are operator-run processes rather than a first-class Kujo worker runtime.
- Webhook delivery remains at-least-once across a crash after remote acceptance; receivers must deduplicate the stable webhook event ID.

5. Request testing ergonomics are limited at contract-test level
- Current tests cover utility and deterministic builders.
- End-to-end HTTP integration testing tooling should be standardized for Kujo projects.

6. Delivery formatting utilities are string-based
- XML generation uses manual escaping and string assembly.
- A dedicated XML/Atom helper package would improve safety and maintainability.

7. Upload pipeline primitives are not yet modeled
- Stage 1 media route is metadata-oriented and does not handle multipart uploads.
- Runtime/framework-level upload stream support may be needed for large media workloads.

8. Nested module imports are not currently parser-compatible in `from` statements
- `from backend/config/config import ...` and `from backend.config.config import ...` both fail parser validation.
- This limits direct runtime activation of nested backend folder modules through `from` imports.
- Practical workaround in this codebase: keep temporary root-level bridge modules while maintaining backend target-path files for migration mapping.

## Suggested Kujo-Level Opportunities

1. Add reference middleware patterns for auth/rate-limit/trace ID.
2. Provide a shared cache/kv abstraction for distributed state.
3. Add first-class HTTP integration test harness helpers.
4. Add standard library helpers for feed/sitemap-safe XML generation.
5. Add optional background worker/runtime patterns for delayed or retryable tasks.
6. Add parser/runtime support for nested module imports to unblock direct backend folder module loading.
