#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FORBIDDEN_TERM="word""press"

cd "${REPO_DIR}"

if rg -ni --hidden --glob '!.git/**' --glob '!node_modules/**' --glob '!results/**' "${FORBIDDEN_TERM}" .; then
  printf '%s\n' 'Brand isolation check failed: forbidden external product reference found in the working tree.' >&2
  exit 1
fi

if git log --all --format='%H%x09%s%n%b' | rg -ni "${FORBIDDEN_TERM}"; then
  printf '%s\n' 'Brand isolation check failed: forbidden external product reference found in commit messages.' >&2
  exit 1
fi

for commit in $(git rev-list --all); do
  if git grep -Iin "${FORBIDDEN_TERM}" "${commit}" -- >/dev/null 2>&1; then
    printf '%s\n' "Brand isolation check failed: forbidden external product reference found in reachable commit ${commit}." >&2
    exit 1
  fi
done

printf '%s\n' 'Brand isolation check passed.'
