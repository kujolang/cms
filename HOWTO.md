# Build a Site with Kujo CMS

Kujo CMS is a server-first, headless content backend. It stores and delivers content, while your website remains a separate application that you are free to build with any frontend stack: Next.js, Astro, Nuxt, SvelteKit, a native app, a static-site generator, or plain HTML and JavaScript.

That separation is the central idea behind this guide. The CMS owns content, publishing state, API access, and operational concerns. Your frontend owns routes, components, styling, rendering, and the user experience.

By the end of this HOWTO, you will have:

- A local CMS API backed by SQLite
- An `article` content type
- A published first article
- A frontend reading content through the public API
- A clear path from local prototype to an agent-assisted production workflow

## Why Build This Way?

### Your frontend is whatever you want it to be

Kujo CMS does not force your site into a theme runtime or a specific JavaScript framework. A frontend only needs to make HTTP requests and read JSON. You can replace the frontend without migrating the content backend, add a mobile client alongside the website, or serve multiple experiences from the same content source.

The CMS does include a theme registry, but theme records are metadata and activation controls. They do not take ownership of frontend rendering. Your application still decides what an active theme means and how it should look.

### The workflow is agentic-first

An agent works best when a system is discoverable, explicit, and testable. Kujo CMS exposes the surfaces an agent needs to understand and safely operate the project:

- `GET /v1` advertises API capabilities.
- `GET /v1/openapi.json` provides a machine-readable API contract.
- `GET /.well-known/llms.txt` and `GET /llms.txt` describe useful public routes.
- Predictable JSON envelopes make responses easy to inspect and compose.
- Bearer-authenticated writes keep public reads separate from mutations.
- Idempotency support makes automated mutation retries safer.
- Contract tests and a release gate give both humans and agents an objective definition of working.

This makes a practical agentic loop possible: inspect the contract, model the content, create or update it through authenticated routes, connect the frontend, run validation, and use failures as structured feedback.

Agentic-first does not mean agents bypass review or security. It means the normal interface is structured enough for agents to contribute without relying on hidden dashboard behavior or brittle browser automation.

### Content and presentation can evolve independently

Editors and automations can work with entries while frontend developers refine the site. Published-only anonymous reads prevent drafts, scheduled entries, archived entries, and revision history from leaking through the public delivery path. Revisions, rollback, scheduling, entry locks, webhooks, and background jobs are available when the workflow grows beyond a simple blog.

### Delivery basics are already present

The backend provides sitemap, RSS, robots, security, health, readiness, metrics, and API discovery routes. These do not replace good frontend SEO or production operations, but they give a new site a useful foundation.

## 1. Prerequisites

You need:

- A Kujo runtime binary
- Bash and `curl`
- This repository checked out locally

If you need to build Kujo first:

```bash
cd /path/to/kujo
cargo build --bin kujo
```

The examples below assume the binary is at `/path/to/kujo/target/debug/kujo` and this repository is at `/path/to/cms`.

## 2. Configure the CMS

From the repository root, create your local environment file:

```bash
cd /path/to/cms
cp .env.example .env
```

The development defaults bind the server to `127.0.0.1:4200` and store data in `cms.db`. Before doing anything beyond local development, replace the bootstrap token and set the public site URL and CORS origin deliberately.

For this local walkthrough, confirm these values in `.env`:

```dotenv
CMS_API_HOST=127.0.0.1
CMS_API_PORT=4200
CMS_SITE_URL=http://127.0.0.1:4200
CMS_DB_PATH=cms.db
CMS_API_TOKEN=change-me-in-production
CMS_ENV=development
```

The placeholder token is only for a local walkthrough. Never deploy it.

## 3. Start the API

The canonical runtime entrypoint is `backend/runtime/main.kujo`:

```bash
cd /path/to/cms
/path/to/kujo/target/debug/kujo run --interpreter backend/runtime/main.kujo
```

Keep that process running. In another terminal, verify the API and inspect its discovery surfaces:

```bash
curl -sS http://127.0.0.1:4200/health
curl -sS http://127.0.0.1:4200/v1
curl -sS http://127.0.0.1:4200/v1/openapi.json
curl -sS http://127.0.0.1:4200/.well-known/llms.txt
```

These are also good first requests for a coding agent joining the project: health establishes that the service is running, while the capability and contract endpoints describe the available interface.

Set a few shell variables for the remaining examples:

```bash
export CMS_BASE="http://127.0.0.1:4200"
export CMS_TOKEN="change-me-in-production"
```

## 4. Model the Site's Content

