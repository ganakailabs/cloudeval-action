#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

legacy_refs="$({
  git -C "$repo_root" grep -n -I 'CloudEval' -- \
    ':!*.lock' \
    ':!scripts/test-brand-consistency.sh' || true
} | sed -E 's/\\n/ /g; s/\\t/ /g; s/CloudEval Live Sync Reader//g; s/X-CloudEval(-[A-Za-z0-9*-]*)?//g' \
  | rg '\bCloudEval\b' || true)"

if [[ -n "$legacy_refs" ]]; then
  printf '%s\n' "Visible product copy must use Cloudeval casing:" "$legacy_refs" >&2
  exit 1
fi

echo "brand consistency test passed"
