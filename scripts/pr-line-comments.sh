#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PR_NUMBER:-}" || -z "${REPO:-}" ]]; then
  echo "pr-line-comments: PR_NUMBER or REPO not set; skipping" >&2
  exit 0
fi
if [[ -z "${JSON_PATH:-}" || ! -f "$JSON_PATH" ]]; then
  echo "pr-line-comments: review JSON not found; skipping" >&2
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "pr-line-comments: jq unavailable; skipping" >&2
  exit 0
fi

MARKER="<!-- cloudeval-line-comment -->"
limit="${INPUT_PR_LINE_COMMENT_LIMIT:-5}"
if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
  limit=5
fi
if [[ "$limit" -lt 1 ]]; then
  echo "pr-line-comments: limit is 0; skipping"
  exit 0
fi

annotations_json="$(
  jq -c --argjson limit "$limit" '
    (.data // .).github.checks.annotations // []
    | [
        .[]
        | select((((.raw_details // "") | tostring) | contains("gate_summary")) | not)
        | select((.annotation_level // "notice") != "notice")
      ]
    | .[0:$limit]
  ' "$JSON_PATH"
)"

annotation_count="$(jq 'length' <<<"$annotations_json")"

post_with_cloudeval_app() {
  if [[ -z "${CLOUDEVAL_ACCESS_KEY:-}" || -z "${INPUT_PROJECT_ID:-}" || -z "${GITHUB_HEAD_SHA:-}" ]]; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "pr-line-comments: curl unavailable for Cloudeval GitHub App comments" >&2
    return 2
  fi

  local api_base="${INPUT_BASE_URL:-${CLOUDEVAL_BASE_URL:-https://cloudeval.ai/api/proxy/v1}}"
  api_base="${api_base%/}"
  local endpoint="${api_base}/projects/${INPUT_PROJECT_ID}/github/pr-line-comments"
  local payload_file
  local response_file
  payload_file="$(mktemp)"
  response_file="$(mktemp)"

  jq -n \
    --arg repo_full_name "$REPO" \
    --arg head_sha "$GITHUB_HEAD_SHA" \
    --arg marker "$MARKER" \
    --argjson pull_request_number "$PR_NUMBER" \
    --argjson comments "$annotations_json" \
    '{
      repo_full_name: $repo_full_name,
      pull_request_number: $pull_request_number,
      head_sha: $head_sha,
      marker: $marker,
      comments: $comments
    }' >"$payload_file"

  if ! curl -fsS \
    --request POST \
    --url "$endpoint" \
    --header "Authorization: Bearer ${CLOUDEVAL_ACCESS_KEY}" \
    --header "Content-Type: application/json" \
    --data @"$payload_file" >"$response_file"; then
    rm -f "$payload_file" "$response_file"
    return 2
  fi

  local posted
  posted="$(jq -r '.posted_count // (.comments | length) // 0' "$response_file")"
  rm -f "$payload_file" "$response_file"
  echo "pr-line-comments: posted ${posted} line comment(s) via Cloudeval GitHub App"
  return 0
}

if [[ -n "${CLOUDEVAL_ACCESS_KEY:-}" && -n "${INPUT_PROJECT_ID:-}" ]]; then
  if post_with_cloudeval_app; then
    exit 0
  fi
  echo "pr-line-comments: Cloudeval GitHub App comment endpoint failed; not posting fallback line comments" >&2
  exit 0
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "pr-line-comments: GITHUB_TOKEN not set; skipping" >&2
  exit 0
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "pr-line-comments: gh unavailable; skipping" >&2
  exit 0
fi

delete_stale_line_comments() {
  local ids
  ids="$(
    gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --paginate \
      --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- cloudeval-line-comment -->"))) | .id' \
      || true
  )"
  if [[ -z "$ids" ]]; then
    return 0
  fi

  while IFS= read -r comment_id; do
    [[ -z "$comment_id" ]] && continue
    gh api --method DELETE "repos/${REPO}/pulls/comments/${comment_id}" >/dev/null || true
  done <<<"$ids"
}

format_body() {
  local title="$1"
  local message="$2"
  if [[ "${#message}" -gt 1400 ]]; then
    message="${message:0:1400}..."
  fi
  printf '%s\n\n**%s**\n\n%s\n\nSee the Cloudeval PR summary for full report links and drilldowns.' \
    "$MARKER" \
    "$title" \
    "$message"
}

delete_stale_line_comments

if [[ "$annotation_count" -lt 1 ]]; then
  echo "pr-line-comments: no source-mapped line comments to post"
  exit 0
fi

posted=0
while IFS= read -r annotation; do
  [[ -z "$annotation" ]] && continue
  if [[ "$posted" -ge "$limit" ]]; then
    break
  fi

  path="$(jq -r '.path // empty' <<<"$annotation")"
  line="$(jq -r '.start_line // .line // 1' <<<"$annotation")"
  level="$(jq -r '.annotation_level // "notice"' <<<"$annotation")"
  title="$(jq -r '.title // "Cloudeval review finding"' <<<"$annotation")"
  message="$(jq -r '.message // "Cloudeval reported a review finding for this line."' <<<"$annotation")"

  [[ -n "$path" ]] || continue
  [[ "$line" =~ ^[0-9]+$ ]] || line=1
  tmp="$(mktemp)"
  body="$(format_body "$title" "$message")"
  jq -n \
    --arg body "$body" \
    --arg path "$path" \
    --argjson line "$line" \
    --arg commit_id "${GITHUB_HEAD_SHA:-}" \
    '{
      body: $body,
      path: $path,
      line: $line,
      side: "RIGHT"
    }
    | if $commit_id != "" then . + {commit_id: $commit_id} else . end' >"$tmp"

  if gh api --method POST "repos/${REPO}/pulls/${PR_NUMBER}/comments" --input "$tmp" >/dev/null; then
    posted=$((posted + 1))
  else
    echo "pr-line-comments: failed to comment on ${path}:${line}; continuing" >&2
  fi
  rm -f "$tmp"
done < <(
  jq -c '.[]' <<<"$annotations_json"
)

echo "pr-line-comments: posted ${posted} line comment(s)"