A content type describes a family of entries. A fresh CMS database currently seeds `article` and `page` content types, plus a published welcome article. Inspect the available models before creating anything:

```bash
curl -sS "${CMS_BASE}/v1/content-types?sort_by=type_key&sort_dir=asc"
```

If `article` is already present, use it and skip the next request. If your installation does not include it, create it:

```bash
curl -sS -X POST "${CMS_BASE}/v1/content-types" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: setup-article-content-type-v1" \
  --data '{
    "type_key": "article",
    "label": "Articles",
    "singular_label": "Article",
    "description": "Long-form editorial content",
    "supports": {
      "excerpt": true,
      "seo": true
    }
  }'
```

List the available content types again to confirm the model you will use:

```bash
curl -sS "${CMS_BASE}/v1/content-types?sort_by=type_key&sort_dir=asc"
```

If the create request returns HTTP 409 with `create_failed`, the `type_key` probably already exists. Reuse the existing model or choose a different key; an idempotency key only replays the same earlier request and does not turn a pre-existing seeded record into a successful create.

Content modeling is where headless architecture pays off. Use content types to describe editorial meaning—articles, documentation pages, release notes, case studies—not frontend component names. A `case-study` content type can be rendered as a full web page, a homepage card, an email excerpt, and a mobile screen without duplicating the underlying content.

## 5. Publish the First Article

Create a published entry:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: publish-hello-kujo-v1" \
  --data '{
    "content_type_key": "article",
    "title": "Hello from Kujo CMS",
    "slug": "hello-kujo",
    "status": "published",
    "excerpt": "Our first article from a frontend-agnostic CMS.",
    "body": "# Hello, world!\n\nThis body is stored by the CMS and rendered by the frontend.",
    "author_id": "editorial-team",
    "meta": {
      "featured": true
    },
    "seo": {
      "title": "Hello from Kujo CMS",
      "description": "A first site powered by Kujo CMS.",
      "schema_type": "Article"
    }
  }'
```

The `body` is stored as text. In this example it contains Markdown, but the frontend is responsible for parsing and sanitizing it. You could instead establish HTML, portable JSON, or another body convention for your project.

Read the entry without authentication, just as the public site will:

```bash
curl -sS "${CMS_BASE}/v1/entries/by-slug/article/hello-kujo"
```

Or fetch an article index with only the fields a listing page needs:

```bash
curl -sS "${CMS_BASE}/v1/entries?content_type=article&fields=title,slug,excerpt,published_at&sort_by=published_at&sort_dir=desc"
```

Anonymous requests only receive published entries. Authenticated editorial clients can also work with `draft`, `scheduled`, and `archived` content.

## 6. Connect Any Frontend

The integration contract is ordinary HTTP plus JSON, so the same approach works in server-rendered frameworks, build-time generators, browser applications, and native clients.

Here is a framework-neutral JavaScript data layer for server-rendered frameworks and build-time generators:

```js
const cmsBase = process.env.CMS_BASE_URL ?? "http://127.0.0.1:4200";

export async function getArticles() {
  const url = new URL("/v1/entries", cmsBase);
  url.searchParams.set("content_type", "article");
  url.searchParams.set("fields", "title,slug,excerpt,published_at");
  url.searchParams.set("sort_by", "published_at");
  url.searchParams.set("sort_dir", "desc");

  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`CMS request failed: ${response.status}`);

  const payload = await response.json();
  return payload.data.items;
}

export async function getArticle(slug) {
  const path = `/v1/entries/by-slug/article/${encodeURIComponent(slug)}`;
  const response = await fetch(new URL(path, cmsBase), {
    headers: { Accept: "application/json" },
  });

  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`CMS request failed: ${response.status}`);

  const payload = await response.json();
  return payload.data;
}
```

Use `getArticles()` in an index route and `getArticle(slug)` in a dynamic article route. Everything after that—Markdown rendering, design tokens, image handling, caching, page transitions, analytics—is a frontend decision.

For a static site, call these functions during the build. For server-side rendering, call them per request or through the framework's cache. In plain browser code, replace `process.env.CMS_BASE_URL` with your build tool's public environment convention or a fixed public API URL. For a client-rendered app, set `CMS_CORS_ORIGIN` to the exact frontend origin rather than leaving it as `*` in production.

Do not expose `CMS_API_TOKEN` in browser code. Public pages do not need it. Put editorial mutations in a trusted server, admin application, CI workflow, or agent tool that can protect credentials.

## 7. Add Taxonomy, Navigation, and Media

Once the basic route works, the API can model the rest of the site:

- Taxonomies and terms categorize content.
- Menus provide managed navigation data.
- Media records associate URLs, MIME types, and alt text with assets.
- SEO projections expose normalized metadata for a frontend.
- RSS and sitemap variants support discovery by content type and taxonomy.

For example, create a topic taxonomy:

```bash
curl -sS -X POST "${CMS_BASE}/v1/taxonomies" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{
    "taxonomy_key": "topic",
    "label": "Topics",
    "description": "Editorial subject areas"
  }'
