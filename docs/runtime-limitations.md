# Kujo Runtime Limitations Impacting CMS Evolution

This document tracks runtime or platform constraints that may need Kujo-level improvements for full enterprise CMS parity.

## Current Constraints

1. Interpreter route closures can fail to resolve some helper symbols
- During Stage 1 integration hardening, multiple route closures returned runtime 500s due to undefined helper symbols.
- Failures were observed with module-local handlers and selected imported helper wrappers.
- Practical workaround in this codebase: inline critical route logic in closures using runtime-native primitives (`db_query`, `db_execute`, `json_response`) where needed.
- A runtime-level fix for closure symbol resolution would reduce boilerplate and prevent hidden production failures.

2. HTTP requests are buffered before application body limits
- Kujo rejects bodies above 8 MiB before route dispatch and applies a bounded socket read deadline, but CMS may configure `CMS_MAX_BODY_BYTES` below that runtime ceiling after the body has been buffered.
- Production startup therefore still requires `CMS_TRUSTED_INGRESS_LIMITS=true`; the trusted ingress must enforce the smaller CMS body-size contract before Kujo.

3. Socket peer identity is available in current Kujo runtimes
- CMS prefers the socket-derived `peer_ip` field for rate limiting and audit identity, with compatibility fallbacks for older runtimes.
- Production may use durable local `CMS_RATE_LIMIT_MODE=sqlite` or a shared `external` limiter. Forwarding headers remain untrusted and do not override socket identity.

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
