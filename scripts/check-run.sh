#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${INPUT_PROJECT_ID:-}" || -z "${CLOUDEVAL_ACCESS_KEY:-}" ]]; then
  echo "check-run: project_id or access_key not set; skipping" >&2
  exit 0
fi
if [[ -z "${JSON_PATH:-}" || ! -f "$JSON_PATH" ]]; then
  echo "check-run: review JSON not found; skipping" >&2
  exit 0
fi
if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "check-run: jq or curl unavailable; skipping" >&2
  exit 0
fi

api_base="${INPUT_BASE_URL:-${CLOUDEVAL_BASE_URL:-https://cloudeval.ai/api/proxy/v1}}"
api_base="${api_base%/}"

repo="${REPO:-${GITHUB_REPOSITORY:-}}"
if [[ -z "$repo" ]]; then
  echo "check-run: repository not set; skipping" >&2
  exit 0
fi

run_url=""
if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

gate_status="$(jq -r '(.data // .).gate.status // empty' "$JSON_PATH")"
case "${gate_status:-${RESULT:-}}" in
  fail | failed)
    conclusion="failure"
    ;;
  warn | warning)
    conclusion="neutral"
    ;;
  pass | passed | success)
    conclusion="success"
    ;;
  *)
    conclusion="neutral"
    ;;
esac

summary_preview="Cloudeval review completed."
markdown_file="/dev/null"
if [[ -n "${SUMMARY_FILE:-}" && -f "$SUMMARY_FILE" ]]; then
  markdown_file="$SUMMARY_FILE"
  summary_preview="$(
    awk '
      /^<!--/ { next }
      /^[[:space:]]*$/ { next }
      {
        gsub(/[[:space:]][[:space:]]+/, " ")
        printf "%s ", $0
        count += 1
        if (count >= 8) {
          exit
        }
      }
    ' "$SUMMARY_FILE"
  )"
  summary_preview="${summary_preview:0:900}"
fi

payload_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f "$payload_file" "$response_file"' EXIT

jq -n \
  --slurpfile review "$JSON_PATH" \
  --arg repo "$repo" \
  --arg name "${INPUT_GITHUB_CHECK_NAME:-Cloudeval}" \
  --arg sha "${GITHUB_SHA:-}" \
  --arg conclusion "$conclusion" \
  --arg run_url "$run_url" \
  --arg project_id "$INPUT_PROJECT_ID" \
  --arg summary "$summary_preview" \
  --rawfile markdown "$markdown_file" \
  '
  ($review[0].data // $review[0]) as $d |
  {
    repo_full_name: $repo,
    name: ($d.github.checks.name // $name),
    head_sha: ($d.commitSha // $sha),
    status: "completed",
    conclusion: $conclusion,
    external_id: ("cloudeval-" + $project_id + "-" + (($d.commitSha // $sha) | tostring)),
    output: {
      title: "Cloudeval infrastructure review",
      summary: $summary,
      text: ($markdown[0:60000])
    },
    annotations: ($d.github.checks.annotations // [])
  }
  | if $run_url != "" then . + {details_url: $run_url} else . end
  ' >"$payload_file"

if ! jq -e '.head_sha | length >= 7' "$payload_file" >/dev/null; then
  echo "check-run: head SHA unavailable; skipping" >&2
  exit 0
fi

status_code="$(
  curl -sS \
    -o "$response_file" \
    -w '%{http_code}' \
    -X POST "${api_base}/projects/${INPUT_PROJECT_ID}/github/check-run" \
    -H "Authorization: Bearer ${CLOUDEVAL_ACCESS_KEY}" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: cloudeval-check-run-${GITHUB_RUN_ID:-run}-${INPUT_PROJECT_ID}" \
    --data-binary "@${payload_file}" || true
)"

if [[ "$status_code" =~ ^2 ]]; then
  check_url="$(jq -r '.html_url // empty' "$response_file" 2>/dev/null || true)"
  echo "check-run: posted Cloudeval Check Run"
  if [[ -n "${GITHUB_OUTPUT:-}" && -n "$check_url" ]]; then
    echo "check_run_url=$check_url" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

preview="$(head -c 300 "$response_file" 2>/dev/null | tr -d '\r' || true)"
echo "check-run: Cloudeval GitHub App check run unavailable (${status_code}); ${preview}" >&2
exit 0
