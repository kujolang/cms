# Universal CMS Improvement Checklist

This document is the concise status summary for the universal hardening and extensibility backlog.

## Status

All scoped items in this checklist are complete.

## Tier Summary

| Tier | Focus | Status |
| --- | --- | --- |
| P0 | Security and correctness | Complete |
| P1 | Consistency and test expansion | Complete |
| P2 | Extensibility and developer experience | Complete |

## Completed Outcomes

### Security and Correctness (P0)

- Plugin hook secret leakage removed from API responses
- Lock expiry, ownership, and release semantics hardened
- Token expiration parsing and enforcement fixed
- Slug fallback validation tightened
- Mutation audit coverage expanded for key domains

### Consistency and Test Coverage (P1)

- Route handler execution paths standardized
- Delivery builders consolidated onto canonical rendering paths
- Tenancy scope helpers adopted across relevant routes
- DB access style normalized by layer
- Dead helpers removed or adopted
- Health/readiness shared logic consolidated
- Contract and negative-security test coverage expanded
- Audit consistency and pagination parity integration suites added

### Extensibility and Developer Experience (P2)

- Webhook outbox/retry/dead-letter/replay pipeline implemented
- Idempotency support expanded for mutation safety
- Plugin hook egress URL policy controls implemented
- Machine-readable API contract endpoint published
- Background job primitives and scripts added
- Root wrapper cleanup completed and backend import policy finalized
- Contributor one-loop playbook added

## Validation Baseline

Representative validation commands used to close this backlog:

```bash
KUJO_BIN=/path/to/kujo/target/debug/ruff test-run tests/cms_contract_tests.ruff
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/integration-stage1.sh
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/integration-enterprise-security.sh
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/run-release-gate.sh
```

## Historical Detail

Detailed per-loop execution notes are intentionally removed from this public-facing checklist for readability.
Use git history for full implementation chronology and command-by-command artifacts.
