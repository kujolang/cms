# Stage 1 Release Notes

## Release Scope

Stage 1 establishes a production-ready headless CMS API foundation in Kujo with secured write flows, delivery/discovery documents, relational validation, and automated verification tooling.

## Highlights

- Added public delivery endpoints:
	- `GET /robots.txt`
	- `GET /llms.txt`
	- `GET /.well-known/llms.txt`
	- `GET /sitemap.xml`
	- `GET /rss.xml`
- Added entry slug lookup endpoint:
	- `GET /v1/entries/by-slug/:content_type/:slug`
- Hardened relational write behavior:
	- taxonomy parent validation and child-term delete guards
	- entry-term assignment validation with explicit `invalid_term_ids` response details
	- plugin hook creation validates plugin existence
	- theme activation validates theme existence before status mutation
	- token deactivation validates token existence
- Added pagination metadata support across list endpoints used by content/media/navigation/extensions/auth domains.

## Verification Assets Added

- Full Stage 1 integration matrix:
	- `scripts/integration-stage1.sh`
- API smoke checks:
	- `scripts/smoke-api.sh`
- Performance baseline tooling:
	- `scripts/perf-baseline.sh`
- CI gates:
	- `.github/workflows/ci.yml` (contract + integration)

## Validation Snapshot

- Contract tests:
	- `tests/cms_contract_tests.kujo` passing
- Integration matrix:
	- `scripts/integration-stage1.sh` passing
- Smoke checks:
	- `scripts/smoke-api.sh` passing

## Known Runtime Caveats

- Some interpreter-mode route closures can fail to resolve helper symbols at runtime.
- Stage 1 mitigates this in critical routes with inline runtime-safe logic.
- See `docs/runtime-limitations.md` for details and follow-up direction.

## Stage 2 Handoff

Stage 2 should prioritize SEO metadata/schema modeling, richer query/pagination primitives, editorial workflows, and resilient integration/event tooling while maintaining Stage 1 route compatibility.
