# CMS HOWTO (Beta Runbook)

This guide is written for people who are new to Kujo and new to this CMS repository.

If you follow this document from top to bottom, you will be able to:

- Start and stop the CMS server reliably
- Use each major API piece (content types, entries, taxonomies, media, menus, plugins, themes, auth)
- Run the full beta-readiness validation suite
- Hand the API and data layer off to dashboard/frontend work with confidence

## 1) What This Repository Is

This project is an API-first CMS backend implemented in Kujo with SQLite storage.

Main runtime entrypoint:

- `main.kujo`

Core local modules used by the runtime:

- `config.kujo`
- `database.kujo`
- `migrations.kujo`
- `http.kujo`
- `auth.kujo`
- `delivery.kujo`
- `content_types.kujo`
- `taxonomies.kujo`
- `entries.kujo`
- `media.kujo`
- `menus.kujo`
- `plugins.kujo`
- `themes.kujo`
- `authz.kujo`

## 2) Prerequisites

You need:

- A Kujo runtime binary
- Bash + curl
- Node.js (used by integration scripts for JSON extraction)

### Build Kujo runtime (if you do not already have it)

```bash
cd /path/to/kujo
cargo build --bin kujo
```

This guide assumes your runtime is at:

```bash
/path/to/kujo/target/debug/kujo
```

## 3) Initial Setup

From the CMS repository root:

```bash
cd /path/to/cms
cp .env.example .env
```

Minimum `.env` values to verify:

- `CMS_API_HOST=127.0.0.1`
- `CMS_API_PORT=4200`
- `CMS_SITE_URL=http://127.0.0.1:4200`
- `CMS_DB_PATH=cms.db`
- `CMS_API_TOKEN=change-me-in-production`
- `CMS_ENV=development`

## 4) Turn CMS Server On

### Foreground mode (recommended while developing)

```bash
cd /path/to/cms
/path/to/kujo/target/debug/kujo run --interpreter main.kujo
```

Expected startup output includes:

- `CMS API`
- `Server: http://127.0.0.1:<port>` when `CMS_API_HOST=127.0.0.1`
- `Press Ctrl+C to stop`

### Background mode (if you want your shell back)

```bash
cd /path/to/cms
mkdir -p results
CMS_API_PORT=4200 \
CMS_API_HOST=127.0.0.1 \
CMS_SITE_URL=http://127.0.0.1:4200 \
CMS_DB_PATH=results/dev_4200.db \
CMS_API_TOKEN=change-me-in-production \
/path/to/kujo/target/debug/kujo run --interpreter main.kujo \
  > results/dev_server_4200.log 2>&1 &
echo $! > results/dev_server_4200.pid
```

## 5) Verify Server Is Running

```bash
curl -sS http://127.0.0.1:4200/health
curl -sS http://127.0.0.1:4200/v1
```

You should see HTTP 200 payloads and API capability metadata.

## 6) Turn CMS Server Off

### If running in foreground

Press `Ctrl+C`.

### If running in background with PID file

```bash
cd /path/to/cms
kill "$(cat results/dev_server_4200.pid)"
rm -f results/dev_server_4200.pid
```

### If port is stuck/in use

```bash
lsof -nP -iTCP:4200 -sTCP:LISTEN
kill <PID>
```

Use this when an old process prevents startup with `Address already in use`.

## 7) Auth Header You Will Reuse

Most write endpoints require bearer auth.

```bash
export CMS_TOKEN="change-me-in-production"
export CMS_BASE="http://127.0.0.1:4200"
```

Header pattern:

```bash
-H "Authorization: Bearer ${CMS_TOKEN}"
```

## 8) Use Each API Piece (Step-by-Step)

The examples below are intentionally practical and minimal.

## 8.1 Core + Delivery

```bash
curl -sS "${CMS_BASE}/"
curl -sS "${CMS_BASE}/health"
curl -sS "${CMS_BASE}/v1"
curl -sS "${CMS_BASE}/robots.txt"
curl -sS "${CMS_BASE}/.well-known/security.txt"
curl -sS "${CMS_BASE}/sitemap.xml"
curl -sS "${CMS_BASE}/rss.xml"
curl -sS "${CMS_BASE}/llms.txt"
```

