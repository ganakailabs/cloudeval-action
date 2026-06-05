#!/usr/bin/env bash
set -euo pipefail

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

try_cloudeval_app_comment() {
  if [[ -z "${CLOUDEVAL_ACCESS_KEY:-}" || -z "${INPUT_PROJECT_ID:-}" ]]; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  local api_base="${INPUT_BASE_URL:-${CLOUDEVAL_BASE_URL:-https://cloudeval.ai/api/proxy/v1}}"
  api_base="${api_base%/}"
  local payload_file response_file status_code idempotency_key
  payload_file="$(mktemp)"
  response_file="$(mktemp)"
  idempotency_key="cloudeval-pr-comment-${GITHUB_RUN_ID:-run}-${PR_NUMBER}"
  jq -n \
    --arg repo "$REPO" \
    --argjson pull_request_number "$PR_NUMBER" \
    --arg body "$BODY" \
    --arg marker "$MARKER" \
    '{
      repo_full_name: $repo,
      pull_request_number: $pull_request_number,
      body: $body,
      marker: $marker
    }' >"$payload_file"
  status_code="$(
    curl -sS \
      -o "$response_file" \
      -w '%{http_code}' \
      -X POST "${api_base}/projects/${INPUT_PROJECT_ID}/github/pr-comment" \
      -H "Authorization: Bearer ${CLOUDEVAL_ACCESS_KEY}" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: ${idempotency_key}" \
      --data-binary "@${payload_file}" || true
  )"
  rm -f "$payload_file"
  if [[ "$status_code" =~ ^2 ]]; then
    echo "pr-comment: posted via CloudEval GitHub App"
    rm -f "$response_file"
    return 0
  fi
  local preview
  preview="$(head -c 300 "$response_file" 2>/dev/null | tr -d '\r' || true)"
  rm -f "$response_file"
  echo "pr-comment: CloudEval GitHub App posting unavailable (${status_code}); falling back to github-actions[bot]. ${preview}" >&2
  return 1
}

if try_cloudeval_app_comment; then
  exit 0
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "pr-comment: GITHUB_TOKEN not set; skipping github-actions[bot] fallback" >&2
  exit 0
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
