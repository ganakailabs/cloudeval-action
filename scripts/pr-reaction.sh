#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "pr-reaction: GITHUB_TOKEN not set; skipping" >&2
  exit 0
fi

if [[ -z "${PR_NUMBER:-}" ]] || [[ -z "${REPO:-}" ]]; then
  echo "pr-reaction: PR_NUMBER or REPO not set; skipping" >&2
  exit 0
fi

content="${REACTION:-}"
if [[ -z "$content" ]]; then
  case "${RESULT:-unknown}" in
    running)
      content="eyes"
      ;;
    pass)
      content="+1"
      ;;
    fail)
      content="confused"
      ;;
    *)
      content="+1"
      ;;
  esac
fi

case "$content" in
  +1|-1|laugh|confused|heart|hooray|rocket|eyes)
    ;;
  *)
    echo "pr-reaction: unsupported reaction '$content'; skipping" >&2
    exit 0
    ;;
esac

if ! gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${REPO}/issues/${PR_NUMBER}/reactions" \
  -f "content=${content}" >/dev/null; then
  echo "pr-reaction: failed to add '${content}' reaction; continuing" >&2
fi
