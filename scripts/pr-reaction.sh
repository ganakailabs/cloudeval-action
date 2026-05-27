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

delete_reaction_content() {
  local stale_content="$1"
  local ids

  ids="$(
    gh api \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "repos/${REPO}/issues/${PR_NUMBER}/reactions" \
      --jq ".[] | select(.content == \"${stale_content}\") | .id" \
      2>/dev/null || true
  )"

  if [[ -z "$ids" ]]; then
    return 0
  fi

  while IFS= read -r reaction_id; do
    [[ -z "$reaction_id" ]] && continue
    if ! gh api \
      --method DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "repos/${REPO}/issues/${PR_NUMBER}/reactions/${reaction_id}" >/dev/null; then
      echo "pr-reaction: failed to delete stale '${stale_content}' reaction ${reaction_id}; continuing" >&2
    else
      echo "pr-reaction: deleted stale '${stale_content}' reaction ${reaction_id}" >&2
    fi
  done <<< "$ids"
}

case "$content" in
  eyes)
    delete_reaction_content "+1"
    delete_reaction_content "-1"
    delete_reaction_content "confused"
    ;;
  +1)
    delete_reaction_content "-1"
    delete_reaction_content "confused"
    ;;
  -1|confused)
    delete_reaction_content "+1"
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
