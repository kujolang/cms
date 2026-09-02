# CMS core Ability pack certification — 2026-09-02

Certification level: local reference-gateway conformance

Source revision: `11fb5ee`

CMS package version: `1.1.0` (unreleased)

Ability Pack: `kujo.cms.core@1.0.0`

Canonical Ability dependency: `1.0.1`, pinned through `kennel.toml` and `kennel.lock`

Owner: Kujo CMS owns handlers, permissions, gateway policy, durable approval/idempotency/audit state, and product data. `kujolang/ability` owns the definition and runtime contracts.

## Certified core catalog

| Canonical Ability | CMS route name | Effect | Idempotency | Permission | Approval | Handler maturity |
| --- | --- | --- | --- | --- | --- | --- |
| `kujo.cms.site.inspect@1.0.0` | `cms/site-info` | `read` on `kujo.cms.site` | intrinsic | `cms.read` | no | bounded core handler |
| `kujo.cms.content.list@1.0.0` | `content/list` | `read` on `kujo.cms.content` | intrinsic | `cms.read` | no | bounded core handler, limit ≤ 50 |
| `kujo.cms.seo.audit@1.0.0` | `seo/audit-summary` | `read` on `kujo.cms.seo` | intrinsic | `cms.read` | no | bounded core handler, limit ≤ 50 |
| `kujo.cms.seo.update-entry@1.0.0` | `seo/update-entry` | `write` on `kujo.cms.seo` | keyed | `cms.write` | request-bound, one-time | bounded core handler |
| `kujo.cms.seo.bulk-update@1.0.0` | `seo/bulk-update` | `write` on `kujo.cms.seo` | keyed | `cms.write` | request-bound, one-time | bounded core handler, ≤ 200 entries |
| `kujo.cms.integrations.inspect@1.0.0` | `ai/integration-status` | `read` on `kujo.cms.integrations` | intrinsic | `admin.settings` | no | secret-redacted core handler |

All definitions use closed input and output schemas. Discovery is principal-visible and requires the descriptor permission. The CMS gateway validates canonical identity and definition digest, authorizes every call, atomically consumes approvals, rejects approval replay and idempotency conflicts, validates handler output, writes audit evidence, and returns canonical receipts.

## Verification

The following clean run passed on 2026-09-02:

```bash
CMS_GATE_PORT_BASE=56400 \
CMS_GATE_RUN_PERF=false \
KUJO_BIN=/path/to/kujo/target/release/kujo \
bash scripts/run-release-gate.sh
```

Evidence included:

- 36 of 36 CMS contract tests;
- positive authenticated discovery and read execution;
- input and output schema enforcement;
- approval-required denial, approval issuance, approved write, and replay denial;
- keyed idempotency replay and changed-input conflict;
- canonical receipt identity and audit rows;
- tenant isolation and scoped authorization;
- secret redaction and webhook egress controls;
- background jobs, graceful restart, migration, backup/restore, load, and package validation;
- port-safety regression proving the release gate never stops an unrelated listener.

The canonical Ability repository release gate and its CMS consumer conformance checks also passed. The MCP bridge contract passed against an authenticated fixture for discovery, read, approval, write, replay denial, idempotency conflict, cancellation, and receipt preservation.

## Support and security boundary

This certification covers the local/customer-hosted CMS reference gateway contract and deterministic repository fixtures. It does not certify a production deployment, managed multi-tenant service, marketplace host, infrastructure configuration, SSO/SCIM, regional controls, or enterprise operations. Deployments must supply HTTPS, rotated least-privilege credentials, durable storage, backup/restore, ingress controls, monitoring, retention/deletion policy, and target-environment security review.

Vulnerabilities should be reported through the repository security policy. Public issues must not contain credentials, approval tokens, customer content, or private receipts.
