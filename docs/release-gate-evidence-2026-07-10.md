# CMS Local Release-Gate Evidence — 2026-07-10

## Scope

This receipt records local, reproducible validation only. It does not claim
hosted deployment certification or default-branch protection enforcement.

## Release gate

Command:

```bash
CMS_GATE_RUN_PERF=true CMS_GATE_PERF_RUNS=5 CMS_GATE_RUN_PERF_BUDGET=true \
KUJO_BIN=kujo \
bash scripts/run-release-gate.sh
```

Result: exit `0` on 2026-07-10. The gate completed contract tests, all staged
integration suites, smoke/security/operational checks, the five-run performance
baseline, and the configured performance-budget check.

## Backup and restore drill

The release gate runs the repository's operational-load validation, which
creates a disposable SQLite snapshot, invokes `scripts/backup-db.sh`, restores
it to a separate disposable path with `scripts/restore-db.sh --force`, and
validates the restored data. To repeat the focused drill:

```bash
CMS_OPS_LOAD_PERF_PORT=49440 CMS_OPS_LOAD_MIGRATION_PORT=49441 \
CMS_OPS_LOAD_PORT=49442 KUJO_BIN=kujo \
bash scripts/ops-load-validation.sh
```

Expected result: `Backup completed`, `Restore completed`, and exit `0`. The
script writes only ignored paths under `results/`.

## Remaining external blocker

Branch protections cannot be enabled locally. Apply the exact `CMS CI` ruleset
instructions in [enterprise-production-readiness-plan.md](enterprise-production-readiness-plan.md),
then capture a failing and passing protected-branch result before graduation.