## 8.2 Content Types

Create:

```bash
curl -sS -X POST "${CMS_BASE}/v1/content-types" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"type_key":"news","label":"News","singular_label":"News Item"}'
```

List:

```bash
curl -sS "${CMS_BASE}/v1/content-types"
```

## 8.3 Taxonomies + Terms

Create taxonomy:

```bash
curl -sS -X POST "${CMS_BASE}/v1/taxonomies" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"taxonomy_key":"topic","label":"Topic","description":"Topic taxonomy"}'
```

Create term (replace `<taxonomy_id>`):

```bash
curl -sS -X POST "${CMS_BASE}/v1/taxonomies/<taxonomy_id>/terms" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Platform","slug":"platform"}'
```

## 8.4 Entries (CRUD, SEO, revisions, scheduling, locking)

Create entry:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"content_type_key":"news","title":"First Post","slug":"first-post","status":"published","body":"Hello API"}'
```

List entries with deterministic filters/sort:

```bash
curl -sS "${CMS_BASE}/v1/entries?content_type=news&status=published&sort_by=created_at&sort_dir=desc"
```

Lookup by slug:

```bash
curl -sS "${CMS_BASE}/v1/entries/by-slug/news/first-post"
```

Entry SEO projection (replace `<entry_id>`):

```bash
curl -sS "${CMS_BASE}/v1/entries/<entry_id>/seo"
```

Create revision snapshot:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries/<entry_id>/revisions" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"note":"checkpoint before major edit"}'
```

List revisions:

```bash
curl -sS "${CMS_BASE}/v1/entries/<entry_id>/revisions"
```

Restore a revision (replace `<revision_id>`):

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries/<entry_id>/revisions/<revision_id>/restore" \
  -H "Authorization: Bearer ${CMS_TOKEN}"
```

Run scheduler:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entries/scheduler/run" \
  -H "Authorization: Bearer ${CMS_TOKEN}"
```

Acquire lock:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entry-locks/acquire" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "X-Lock-Session: editor-a" \
  -H "Content-Type: application/json" \
  --data '{"entry_id":<entry_id>,"session_id":"editor-a","note":"editing"}'
```

Lock state:

```bash
curl -sS "${CMS_BASE}/v1/entry-locks/state?entry_id=<entry_id>"
```

Release lock:

```bash
curl -sS -X POST "${CMS_BASE}/v1/entry-locks/release" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "X-Lock-Session: editor-a" \
  -H "Content-Type: application/json" \
  --data '{"entry_id":<entry_id>,"session_id":"editor-a"}'
```

## 8.5 Media

```bash
curl -sS -X POST "${CMS_BASE}/v1/media" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"url":"https://example.com/image.jpg","mime_type":"image/jpeg","alt_text":"Example image"}'

curl -sS "${CMS_BASE}/v1/media"
```

## 8.6 Menus + Menu Items

```bash
curl -sS -X POST "${CMS_BASE}/v1/menus" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Main Navigation","location":"primary"}'

curl -sS -X POST "${CMS_BASE}/v1/menus/<menu_id>/items" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"label":"Home","item_type":"custom","target":"/","sort_order":1}'

curl -sS "${CMS_BASE}/v1/menus/<menu_id>/items"
```

## 8.7 Plugins + Hooks

```bash
curl -sS -X POST "${CMS_BASE}/v1/plugins" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Example Plugin","slug":"example-plugin","version":"1.0.0","enabled":true}'

curl -sS -X POST "${CMS_BASE}/v1/plugins/<plugin_id>/hooks" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"hook_name":"publish","handler_url":"https://example.com/hook","shared_secret":"secret"}'

curl -sS "${CMS_BASE}/v1/plugins/<plugin_id>/hooks"
```

## 8.8 Themes

```bash
curl -sS -X POST "${CMS_BASE}/v1/themes" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Default Theme","slug":"default-theme","version":"1.0.0","is_active":false}'

