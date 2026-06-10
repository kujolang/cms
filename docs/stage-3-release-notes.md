# Stage 3 Release Notes

Date: 2026-05-19

## Summary

Stage 3 reliability and operations hardening now includes:

- Request ID response headers and structured guard/audit logs.
- Readiness (`/ready`) and liveness (`/live`) endpoints with configurable DB readiness checks.
- Metrics summary endpoint (`/metrics`) with latency and auth/rate-limit counters.
- Graceful shutdown/restart validation automation.
- Operational load validation covering perf baseline, migration safety, backup, and restore workflows.
- Performance budget enforcement wired into release-gate and CI execution.

## Upgrade Impact

- No API v1 breaking path/method/shape changes.
- Added endpoints are additive only:
  - `GET /live`
  - `GET /ready`
  - `GET /metrics`
- Existing `GET /health` remains available and now mirrors readiness behavior.

## Rollback Guidance

1. Revert the release commit(s) that introduced Stage 3 reliability hardening.
2. Re-run `bash scripts/run-release-gate.sh` to validate rollback state.
3. If required, restore the previous DB snapshot using:
   - `bash scripts/restore-db.sh <backup_db_path> <target_db_path> --force`
4. Confirm post-rollback health with:
   - `bash scripts/smoke-api.sh`

## Validation Evidence

- Contract tests: `tests/cms_contract_tests.ruff`
- Integration checks: Stage 1/2/3 + enterprise security scripts
- Reliability checks: `scripts/validate-graceful-restart.sh`, `scripts/ops-load-validation.sh`
- Perf budget checks: `scripts/perf-baseline.sh` + `scripts/perf-budget-check.sh`
