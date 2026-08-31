# Hardening evaluation reproduction

This package compares CMS `1be7ec1f551dbecd964ce1404851276241838632` with `22570a510a0169bab2a6c3a4f3b92512f290ea57` using identical local workloads.

## Requirements

- Kujo runtime 1.0.0 at `$KUJO_BIN` or `~/.local/bin/kujo`
- Node.js 24+
- SQLite 3
- Git
- Kujo Eval checkout at `/Users/robertdevore/2026/Kujolang/kujo-repos/eval`, or adjust `EVAL_MAIN`

## Create immutable worktrees

```bash
eval_root="$(mktemp -d /tmp/cms-hardening-eval.XXXXXX)"
git worktree add --detach "$eval_root/baseline" 1be7ec1f551dbecd964ce1404851276241838632
git worktree add --detach "$eval_root/current" 22570a510a0169bab2a6c3a4f3b92512f290ea57
```

## Full pass, baseline first

```bash
node benchmarks/hardening/run-comparison.mjs \
  --baseline-dir="$eval_root/baseline" \
  --current-dir="$eval_root/current" \
  --output-dir="$(pwd)/benchmarks/hardening/raw" \
  --runs=20 --warmups=3 \
  --startup-runs=10 --startup-warmups=3 \
  --throughput-requests=50 \
  --order=baseline-first
```

## Full pass, current first

```bash
node benchmarks/hardening/run-comparison.mjs \
  --baseline-dir="$eval_root/baseline" \
  --current-dir="$eval_root/current" \
  --output-dir="$(pwd)/benchmarks/hardening/raw/pass2" \
  --runs=10 --warmups=3 \
  --startup-runs=10 --startup-warmups=3 \
  --throughput-requests=25 \
  --order=current-first
```

## Counterbalanced ABBA pass

```bash
node benchmarks/hardening/run-paired.mjs \
  --baseline-dir="$eval_root/baseline" \
  --current-dir="$eval_root/current" \
  --output-dir="$(pwd)/benchmarks/hardening/raw/paired" \
  --blocks=5 --requests-per-trial=5
```

The paired pass is authoritative for latency because it controls the order effect found in the full passes.

## Build machine-readable results

```bash
node benchmarks/hardening/build-results.mjs
jq '.headline_measurements, .regressions, .final_answer' benchmarks/hardening/evaluation-results.json
```

## Run Kujo Eval

```bash
EVAL_MAIN=/Users/robertdevore/2026/Kujolang/kujo-repos/eval/main.kujo

kujo run "$EVAL_MAIN" lint benchmarks/hardening/eval-baseline.json
kujo run "$EVAL_MAIN" lint benchmarks/hardening/eval-current.json

# Exit 1 is expected for BASELINE: it fails the production-safety criterion.
kujo run "$EVAL_MAIN" run benchmarks/hardening/eval-baseline.json \
  --output-dir benchmarks/hardening/eval-output/baseline --quiet

kujo run "$EVAL_MAIN" run benchmarks/hardening/eval-current.json \
  --output-dir benchmarks/hardening/eval-output/current --quiet
```

Use each `summary.json` for the machine pass rate. Eval v2.0.0's Markdown renderer displays `0%` for the 10/11 baseline result even though `summary.json` correctly records `90`; this known rendering defect is preserved in the evidence.

## Clean up worktrees

```bash
git worktree remove "$eval_root/baseline"
git worktree remove "$eval_root/current"
```

## Preserved evidence

- `raw/comparison-input.json`: 20-sample baseline-first pass
- `raw/pass2/comparison-input.json`: 10-sample current-first pass
- `raw/paired/paired-results.json`: counterbalanced process/request samples
- `raw/*-{capabilities,openapi,llms}.txt`: exact agent-facing payloads
- `evaluation-results.json`: normalized result and classifications
- `eval-output/`: Kujo Eval reports, summaries, manifests, and failure evidence

SHA-256 hashes for the three primary raw JSON files are embedded in `evaluation-results.json`.