curl -sS -X POST "${CMS_BASE}/v1/themes/<theme_id>/activate" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{}'

curl -sS "${CMS_BASE}/v1/themes/active"
```

## 8.9 Auth (Roles + API Tokens)

```bash
curl -sS -X POST "${CMS_BASE}/v1/auth/roles" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Editor","permissions":["entries:write","entries:read","taxonomies:read"]}'

curl -sS -X POST "${CMS_BASE}/v1/auth/tokens" \
  -H "Authorization: Bearer ${CMS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"label":"dashboard-token","role_id":1}'

curl -sS "${CMS_BASE}/v1/auth/tokens" \
  -H "Authorization: Bearer ${CMS_TOKEN}"
```

## 9) Full Beta-Readiness Validation Commands

Use an explicit runtime binary to avoid drift:

```bash
export KUJO_BIN=/path/to/kujo/target/debug/kujo
cd /path/to/cms
```

Run all gates:

```bash
"${KUJO_BIN}" test-run tests/cms_contract_tests.kujo
CMS_TEST_PORT=49390 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage1.sh
CMS_TEST_PORT=49391 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage2-round1.sh
CMS_TEST_PORT=49392 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage2-round2-sitemaps.sh
CMS_TEST_PORT=49393 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage2-round2-feeds.sh
CMS_TEST_PORT=49394 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage2-round2-cursor.sh
CMS_TEST_PORT=49395 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage2-round2-projection.sh
CMS_TEST_PORT=49396 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage3-round1-revisions.sh
CMS_TEST_PORT=49397 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage3-round2-rollback.sh
CMS_TEST_PORT=49398 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage3-round3-scheduler.sh
CMS_TEST_PORT=49399 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-stage3-round3-locking.sh
CMS_SMOKE_PORT=49400 KUJO_BIN="${KUJO_BIN}" bash scripts/smoke-api.sh
CMS_SECURITY_TEST_PORT_BASE=49410 KUJO_BIN="${KUJO_BIN}" bash scripts/integration-enterprise-security.sh
CMS_PERF_PORT=49420 CMS_PERF_RUNS=5 KUJO_BIN="${KUJO_BIN}" bash scripts/perf-baseline.sh
```

Perf report output:

- `results/perf_baseline_latest.json`

You can also run all gates with one command:

```bash
cd /path/to/cms
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/run-release-gate.sh
```

If you want to skip perf in a fast CI-style pass:

```bash
cd /path/to/cms
CMS_GATE_RUN_PERF=false KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/run-release-gate.sh
```

## 10) Important Operational Notes

- If you see `Address already in use`, stop the old process or choose a different port.
- Integration scripts create temporary DB files in `results/` and clean most of them after each run.
- A production deployment should not use `CMS_API_TOKEN=change-me-in-production`.
- In production, use:
  - `CMS_ENV=production`
  - `CMS_ALLOW_BOOTSTRAP_TOKEN=false` after bootstrap
  - `CMS_ENFORCE_BOOTSTRAP_TOKEN_ROTATION=true`
  - A real CORS origin instead of `*`

## 11) Enterprise DB Operations

Run migration safety validation (fresh boot + restart idempotence):

```bash
cd /path/to/cms
KUJO_BIN=/path/to/kujo/target/debug/kujo bash scripts/migration-safety.sh
```

Create a backup:

```bash
cd /path/to/cms
bash scripts/backup-db.sh ./cms.db
```

Restore a backup:

```bash
cd /path/to/cms
bash scripts/restore-db.sh ./results/backups/<backup-file>.bak ./cms.db --force
```

Notes:

- Stop the running CMS server before backup/restore.
- Backup files are timestamped and include a manifest.
- Restore refuses to overwrite existing DBs unless `--force` is provided.

## 12) UI/UX Handoff Checklist

Use this list before starting admin dashboard and frontend work:

- API contract tests passing
- Stage 1/2/3 integration scripts passing
- Smoke script passing
- Enterprise security integration passing
- Baseline perf report generated
- Stable local runbook documented (this file)

When all items are green, you can begin dashboard and frontend implementation with a stable backend foundation.
