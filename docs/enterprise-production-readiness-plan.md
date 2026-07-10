# Enterprise Production Readiness Plan

This plan tracks launch-readiness gates for CMS.

## Current Posture

- Code readiness: complete
- Validation readiness: complete for the 2026-07-10 local release gate with
  performance and performance-budget checks enabled (see
  [release-gate-evidence-2026-07-10.md](release-gate-evidence-2026-07-10.md))
- Governance readiness: one open pre-launch gate

## Launch Gates

### 1. Platform and Code Quality

- [x] Backend-first modular architecture completed
- [x] Contract, integration, smoke, and enterprise security suites passing
- [x] Migration safety, graceful restart, and operational load checks passing
- [x] Security hardening controls implemented and documented

### 2. Multi-Tenant and Operational Readiness

- [x] Tenant/workspace isolation controls implemented and tested
- [x] Webhook retry/dead-letter/replay workflow implemented
- [x] Background job processing and dead-letter replay workflow implemented
- [x] Audit and observability coverage validated

### 3. Release Governance

- [ ] Default branch protections enforce required release-readiness checks

Known blocker for gate 3:

- GitHub branch protections/rulesets return `HTTP 403` on current private repository plan.

### Ready-to-apply branch rule

An organization or repository administrator should apply this ruleset to the
default branch after confirming the repository plan supports it:

1. Target the `main` branch, including direct pushes and pull-request merges.
2. Require a pull request before merging, at least one approval, and dismissal
   of stale approvals after new commits.
3. Require status checks to pass and be up to date. Require the exact GitHub
   Actions job check names `stage1-gates` and `release-gates` from `CMS CI`.
4. Require conversation resolution and block force pushes and branch deletion.
5. Restrict bypass actors to the minimum repository-administrator set required
   for incident recovery; record every bypass in the release evidence note.

Validate the rule with one intentionally failing pull request and one passing
release-gate pull request before treating this governance item as closed.

Pre-launch completion steps:

1. Finalize repository posture (`private + eligible plan` or `public`).
2. Enable branch protection/rulesets for required checks.
3. Verify merge/push policy enforcement with failing and passing gate scenarios.

## Release Discipline Requirements

For each release-bound change:

- Scope is explicit and limited
- API behavior remains compatible unless versioned
- Validation output is included in PR/release notes
- Rollback steps are documented for risky changes

## Definition of Ready

CMS is launch-ready when:

1. All code and operational gates remain green.
2. Branch-protection governance gate is enforced.
3. Release artifacts include operator-facing upgrade and rollback guidance.