```

Save the `id` from that response as `<taxonomy_id>`, then create a term:

```bash
curl -sS -X POST "${CMS_BASE}/v1/taxonomies/<taxonomy_id>/terms" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: setup-agentic-systems-term-v1" \
  --data '{
    "name": "Agentic Systems",
    "slug": "agentic-systems",
    "description": "Tools and workflows designed for agents and humans"
  }'
```

Save the term response `id` as `<term_id>` and the article response `id` from step 5 as `<entry_id>`. Attach the term with the actual returned IDs—IDs are database-assigned and must not be guessed:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries/<entry_id>/terms" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: assign-hello-kujo-agentic-systems-v1" \
  --data '{"term_ids":[<term_id>]}'
```

`POST /v1/entries/:id/terms` replaces the entry's complete term assignment with the supplied array. The live contract at `/v1/openapi.json` is the best place for a human or agent to discover the rest of the current route surface.

## 8. Use an Agentic Build Loop

A productive agent-assisted workflow can stay small and explicit:

1. Ask the agent to inspect `/v1`, `/v1/openapi.json`, and `/.well-known/llms.txt`.
2. Describe the site in editorial terms: required content types, taxonomies, menus, and publishing rules.
3. Have the agent propose API mutations before applying them, especially against shared or production data.
4. Use a unique `Idempotency-Key` for retryable mutations.
5. Let the agent build the frontend against public, published-only routes.
6. Run contract tests and the release gate after source or API-documentation changes.
7. Review the rendered site, accessibility, content accuracy, and production configuration as human-owned release decisions.

A useful prompt might be:

> Inspect the Kujo CMS capability and OpenAPI endpoints. Create a content model for a documentation site with guides and release notes, then build the frontend against published-only routes. Keep write credentials server-side, use idempotency keys for mutations, and run the repository validation gate before reporting completion.

Because the CMS contract is available over HTTP, this workflow is not tied to a particular agent product. The same system can support a local coding agent, an internal editorial automation, or a CI publishing job.

## 9. Editorial and Operational Features

As the site matures, you can add:

- Revisions and rollback for editorial recovery
- Entry locks for concurrent editing
- Scheduled publishing and unpublishing
- Webhook hooks and an outbox with retries
- Background jobs and dead-letter replay
- Roles and API tokens with lifecycle controls
- Tenant and workspace isolation
- Database migration checks, backup, and restore
- Health, readiness, metrics, structured audit logs, and rate limiting

These features let the frontend stay focused on presentation while the backend handles content workflow and operational policy.

## 10. Validate Before You Ship

Run the contract suite:

```bash
cd /path/to/cms
/path/to/kujo/target/debug/kujo test-run tests/cms_contract_tests.kujo
```

Run the repository release gate without the optional performance pass:

```bash
cd /path/to/cms
CMS_GATE_RUN_PERF=false \
KUJO_BIN=/path/to/kujo/target/debug/kujo \
bash scripts/run-release-gate.sh
```

For a public production deployment, also:

- Set `CMS_ENV=production`.
- Rotate `CMS_API_TOKEN` and disable the bootstrap token after provisioning.
- Set a specific `CMS_CORS_ORIGIN`.
- Use durable storage and test backup and restore procedures.
- Review rate limiting, webhook URL policy, observability, TLS, infrastructure, and secrets management.
- Run your own threat-model, privacy, compliance, accessibility, and load reviews.
- Enforce the release gate through branch protection or repository rulesets.

The repository documents its current production-readiness posture in `README.md` and `docs/enterprise-production-readiness-plan.md`. Treat that evidence as a starting point, not a substitute for reviewing the environment where your site will actually run.

## Where to Go Next

- Read `README.md` for the architecture and current readiness posture.
- Open `docs/README.md` for the documentation index.
- Inspect `GET /v1/openapi.json` for the live route contract.
- Use `backend/runtime/main.kujo` as the canonical server entrypoint.
- Use `scripts/run-release-gate.sh` as the final repository validation path.

The result is a content platform with a deliberately small boundary: Kujo CMS manages and delivers content; your frontend turns that content into whatever experience you want to build.
