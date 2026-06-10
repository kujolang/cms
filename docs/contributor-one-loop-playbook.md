# Contributor One-Loop Playbook

This playbook describes the smallest safe execution cycle for CMS changes.

Use one loop per checklist item so behavior changes stay reviewable and easy to roll back.

## 1. Pick One Item

- Start from `docs/universal-cms-improvement-checklist.md`.
- Select the first unchecked item in the active priority tier unless maintainers direct otherwise.
- Define scope in one sentence before editing code.

## 2. Implement Only That Scope

- Touch only files needed for the selected item.
- Preserve API v1 response shapes unless the item explicitly allows a contract change.
- Prefer additive behavior over breaking changes.

## 3. Run Smallest Relevant Validation First

Use the narrowest command that proves your change works:

- Security change: `KUJO_BIN=/path/to/kujo bash scripts/integration-enterprise-security.sh`
- API behavior change: `CMS_TEST_PORT=4290 KUJO_BIN=/path/to/kujo bash scripts/integration-stage1.sh`
- Broad regression check: `CMS_SMOKE_PORT=4291 KUJO_BIN=/path/to/kujo bash scripts/smoke-api.sh`
- Contract sanity: `KUJO_BIN=/path/to/kujo test-run tests/cms_contract_tests.kujo`

## 4. Expand Validation To Gate Level

Before marking done, run full release-level verification for the branch:

- `KUJO_BIN=/path/to/kujo bash scripts/run-release-gate.sh`

If full gate is too expensive for an intermediate loop, document the deferred command explicitly in the handoff note.

## 5. Update Docs And Checklist

For completed checklist items:

- Mark `[x]` in `docs/universal-cms-improvement-checklist.md`.
- Add completion note fields:
  - Completed on
  - Commit
  - Summary
  - Validation run commands
- Update `README.md` if behavior or endpoints changed.
- Add a categorized entry in `CHANGELOG.md` (`FEATURE`, `FIX`, `TWEAK`, etc.).

## 6. Done Criteria

A loop is done only when all are true:

- Scope stayed limited to one checklist item.
- Relevant tests/scripts passed.
- Checklist and docs are updated.
- No unresolved runtime errors were introduced.

## 7. Handoff Template

Use this in PR notes or agent handoff:

- Item: `<checklist id and title>`
- Scope: `<one sentence>`
- Files changed: `<short list>`
- Validation: `<commands + pass/fail>`
- Risks/follow-ups: `<if any>`
