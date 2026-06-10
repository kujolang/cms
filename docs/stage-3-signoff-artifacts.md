# Stage 3 Sign-Off Artifacts

This document records the required sign-off evidence for Stage 3 production-readiness increments.

## Required Artifacts

- Validation output from `bash scripts/run-release-gate.sh`.
- Latest perf baseline report: `results/perf_baseline_latest.json`.
- Perf budget policy: `docs/perf-budget.json`.
- Enterprise security validation output from `scripts/integration-enterprise-security.sh`.
- Graceful restart validation output from `scripts/validate-graceful-restart.sh`.
- Operational load validation output from `scripts/ops-load-validation.sh`.

## Operator-Facing Release Guidance

- Upgrade path remains additive for API v1 compatibility.
- Rollback path is documented in `docs/stage-3-release-notes.md`.
- Backup/restore commands are documented in README and `docs/enterprise-hardening-checklist.md`.

## CI Enforcement

- `.github/workflows/ci.yml` executes `scripts/run-release-gate.sh`.
- CI release gate runs performance baseline and budget checks.
- CI failures block merge until production-readiness checks pass.
