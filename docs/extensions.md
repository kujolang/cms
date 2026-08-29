# Portable Themes and Plugins

Kujo CMS treats themes and plugins as portable, versioned contracts instead of installation-specific database records.

## Theme packages

A theme repository includes `kujo-theme.json` at its root. The manifest identifies the package, compatible CMS contract, frontend entrypoints, templates, assets, settings schema, defaults, supported content types, menu locations, and distribution metadata.

Themes remain ordinary frontend projects. They can use any framework that consumes the CMS delivery API. The manifest gives installers, marketplaces, deployment tools, agents, and the administration interface one stable way to understand and configure the project.

The backend never downloads or executes theme code. Installation records the validated manifest and settings. Deployment tooling fetches a declared package, verifies its `sha256-` integrity value when supplied, builds it in an isolated environment, and connects it to the CMS URL.

Lifecycle:

1. Create a frontend repository with `kujo-theme.json`.
2. Validate it with `POST /v1/themes/validate` or `bash scripts/cms-extensions.sh theme:validate kujo-theme.json`.
3. Install it with `POST /v1/themes/install` or the CLI equivalent.
4. Configure settings against `settings_schema`.
5. Activate exactly one installed theme.
6. Export the normalized, secret-free manifest from `GET /v1/themes/:id/export`.

[`examples/extensions/starter-theme/kujo-theme.json`](../examples/extensions/starter-theme/kujo-theme.json) is the canonical starter.

The Field Notes frontend is a complete reusable theme package in the independent [`cms-field-notes-theme`](https://github.com/kujolang/cms-field-notes-theme) repository. The CMS showcase bundles it as the default, but the standalone repository contains only the public theme so creators can fork, remix, package, and distribute it without the administration application.

The `cms-example` administration frontend provides separate **Themes** and **Plugins** screens, where an administrator can drag in or choose a ZIP, install it, optionally activate it immediately, and manage installed extensions. Its server adapter rejects encrypted archives, traversal paths, unsupported compression, duplicate manifests, oversized packages, excessive expanded size, and CRC failures before calling the CMS install API. The CMS stores the normalized manifest and a bounded receipt containing the package digest and archive facts; it does not execute uploaded code.

## Plugin packages

A plugin repository includes `kujo-plugin.json`. Its manifest declares identity, compatibility, runtime type, capabilities, subscribed events, optional Abilities API descriptors, configuration schema, defaults, and distribution metadata.

Supported runtime declarations are:

- `connector`: a trusted external service integrated through a server-side adapter.
- `webhook`: an HTTPS event receiver registered with a separately supplied shared secret.
- `browser`: a frontend module loaded by a theme or administration application.
- `hybrid`: a package with more than one of those components.

Installing a manifest does not install webhook secrets, provider credentials, or executable code. Secrets are configured separately through protected operational routes. Plugins install inactive unless activation is explicitly requested.

Installing a newer manifest for an existing package preserves its current activation state and configured settings unless the request supplies replacements. This makes package upgrades safe for customer-specific configuration while keeping activation an explicit lifecycle decision.

[`examples/extensions/starter-plugin/kujo-plugin.json`](../examples/extensions/starter-plugin/kujo-plugin.json) is the canonical starter.

[`cms-contact-form`](https://github.com/kujolang/cms-contact-form) is the full plugin showcase. It combines a framework-neutral contact-form web component with a standalone SQLite-backed connector, protected moderation API, matching CLI, OpenAPI discovery, declared agent abilities, origin policy, rate limiting, honeypot filtering, hashed client addresses, and signed notification delivery for email or automation adapters.

## Administration extensions

Both manifest types accept an optional `admin` object. `admin.icon` supplies an HTTPS, root-relative, or package-relative branded image for the Themes or Plugins card. `author.url` makes the creator name link to its verified HTTPS destination.

`admin.navigation` contains at most 20 ordered, capability-scoped links. Each item declares `key`, `label`, an internal `/cms` path, numeric `order`, capability, and optional icon image. An item whose key matches a built-in navigation item may change only its order in Studio; it cannot replace the built-in destination or access policy. New keys add extension-owned links. Only the active theme and active plugins contribute links.

The resolved surface is available to applications and agents at `GET /v1/extensions/navigation` and through `bash scripts/cms-extensions.sh navigation`. This keeps the visual Studio sidebar, REST API, and terminal discovery on the same manifest source of truth.

Plugin manifests may also declare bounded, secret-free `abilities` and `connectors`. Active contributions are merged into `GET /v1/abilities` and `GET /v1/ai/connectors`, and their raw package descriptors remain discoverable at `GET /v1/extensions/ai` and `bash scripts/cms-extensions.sh ai`. Their execution and secret handling stay in the plugin’s declared runtime, so CMS marks them plugin-managed and does not claim they are native MCP tools. Activating or deactivating the plugin controls whether these contributions are published.

## Contracts and API

`GET /v1/extensions/contracts` returns the current filenames, schemas, routes, portability model, and security boundary. `GET /v1/extensions/catalog` returns installed theme manifests and active plugin manifests for discovery. `GET /v1/extensions/navigation` and `GET /v1/extensions/ai` return the active administration and AI contributions.

| Operation | Theme | Plugin |
| --- | --- | --- |
| Validate | `POST /v1/themes/validate` | `POST /v1/plugins/validate` |
| Install/update | `POST /v1/themes/install` | `POST /v1/plugins/install` |
| Export | `GET /v1/themes/:id/export` | `GET /v1/plugins/:id/export` |
| Activate | `POST /v1/themes/:id/activate` | `PATCH /v1/plugins/:id` |

Validation endpoints require an authenticated CMS reader and are rate-limited. Theme installation requires `admin.settings`; plugin installation and export require `admin.plugins`. Theme exports are public because frontend manifests are distributable metadata. Every export is curated and excludes stored settings, hook secrets, credentials, and connector endpoints.

Install APIs accept an optional verified `package` receipt with ZIP filename, compressed and expanded sizes, file count, manifest path, and SHA-256 digest. `GET /v1/extensions/manage` gives authenticated administration adapters an all-installed catalog without exposing extension settings. Terminal users can install the same archive with `theme:install-zip` or `plugin:install-zip`; the CLI performs the archive checks locally before sending the receipt.

## Compatibility policy

Manifest schemas are versioned independently from package versions. Consumers must reject unsupported schema identifiers and unknown fields. New optional capabilities should use a new manifest schema when their meaning changes existing behavior.

Package authors should:

- use immutable released versions;
- publish HTTPS repository and package URLs;
- provide a `sha256-` integrity digest for downloadable artifacts;
- keep settings declarative and secret-free;
- declare the smallest capability and event surface;
- test against the public delivery contract, extension contract, and active theme payload;
- keep privileged mutations in authenticated API or Abilities API operations.

The CMS package registry is deliberately transport-neutral. A public catalog, private vendor registry, direct repository release, customer-only package server, or local file can all carry the same manifests.
