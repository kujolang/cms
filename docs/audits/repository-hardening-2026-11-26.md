# Kujo CMS hardening, 2026-11-26

Reviewed baseline `1ed30838c0a0b559e407ae852113527b83fd0460` across
configuration, HTTP admission, authentication, persistence, published
delivery, extension and media boundaries, workers, and release automation.

- JSON request admission now enforces bytes and matches the exact supported
  media types before parameters. The native request byte buffer supplies the
  length on runtimes that expose it. A compatibility fallback measures UTF-8
  when character count alone cannot determine the result.
- Compose captures the updated entry and terms inside the write transaction
  and returns the revision created by that operation. A SQLite fixture that
  appends a secondary revision previously delivered the secondary ID. The
  operation now binds the response and audit to its own revision.
- Exact public WebMCP retrieval queries the existing type and slug index and
  applies the published and exclusion rules to the selected record. With a
  100-row list cap, an eligible record beyond the cap now returns its full
  record and taxonomy. WebMCP reads the runtime's decoded query fields for
  encoded selectors, search phrases, and taxonomy filters.
- Browse and site-summary scans skip body loading and summary rendering.
  Taxonomy queries use bounded batches and surface query failures. The
  browser adapter resolves same-origin record URLs, rejects fetch redirects,
  and registers tools again when the page returns from the back-forward cache.

On the checksum-verified Kujo 1.2.2 macOS x64 runtime, a 700-record loopback
fixture reduced median exact lookup from 9,365.32 to 40.92 ms across five
paired requests. A separate three-pair listing measurement reduced the
median from 10,620.71 to 8,532.63 ms with byte-identical output. The listing
fixture also verified a taxonomy label in the second query batch. These are
local workload measurements.

The baseline and final full release gates passed using published Kujo 1.2.2
and the pinned Ability source. Verification included 40 final contract
tests, JavaScript and PHP clients, browser adapter and API smoke, auth and
tenancy, worker lifecycle, migrations, graceful restart, operational load,
and performance budgets. The 40 contract tests also passed on the local
1.10.0 build. The standalone startup harness passed on the published 1.2.0
minimum and CI's 1.2.2. The occupied-port fixture verified that the release
gate leaves unrelated listeners running. The existing deployment governance
record remains in the production-readiness plan.
