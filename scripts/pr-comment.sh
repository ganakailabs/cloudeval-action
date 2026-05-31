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

# scripts/run.sh already appends run metadata to SUMMARY_FILE. Keep the PR
# comment body focused and avoid repeating workflow/ref/SHA details twice.
meta_block=""

inner="${summary_text}${meta_block}"

if [[ "${PR_COMMENT_COLLAPSED:-true}" == "true" ]]; then
  body_main=$'<details open><summary><strong>CloudEval summary</strong></summary>\n\n'"${inner}"$'\n\n</details>'
else
  body_main="$inner"
fi

json_block=""
if [[ "${PR_COMMENT_JSON_EXCERPT:-false}" == "true" && -n "${JSON_PATH:-}" && -f "$JSON_PATH" ]]; then
  maxc="${PR_COMMENT_MAX_JSON_CHARS:-12000}"
  raw="$(cat "$JSON_PATH")"
  excerpt="$raw"
  if [[ "${#raw}" -gt "$maxc" ]]; then
    excerpt="${raw:0:maxc}"$'\n\n… _(truncated)_'
  fi
  json_block=$'\n\n<details><summary><strong>CLI JSON excerpt</strong></summary>\n\n```json\n'"${excerpt}"$'\n```\n\n</details>'
fi

BODY="${MARKER}

${body_main}${json_block}"

# github issue comment body max ~65536; leave headroom
max_body=60000
if [[ "${#BODY}" -gt "$max_body" ]]; then
  BODY="${BODY:0:$max_body}"$'\n\n… _(comment truncated for github size limit)_'
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

body_file="$(mktemp)"
trap 'rm -f "$tmp" "$body_file"' EXIT
printf '%s' "$BODY" >"$body_file"
jq -Rs '{body: .}' "$body_file" >"$tmp"

existing="$(
  gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate \
    --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- cloudeval-action -->"))) | .id' \
    | tail -n 1
)"

if [[ -n "${existing}" ]]; then
  gh api --method PATCH "repos/${REPO}/issues/comments/${existing}" --input "$tmp"
else
  gh api --method POST "repos/${REPO}/issues/${PR_NUMBER}/comments" --input "$tmp"
fi
