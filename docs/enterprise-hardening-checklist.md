# Enterprise Hardening Checklist

This document tracks obvious operational-readiness gaps identified during a senior engineering pass, and the concrete fixes applied.

## Scope

- Repository: Kujo CMS API foundation
- Goal: Raise operational confidence for release-bound backend work before dashboard/frontend implementation

## Findings And Fixes

- [x] Add a single-command release gate to remove manual test drift.
  - Problem: Full verification relied on manually chaining many scripts.
  - Fix: Added `scripts/run-release-gate.sh` to run contract, Stage 1/2/3 integrations, smoke, enterprise security, and optional perf in one deterministic flow.
  - Result: Repeatable gate for local and CI execution.

- [x] Add migration safety validation flow.
  - Problem: No dedicated operation to prove schema migration behavior is safe and idempotent across restarts.
  - Fix: Added `scripts/migration-safety.sh` to boot against a fresh DB, verify schema version, restart on the same DB, and re-verify.
  - Result: Explicit migration safety coverage for operational readiness.

- [x] Add database backup operation.
  - Problem: No first-class backup script for SQLite operational hygiene.
  - Fix: Added `scripts/backup-db.sh` with writer-process safety checks and backup manifest output.
  - Result: Repeatable timestamped backups under `results/backups/`.

- [x] Add database restore operation.
  - Problem: No controlled restore workflow with overwrite protections.
  - Fix: Added `scripts/restore-db.sh` with force flag support and active-writer safety checks.
  - Result: Safer, explicit restore path for disaster recovery testing.

- [x] Expand CI from Stage 1-only to full backend release gates.
  - Problem: CI verified contract + Stage 1 only, leaving Stage 2/3 and security checks outside default branch protection.
  - Fix: Updated `.github/workflows/ci.yml` to run `scripts/run-release-gate.sh` (perf disabled in CI for runtime budget).
  - Result: CI now enforces broad regression coverage before merge.

- [x] Update operator documentation to include enterprise operations.
  - Problem: Runbook guidance did not include release-gate and backup/restore/migration-safety operations.
  - Fix: Updated `README.md` and `HOWTO.md` with operations references and command usage.
  - Result: New team members can execute operator-facing backend operations without tribal knowledge.

## Validation Expectations

- Release gate command (local):
  - `bash scripts/run-release-gate.sh`
- Migration safety command:
  - `bash scripts/migration-safety.sh`
- Backup command:
  - `bash scripts/backup-db.sh`
- Restore command:
  - `bash scripts/restore-db.sh <backup_db_path> <target_db_path> --force`

## Webhook Signing And Verification Guidance

- Signing header: use `X-KujoCMS-Signature` with `sha256=<hex_hmac>` format.
- Signing input: raw request body bytes (no JSON reformatting).
- Shared secret source: environment secret managed outside source control.
- Verification steps:
  - Compute expected HMAC SHA-256 over raw body using shared secret.
  - Compare expected and received signature in constant time.
  - Reject missing/malformed signatures with `401` and structured error envelope.
- Rotation guidance:
  - Support overlap window for old/new secrets during coordinated rotation.
  - Record rotation events in audit logs with actor/time metadata.

## Webhook Retry And Dead-Letter Guidance

- Retry policy baseline:
  - Retry on network failures and `5xx` responses.
  - Do not retry `4xx` validation/auth failures.
  - Use bounded exponential backoff with jitter.
- Dead-letter queue policy:
  - Route exhausted deliveries to dead-letter storage with event metadata, response code, and error reason.
  - Keep dead-letter payload references immutable for later replay/audit workflows.
- Replay tooling expectations:
  - Replay command accepts event id(s), dry-run mode, and max-attempt override.
  - Replay operations emit audit entries and preserve original correlation ids where available.
  - Replay defaults to signed delivery using current active webhook secret policy.

## Completion Status

- [x] Checklist created
- [x] All listed fixes implemented
- [x] Regression gates executed successfully after implementation

## Release Checklist Addendum

Release sign-off should explicitly include:

- Migration impact summary (affected modules, paths, and consumer compatibility notes).
- Rollback validation summary (how to revert the release safely and what checks were rerun).
- Validation evidence references (contract, integration, smoke, and security checks).
- Operator-facing upgrade guidance updates in README/changelog.
