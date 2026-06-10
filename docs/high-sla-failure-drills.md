# High-SLA Failure Drills And Recovery Procedures

## Objectives

- Validate restart behavior under controlled termination.
- Validate migration safety and DB recoverability under operational load.
- Preserve API v1 compatibility while running reliability drills.

## Drill 1: Graceful Shutdown And Restart

Command:

```bash
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/validate-graceful-restart.sh
```

Expected outcomes:

- Server exits cleanly on `SIGTERM`.
- Server restarts on the same DB without schema regression.
- Health/readiness endpoints return success after restart.

## Drill 2: Operational Load + Recovery

Command:

```bash
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/ops-load-validation.sh
```

Expected outcomes:

- Perf baseline collection succeeds.
- Migration safety check succeeds.
- Backup is created after load generation.
- Restore succeeds to a target DB path.

## Drill 3: Enterprise Security Abuse Paths

Command:

```bash
KUJO_BIN=/path/to/kujo/target/debug/ruff bash scripts/integration-enterprise-security.sh
```

Expected outcomes:

- Malformed payload and malformed token requests are rejected.
- Deactivated token replay attempts are rejected.
- Bootstrap policy controls behave as configured.

## Incident Recovery Checklist

1. Stop write traffic and capture a backup snapshot.
2. Run migration safety validation.
3. Restore from latest valid backup if integrity checks fail.
4. Re-run smoke and release-gate checks before reopening traffic.
