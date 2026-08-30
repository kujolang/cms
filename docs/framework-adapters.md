# Framework-neutral application adapters

Kujo CMS is the source of truth for content, identities, sessions, permissions, capabilities, SEO/social settings, extensions, media records, abilities, connector state, and WebMCP. An administration application or frontend is a replaceable adapter. It may use Next.js, Astro, PHP, another server framework, a native application, or no visual interface at all.

## Recommended boundary

The browser talks to an application server. The application server talks to CMS through the JavaScript client, PHP client, raw REST, or the CLI. Keep CMS API tokens, password hashes, provider credentials, plugin runtime bearers, and storage credentials on trusted servers.

For interactive users:

1. Verify a password, passkey, or external identity in a trusted adapter.
2. Exchange the verified user through `POST /v1/auth/sessions` or `POST /v1/auth/providers/exchange`.
3. Store the returned raw CMS session in an `HttpOnly`, `Secure`, `SameSite=Lax` application cookie.
4. Forward the session as `X-CMS-Session`; load the user, role permissions, and effective capabilities from `GET /v1/auth/me`.
5. Revoke the core session through `DELETE /v1/auth/session` during sign-out.

The application owns cookie mechanics and its login experience. CMS owns session expiry, revocation, identity links, permissions, and the capability result used by any administration UI.

## Administration adapters

Build navigation from local presentation items plus `GET /v1/extensions/navigation`. Filter every item with the capability list from `/v1/auth/me`, and enforce the same capability again on server routes. The official clients include `resolveAdminNavigation` helpers; themes and plugins may contribute ordered links without knowing the administration framework.

Use the atomic content workflows for editors. `POST /v1/entries` accepts `term_ids` so a new entry and its taxonomy assignments commit together. One `PATCH /v1/entries/:id/compose` request can check `expected_updated_at`, save a revision, update content and SEO-bearing metadata, and replace term assignments. This prevents half-saved content when a browser, agent, or server action fails between requests.

ZIP and media uploads can use base64 API upload endpoints for bounded administration forms. A filesystem media adapter can read a verified object with `mediaFile` and stream the decoded bytes from its own public route; the example does this at `/media/:key`. For larger or distributed deployments, use a two-step trusted adapter:

- accept multipart bytes under the adapter's normal ingress limits;
- write a generated simple filename into the configured CMS inbox shared with the CMS process;
- call the matching CMS ingestion endpoint;
- discard the temporary inbox copy according to the deployment retention policy.

CMS performs the authoritative archive or media verification. In distributed deployments, mount a private shared inbox or implement a small upload service beside CMS. Do not make either inbox web-readable.

## Frontend adapters

Published sites use delivery routes and do not require an administration session. A frontend may render dynamically, pre-render, or generate static output. Include the script published by `/.well-known/kujo-webmcp.json` in the page shell to inherit the CMS public WebMCP tools. Use the official sharing helper to create consistent links for X, Bluesky, LinkedIn, Facebook, Reddit, WhatsApp, Pinterest, and email from the account settings returned by `/v1/settings/social-sharing`.

Themes are ordinary frontend packages described by `kujo-theme.json`; they are not coupled to the administration application. A deployment controller selects the active manifest, installs dependencies in isolation, builds the selected entrypoint, and points it at the CMS delivery URL.

## PHP example

```php
use Kujo\Cms\KujoCmsClient;

$cms = new KujoCmsClient($_ENV['CMS_BASE_URL'], token: $_ENV['CMS_API_TOKEN']);
$result = $cms->composeEntry(42, [
    'expected_updated_at' => $currentVersion,
    'revision_note' => 'editor save',
    'entry' => ['title' => 'Updated title'],
    'term_ids' => [3, 8],
]);
```

## JavaScript example

```js
import { KujoCmsClient, buildShareUrl } from "@kujolang/cms-client";

const cms = new KujoCmsClient({
  baseUrl: process.env.CMS_BASE_URL,
  session: request.cookies.get("cms_session")?.value,
});

const identity = await cms.me();
const shareUrl = buildShareUrl("bluesky", {
  url: article.url,
  title: article.title,
  account: social.accounts.bluesky,
});
```

## Agent parity

Every first-party workflow is available through REST and a matching shell command. Abilities add permission-aware, schema-described operations for agents and can be translated into MCP tools. WebMCP remains public and read-only. Plugin abilities execute through explicit external runtime contracts with outbound URL policy, timeouts, bounded responses, optional server-only bearers, state controls, health checks, and audit events.
