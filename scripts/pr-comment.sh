#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "pr-comment: GITHUB_TOKEN not set; skipping" >&2
  exit 0
fi

if [[ -z "${PR_NUMBER:-}" ]] || [[ -z "${REPO:-}" ]]; then
  echo "pr-comment: PR_NUMBER or REPO not set; skipping" >&2
  exit 0
fi

MARKER="<!-- cloudeval-action -->"
summary_text=""
if [[ -n "${SUMMARY_FILE:-}" && -f "$SUMMARY_FILE" ]]; then
  summary_text="$(cat "$SUMMARY_FILE")"
else
  summary_text="_(no summary)_"
fi

BODY="${MARKER}

${summary_text}

**Result:** \`${RESULT:-unknown}\`
"

existing="$(
  gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate \
    --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- cloudeval-action -->"))) | .id' \
    | tail -n 1
)"

if [[ -n "${existing}" ]]; then
  gh api --method PATCH "repos/${REPO}/issues/comments/${existing}" -f body="$BODY"
else
  gh api --method POST "repos/${REPO}/issues/${PR_NUMBER}/comments" -f body="$BODY"
fi
