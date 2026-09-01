# CMS Abilities

The portable definition contract is maintained by
[`kujolang/ability`](https://github.com/kujolang/ability). CMS owns the product
bindings, permissions, confirmation policy, REST/CLI exposure, and audit data;
the shared package does not.

CMS Abilities expose bounded semantic operations without making HTTP, MCP, or WebMCP the source of their meaning.

## Contract layers

Each resolved CMS Ability has separate concerns:

- `definition` is the portable `kujo.ability/v1` semantic contract;
- `definition_digest` is the canonical SHA-256 identity of that exact definition;
- the CMS descriptor keeps legacy route name, category, permission, enablement, source, and annotations;
- core or plugin bindings implement execution;
- CMS authentication, permissions, confirmation, tenancy, rate limits, and audit remain application policy;
- REST and MCP-ready records are explicit exposure projections.

The canonical JSON Schema and runtime validators are installed from the exact
Ability commit recorded in [`kennel.lock`](../kennel.lock). CMS imports the
package through `from ability import ...`; it no longer maintains a copied
contract. A definition requires a dotted ID, semantic version, bounded
description, input/output schemas, one or more semantic effects, and an
idempotency mode.

Effect kinds are intentionally limited to `read`, `write`, `delete`, and `external`. Idempotency modes are `intrinsic`, `keyed`, and `none`. Permissions, roles, credentials, handlers, URLs, providers, timeouts, approvals, and protocol names do not belong to the portable definition.

## Discovery

- `GET /v1/abilities` returns resolved CMS descriptors with their nested portable definitions.
- `GET /v1/abilities/definitions` returns only validated `kujo.ability/v1` definitions.
- `GET /v1/abilities/categories` returns CMS presentation categories.
- `GET /v1/ai/mcp/tools` returns enabled MCP-ready projections with canonical Ability ID, version, effects, and input/output schemas.

All four routes require an authenticated principal with `cms.read` or the more specific descriptor permission.

## Invocation enforcement

`POST /v1/abilities/:namespace/:ability/run` performs the controls in this order:

1. resolve the server-owned descriptor and reject disabled Abilities;
2. authenticate and authorize through the descriptor permission;
3. apply request rate limiting and supported idempotency handling;
4. require `confirmed: true` for every descriptor marked `requires_confirmation`, including plugin Abilities;
5. validate input against the advertised schema;
6. build the exact definition, handler binding, and REST exposure in the shared
   Ability registry;
7. execute through the canonical Ability runtime;
8. validate output against the advertised closed schema;
9. write preflight and completion audit evidence; and
10. return and, for keyed writes, atomically persist the normalized Ability receipt.

Input schema violations return `ability_input_invalid`. Handler output contract
violations fail closed with `ability_output_invalid` and HTTP 502. Unsupported
schemas or invalid registered definitions fail rather than becoming silently
advisory metadata. Successful responses preserve the legacy `ability` and
`result` fields and add a normalized `receipt` containing the canonical ID,
exact version, definition digest, handler version, principal, request ID,
trace ID, policy decision, timing, audit state, and idempotency state.

Abilities whose definition declares `idempotency.mode = keyed` require an
`Idempotency-Key` header. CMS creates the durable pending record before the
handler runs and commits the normalized receipt on completion.

The current compatibility confirmation is a boolean inside `input`. It is enforced generically, but it is not a substitute for a future request-bound approval token. Product policy remains responsible for deciding when approval is required.

## Plugin compatibility

`kujo.plugin/v1` remains the installation compatibility surface. Plugin Ability descriptors are now checked for:

- a bounded lowercase dotted name;
- a bounded description and optional label;
- an allowlisted HTTP method;
- an absolute non-traversing runtime path;
- a bounded permission string;
- supported input/output JSON Schemas;
- no unknown fields or sensitive values.

CMS converts each active plugin descriptor into a portable definition while keeping HTTP method/path and permission in the plugin binding and policy descriptor. `GET` maps conservatively to a `read` effect with intrinsic idempotency. Other methods map to a `write` effect with no automatic idempotency guarantee unless a future plugin contract declares stronger semantics.

## WebMCP boundary

Public CMS WebMCP remains a separate allowlisted surface. The four built-in site tools are same-origin, read-only, published-only, bounded, and untrusted-content aware. CMS never exports an Ability to WebMCP merely because it is annotated read-only. Authenticated, private, and mutating operations remain behind the Abilities API.

## Compatibility

Legacy names such as `content/list` and `seo/update-entry`, existing REST routes, CLI forms, and client helpers remain supported. Canonical IDs such as `kujo.cms.content.list` are additive identity. Protocol adapters may derive local names but must preserve canonical ID/version metadata and reject collisions.
