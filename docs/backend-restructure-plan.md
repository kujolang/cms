# Backend Restructure Plan (Root Kujo Files -> backend/)

Historical note: this document is retained for migration traceability. The current authoritative architecture and import policy are defined in `docs/backend-architecture-notes.md`.

## Purpose
This document defines how to reorganize the CMS starter backend so Kujo source files are easier to embed in custom projects while preserving API stability and upgrade safety.

The primary objective is to support a universal, reusable backend core that can be dropped into a larger project layout (for example, separate frontend and backend folders) without forcing breaking changes on existing consumers.

## Product Principles
- Keep the backend starter as the single source of truth for reusable features.
- Preserve endpoint contracts for current API versions.
- Add functionality by extension, not breakage.
- Make adoption and upgrades predictable for downstream projects.

## Current Problem
- Many Kujo source files live at repository root.
- Root-heavy layout is less intuitive for teams embedding backend code in a larger CMS project.
- Future modular work (auth providers, storage adapters, plugins) is harder to reason about without clear folders.

## Target Outcome
- Introduce a `backend/` area for backend runtime code.
- Keep compatibility entrypoints at root for one or more transition releases.
- Publish a migration guide so existing users can upgrade without surprises.

## Non-Goals
- No immediate API v1 contract breaks.
- No forced rewrite of consumer frontends.
- No large one-shot refactor without compatibility scaffolding.

## Proposed Folder Design (Phase Target)
- backend/
- backend/app/
- backend/core/
- backend/routes/
- backend/modules/
- backend/config/
- backend/bootstrap/
- backend/runtime/

Suggested mapping approach:
- Keep the primary runtime entrypoint at root temporarily.
- Move implementation files into backend subfolders.
- Leave thin root compatibility files that delegate to backend paths.

## API Compatibility Policy (Required)
- Existing v1 endpoint paths remain available.
- Existing response fields keep semantics and types.
- Additive changes are preferred (new optional fields, new endpoints).
- Breaking changes require a new version boundary (for example, v2).
- Any deprecation includes warning period plus docs before removal.

## Auth and Feature Expansion Policy
- Improvements such as SSO providers, 2FA, or stronger authorization belong in starter core if broadly useful.
- New auth modes should be opt-in via configuration flags.
- Existing auth flows remain valid until explicit deprecation lifecycle completes.

## Agent Execution Checklist (Step-by-Step)
Use this as the primary implementation checklist. Complete items in order. Do not start the next phase until the current phase gate is fully checked.

### Phase 0: Baseline and Guardrails
- [x] Confirm current branch and ensure working tree is clean.
- [x] Capture baseline test command outputs for comparison.
- [x] Confirm no planned API v1 breaking change in current work scope.
- [x] List all root Kujo runtime files that may be migrated.
- [x] Create a short migration scope note for this execution cycle.

Phase 0 gate:
- [x] Baseline captured and attached to PR notes.
- [x] Scope for this cycle is explicit and limited.

### Phase 1: Prepare (No Behavior Change)
- [x] Define backend module boundaries (runtime, routing, config, resolver, auth).
- [x] Produce file mapping table: old path -> target path.
- [x] Add or update architecture notes in docs.
- [x] Identify critical API v1 contract surfaces used by frontend/admin.
- [x] Add or update contract tests for those critical surfaces.

Phase 1 gate:
- [x] Existing tests pass unchanged.
- [x] Contract coverage exists for critical v1 surfaces.

### Phase 2: Compatibility Scaffolding
- [x] Create backend folder skeleton (`backend/`, `backend/app/`, `backend/core/`, `backend/routes/`, `backend/modules/`, `backend/config/`, `backend/bootstrap/`, `backend/runtime/`).
- [x] Add root compatibility wrappers for entrypoints that will move.
- [x] Ensure wrappers delegate behavior without changing output shape.
- [x] Update internal load/import flow so old and new paths can coexist during transition.
- [x] Add tests or checks proving old commands still work.

Phase 2 gate:
- [x] Existing startup commands still work.
- [x] No endpoint/status/response-shape regressions.

### Phase 3: Internal Migration (Incremental)
- [x] Choose one migration domain only (routing OR config OR resolver OR auth) for the current PR.
- [x] Move only files in the chosen domain to backend target paths.
- [x] Update imports/references for moved files.
- [x] Keep root wrappers thin and functional.
- [x] Run contract + integration + smoke tests.
- [x] Record rollback steps for the moved domain.

Phase 3 gate:
- [x] All tests pass.
- [x] Wrapper layer remains documented and minimal.

