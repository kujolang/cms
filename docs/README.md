# Documentation Index

This index organizes CMS documentation by audience and workflow.

## Start Here

- `../README.md`: project overview, quick start, validation, and operations at a glance
- `enterprise-production-readiness-plan.md`: current verified launch posture, release-gate status, and remaining governance gate

## Architecture and Design

- `backend-architecture-notes.md`: canonical module boundaries, import policy, and contract invariants

## Security and Reliability

- `enterprise-hardening-checklist.md`: operational hardening implementation and validation expectations
- `error-codes.md`: stable error envelope and common API error code mappings
- `high-sla-failure-drills.md`: operational drill scenarios and expected recovery behavior
- `runtime-limitations.md`: runtime caveats and safe coding constraints

## Release and Validation

- `stage-1-completion-checklist.md`
- `stage-1-release-notes.md`
- `stage-2-plan.md`
- `stage-2-3-execution-roadmap.md`
- `stage-3-plan.md`
- `stage-3-release-notes.md`
- `stage-3-signoff-artifacts.md`

## Contributor Workflow

- `contributor-one-loop-playbook.md`: contribution protocol, required validations, and done criteria
- `next-session-enterprise-enhancement-checklist.md`: next implementation loop queue

## Agent-Facing Example Policy

- Canonical copyable examples live in `../README.md`, `../HOWTO.md`, this index, and `backend-architecture-notes.md`.
- Small operator scripts should prefer local helpers for repeated fail/status/summary output when the helper keeps the operation visible.
- Integration scripts and `tests/` are validation surfaces; keep explicit request/response detail when it helps failures stay diagnosable.
- Exclude ignored bulk output such as `results/` from broad readability sweeps unless a task explicitly targets generated artifacts.

## Internal Historical Notes

The following files are retained as historical execution records and may be more verbose than day-to-day operator docs:

- `backend-restructure-plan.md`
- `backend-restructure-pr-notes.md`
- `universal-cms-improvement-checklist.md`
