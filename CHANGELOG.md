# Changelog

## Unreleased

- Harden list-query parsing so malformed pagination and sort input falls back to bounded defaults instead of risking direct cast failures.
- Remove stale tracked backend placeholder files after the backend-first source layout became canonical.
- Expand `.env.example` and README production-readiness notes to better reflect the operational surface and remaining governance gate.
- Add the v0.2 -> v0.3 enterprise enhancement checklist for the next improvement loop.

## 1.0.0

- TWEAK: Tighten canonical CMS docs and runtime banner output patterns for agent/human readability without changing API behavior.
- Promote CMS to the 1.0.0 release with aligned service, seed, and contract version defaults.
- Keep the Kujo runtime and release-gate surfaces consistent with the release version.
