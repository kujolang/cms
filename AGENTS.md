# Kujo CMS agent guide

Kujo CMS is the server-first backend in `backend/runtime/main.kujo`. The sibling
`../cms-example` owns the showcase frontend and Studio adapter; do not move UI
concerns into this repository.

## Read paths

- Runtime assembly and route registration: `backend/runtime/main.kujo`
- Environment contract: `backend/config/config.kujo`
- Database schema and migrations: `backend/core/database.kujo`, `backend/core/migrations.kujo`
- Authentication and authorization: `backend/modules/auth.kujo`, `backend/modules/authz.kujo`
- HTTP, idempotency, and audit boundaries: `backend/core/http.kujo`
- Feature handlers: `backend/routes/`
- Public contracts: `ability-pack.json`, `schemas/`, `examples/extensions/`, `docs/`
- Regression coverage: `tests/cms_contract_tests.kujo`, `scripts/integration-*.sh`

## Verification

Run `bash scripts/run-release-gate.sh` for the full production gate. Use
`CMS_GATE_PERF_RUNS=10` for a ten-request performance sample per endpoint. Focused
contract tests run with `kujo test-run tests/cms_contract_tests.kujo`.
Generated databases, logs, and benchmark JSON belong in `results/` and are not
source artifacts.

Preserve API envelopes, status codes, environment names, schema revisions,
idempotency semantics, and capability boundaries. Never expose credentials,
password fields, connector secrets, extension archives, or private media paths.
