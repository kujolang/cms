# WebMCP

Kujo CMS ships a WebMCP surface by default so compatible browser agents can work with a site's published content without a custom integration.

## Built-in surface

| Resource | Purpose |
| --- | --- |
| `/.well-known/kujo-webmcp.json` | Discovery manifest, tool schemas, security properties, and the copyable script tag |
| `/assets/js/kujo-webmcp.js` | Same-origin browser adapter that registers tools with `document.modelContext` |
| `/.well-known/kujo-site-index.json` | Paginated, bounded published-content index |
| `/v1/webmcp/tools` | Canonical public tool descriptors |
| `/v1/webmcp/site` | Site, navigation, and content-type information |
| `/v1/webmcp/search` | Bounded published-content search |
| `/v1/webmcp/content` | Bounded listing by content type and optional taxonomy labels |
| `/v1/webmcp/record` | Exact published record lookup by Kujo ID or same-origin URL |

The four browser tools are `get_site_info`, `search_site`, `list_content`, and `get_content`. All schemas reject unknown arguments and all descriptors declare read-only, untrusted-content annotations.

## Frontend installation

Server-rendered CMS frontends should include this tag once in the page shell:

```html
<script src="/assets/js/kujo-webmcp.js" data-kujo-webmcp data-kujo-webmcp-api="/v1/webmcp/" defer></script>
```

The CMS manifest publishes the current tag. A headless frontend must proxy these CMS routes onto its own origin because the adapter refuses cross-origin API targets. Browsers without WebMCP support ignore the adapter safely.

## Content and privacy boundary

The public surface queries published entries only. It returns bounded plain text plus explicit public fields: stable ID, entry ID, type, slug, URL, title, description, summary, language, dates, searchable status, and taxonomy labels. It never returns raw HTML, raw Markdown, arbitrary metadata, drafts, credentials, users, revision content, or connector configuration.

Entry metadata supports these controls:

- `webmcp_exclude: true` or `webmcp.exclude: true` removes the record from every WebMCP result.
- `search_exclude: true` or `webmcp.search_exclude: true` excludes search while preserving listing and exact retrieval.

`CMS_WEBMCP_ENABLED=false` disables every WebMCP route. Capacity controls are `CMS_WEBMCP_MAX_SCAN_RECORDS`, `CMS_WEBMCP_INDEX_PAGE_SIZE_MAX`, and `CMS_WEBMCP_SUMMARY_MAX_CHARS`. Scan limits are reported with `truncated: true`.

## Extension contract

The canonical registry is `webmcp_tool_registry()` in `backend/routes/webmcp.kujo`. To add a public tool:

1. Add a strict JSON Schema descriptor with read-only and untrusted-content annotations.
2. Add the equivalent registration and argument validation to the browser adapter source.
3. Add a same-origin GET handler under `/v1/webmcp`.
4. Reuse `webmcp_entry_allowed()` and `public_content_record()` when content is involved.
5. Bound query, response, and scan sizes; expose truncation explicitly.
6. Add contract and smoke coverage.

Do not add mutations, private content, administrative data, secrets, or privileged connectors to this public registry. Put those operations in the authenticated Abilities API, which provides permission checks, confirmations, and audit receipts.