### Phase 4: Documentation and Consumer Guidance
- [x] Update README usage and structure sections for migrated paths.
- [x] Update migration docs with old-to-new path mapping table.
- [x] Add upgrade guidance for embedded/custom CMS consumers.
- [x] Update examples if any command or path references changed.
- [x] Add release notes entry for this migration step.

Phase 4 gate:
- [x] New user setup and existing user upgrade path are both documented.
- [x] Migration mapping is explicit and complete for this cycle.

### Phase 5: Deprecation and Cleanup (Deferred)
- [x] Define deprecation timeline for root wrappers.
- [x] Announce timeline in docs and changelog before removals.
- [x] Confirm at least one stable transition cycle has elapsed.
- [x] Remove wrappers only after timeline and migration docs are validated.

Phase 5 gate:
- [x] No undocumented removals.
- [x] Consumers received clear lead time and migration path.

## Per-PR Checklist (Required Every Migration PR)
- [x] Scope limited to one domain.
- [x] No API v1 breaking changes introduced.
- [x] Contract tests run and pass.
- [x] Integration tests run and pass.
- [x] Smoke tests run and pass.
- [x] README updated if user-visible behavior changed.
- [x] CHANGELOG updated with concise migration note.
- [x] `.gitignore` updated only if new generated/temp artifacts were introduced.
- [x] Commits are meaningful and scoped.
- [x] Branch pushed and PR notes include validation output.
- [x] Working tree is clean after commit/push.

## Delivery Strategy

### Phase 1: Prepare (No Behavior Change)
- Define internal module boundaries and file map.
- Add architecture diagram and ownership notes.
- Add contract tests that lock current endpoint shapes.

Exit criteria:
- All existing tests pass unchanged.
- Contract tests cover critical v1 endpoints used by frontend/admin clients.

### Phase 2: Compatibility Scaffolding
- Create backend folder skeleton.
- Add root compatibility loaders/wrappers for runtime entrypoints.
- Introduce internal imports that can resolve both old and new paths during transition.

Exit criteria:
- Existing commands and scripts still work.
- No endpoint or response regressions.

### Phase 3: Internal File Migration
- Move root Kujo implementation files into backend modules incrementally.
- Keep one migration PR per logical domain (routing, config, resolver, auth).
- Run tests after each domain move.

Exit criteria:
- All runtime and contract tests green.
- Root wrappers are thin and documented.

### Phase 4: Docs and Consumer Guidance
- Update README, usage docs, and integration examples.
- Publish upgrade notes for embedded backends.
- Provide "old layout -> new layout" mapping table.

Exit criteria:
- New users can start with backend folder layout only.
- Existing users can still run without immediate rewrites.

### Phase 5: Deprecation and Cleanup
- Announce deprecation timeline for root compatibility wrappers.
- Remove wrappers only after at least one stable transition cycle.

Exit criteria:
- Consumers had clear lead time and migration path.
- No undocumented removals.

## Test Requirements for Each Phase
- Contract tests for endpoint path, status, and response shape.
- Integration tests for major flows.
- Smoke tests for startup and core read/write operations.
- Migration check that old commands still boot during compatibility phase.

## Risk Register and Mitigations
- Risk: hidden import path regressions.
Mitigation: incremental moves and wrapper-based compatibility.

- Risk: accidental endpoint shape drift.
Mitigation: strict contract tests and release checklist gate.

- Risk: downstream custom CMS breaks during pull-in.
Mitigation: publish migration guide plus versioned release notes.

## Change Management for Downstream Projects
- Starter repo remains authoritative for backend core.
- Custom CMS repo pulls starter updates via normal version control workflow.
- Avoid manual copy/paste as primary method; use tagged releases and merge/cherry-pick strategy.

## Release Checklist Additions
- Confirm v1 endpoint contract diffs are additive only.
- Confirm docs list any new fields as optional unless version-bumped.
- Confirm migration notes are present for path/layout changes.
- Confirm deprecations have timeline and alternative.

## Work Package Template (For Future Implementation Agent)
- Scope: one migration domain only.
- Inputs: current files, target paths, compatibility requirements.
- Steps: move files, update imports, keep wrappers, run tests, update docs.
- Validation: contract + integration + smoke.
- Output: PR with migration notes and rollback plan.

## Definition of Done
- Backend folder structure exists and is in active use.
- Root compatibility path remains functional during transition window.
- API v1 remains stable unless explicitly versioned.
- Tests and docs enforce the migration contract.
- Downstream custom CMS users can upgrade with clear instructions.
