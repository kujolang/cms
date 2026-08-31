# Hardening Kujo CMS

## Why we did it

Kujo CMS needed stronger boundaries around administration, credentials, idempotent writes, webhook delivery, background work, recovery, and production deployment. This evaluation asks whether the shipped `v1.1.0` release is empirically better than the commit immediately before that hardening cluster.

## What changed

Six contiguous commits added scoped administration, validated webhook egress, deliberate bootstrap setup, credential-scoped idempotency, race-safe worker/recovery operations, and production ingress requirements. The release then added a large feature set: SEO workflows, abilities, WebMCP, extensions, identity sessions, atomic content/media operations, and portable clients.

That sequencing matters. The final before/after comparison includes both hardening and 3,831 later feature insertions, so it measures the shipped product rather than a pure optimization patch.

## How we measured it

Both revisions ran on the same Intel Mac, Kujo runtime 1.0.0, interpreter mode, loopback network, generated SQLite data, and identical request paths. Two full passes reversed execution order. Because those passes revealed strong machine-load/order effects, the primary latency result came from five counterbalanced ABBA blocks: 10 process trials and 50 endpoint samples per revision.

Kujo Eval checked 11 explicit behaviors per revision. Raw samples, machine-readable results, Eval artifacts, and reproduction scripts are committed with the report.

## Before vs After

| Metric | Before | After | Change |
|---|---:|---:|---:|
| Kujo Eval checks | 10/11 | 11/11 | +1 |
| Unsafe production config | Started | Exited 1 | Fixed |
| Startup median | 1.203 s | 1.773 s | +47.4% slower |
| Startup RSS median | 86,366 KiB | 131,588 KiB | +52.4% |
| Health median | 110.5 ms | 120.5 ms | +9.1% slower |
| Health p95 | 160.4 ms | 154.4 ms | 3.7% lower |
| Entry-list median | 166.8 ms | 179.8 ms | +7.8% slower |
| Entry-list p95 | 259.5 ms | 209.8 ms | 19.2% lower |
| `/llms.txt` | 477 B | 477 B | unchanged |
| OpenAPI | 4,512 B | 9,209 B | +104.1% |

## Biggest improvements

The clearest improvement is operational safety. The old revision became healthy without trusted production ingress controls. The new revision exited with a focused error.

Tail latency and variance also improved. The 5,000-row entry-list p95 fell from 259.5 to 209.8 ms, while standard deviation fell from 30.0 to 16.4 ms. Throughput was higher for the new revision in both run orders, although the magnitude varied too much to publish one percentage.

## What surprised us

A baseline-first pass made the new revision look roughly three times faster on several endpoints. Reversing the order reversed much of that result. A counterbalanced run showed the defensible answer: the new median is slightly slower, while its tail is tighter. Without the reversed and paired runs, the headline would have been wrong.

## What did not improve

Cold startup and memory regressed. The new release loads more modules, routes, migrations, and features. Startup median rose 47.4%, and startup RSS rose 52.4%.

Agent-facing output did not shrink. `/llms.txt` stayed constant, but capabilities grew 36.8% and OpenAPI doubled with the feature surface. No LLM was used, so this study makes no token or cost-savings claim.

## What remains

The next evaluation should benchmark the end-of-hardening commit separately from the final feature-rich release. It should also run fixed real-agent tasks with one model/provider and record tokens, tool calls, retries, context growth, completion success, and cost.

## Reproducing the results

Use [`benchmarks/hardening/README.md`](../benchmarks/hardening/README.md). The full technical report is [`hardening-evaluation-2026-08-30.md`](hardening-evaluation-2026-08-30.md), and structured results are in [`evaluation-results.json`](../benchmarks/hardening/evaluation-results.json).

The conclusion is **PARTIALLY**: `v1.1.0` is demonstrably safer and more predictable at the tail, but it is not leaner and its median cold/request costs are higher.
