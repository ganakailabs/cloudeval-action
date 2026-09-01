#!/usr/bin/env bash
# cloudeval github action — run cloudeval cli and set github outputs
set -euo pipefail

OUT_DIR="${RUNNER_TEMP:-/tmp}/cloudeval-action-$$"
mkdir -p "$OUT_DIR"
JSON_FILE="$OUT_DIR/cloudeval-out.json"
CLI_LOG_FILE="$OUT_DIR/cloudeval-cli.log"
SUMMARY_FILE="$OUT_DIR/summary.md"
ARTIFACT_DIR="$OUT_DIR/artifact-staging"
mkdir -p "$ARTIFACT_DIR"

run_url_value() {
  local base="${GITHUB_SERVER_URL:-https://github.com}"
  local repo="${GITHUB_REPOSITORY:-}"
  local rid="${GITHUB_RUN_ID:-}"
  if [[ -n "$repo" && -n "$rid" ]]; then
    printf '%s/%s/actions/runs/%s' "$base" "$repo" "$rid"
  else
    printf ''
  fi
}

append_run_metadata() {
  [[ "${INPUT_INCLUDE_RUN_METADATA:-true}" != "true" ]] && return 0
  local url
  url="$(run_url_value)"
  {
    echo ""
    echo "---"
    echo ""
    echo "| | |"
    echo "| --- | --- |"
    [[ -n "$url" ]] && echo "| **Workflow run** | $url |"
    if [[ "${INPUT_MODE:-}" == "review" ]]; then
      return 0
    fi
    [[ -n "${GITHUB_WORKFLOW:-}" ]] && echo "| **Workflow** | \`${GITHUB_WORKFLOW}\` |"
    [[ -n "${GITHUB_REF:-}" ]] && echo "| **Ref** | \`${GITHUB_REF}\` |"
    [[ -n "${GITHUB_SHA:-}" ]] && echo "| **SHA** | \`${GITHUB_SHA:0:7}\` |"
  }
  return 0
}

review_summary_has_run_metadata() {
  [[ "${INPUT_INCLUDE_RUN_METADATA:-true}" == "true" ]] || return 0
  [[ "${INPUT_MODE:-}" == "review" ]] || return 1
  [[ -f "$SUMMARY_FILE" ]] || return 1
  local url
  url="$(run_url_value)"
  [[ -n "$url" ]] || return 0
  grep -F "$url" "$SUMMARY_FILE" >/dev/null 2>&1 && return 0
  grep -F "img.shields.io/badge/Workflow-run" "$SUMMARY_FILE" >/dev/null 2>&1 && return 0
  grep -F "**Workflow run**" "$SUMMARY_FILE" >/dev/null 2>&1 && return 0
  return 1
}

append_answer_snippet() {
  local jq_expr="${INPUT_SUMMARY_ANSWER_JQ:-}"
  [[ -z "$jq_expr" ]] && return 0
  [[ ! -f "$JSON_FILE" ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  local snippet
  if ! snippet="$(jq -r "$jq_expr" "$JSON_FILE" 2>/dev/null)"; then
    return 0
  fi
  [[ -z "$snippet" || "$snippet" == "null" ]] && return 0
  {
    echo ""
    echo "#### Model output (excerpt)"
    echo ""
    echo '```text'
    echo "$snippet" | head -c 8000
    echo '```'
  }
}

validate_cli_json() {
  if [[ ! -s "$JSON_FILE" ]]; then
    summarize_fail "cloudeval produced no stdout json (empty file). Check auth, base_url, and flags."
  fi
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if ! jq -e . >/dev/null 2>&1 <"$JSON_FILE"; then
    preview="$(head -c 400 "$JSON_FILE" | tr -d '\r' | tr -cd '\11\12\15\40-\176' || true)"
    summarize_fail "cloudeval stdout is not valid JSON. First 400 chars (sanitized): ${preview}"
  fi
}

build_common_cli_flags() {
  COMMON_FLAGS=()
  if [[ "${INPUT_QUIET:-true}" == "true" ]]; then
    COMMON_FLAGS+=(--quiet)
  fi
  if [[ -n "${INPUT_PROGRESS:-}" && "${INPUT_PROGRESS}" != "default" ]]; then
    COMMON_FLAGS+=(--progress "$INPUT_PROGRESS")
  fi
  if [[ -n "${INPUT_MODEL:-}" ]]; then
    COMMON_FLAGS+=(--model "$INPUT_MODEL")
  fi
  if [[ -n "${INPUT_PROFILE:-}" ]]; then
    COMMON_FLAGS+=(--profile "$INPUT_PROFILE")
  fi
}

write_outputs() {
  local result="$1"
  local extracted="${2:-}"
  local report_path="${3:-}"
  local summary_md
  summary_md="$(cat "$SUMMARY_FILE")"
  local run_url
  run_url="$(run_url_value)"
  local sarif_path
  sarif_path="$(json_string '.data.outputs.sarif.file' || true)"

  {
    echo "result=$result"
    echo "json_path=$JSON_FILE"
    echo "report_path=$report_path"
    echo "summary_file=$SUMMARY_FILE"
    echo "run_url=$run_url"
    [[ -n "$extracted" ]] && echo "score=$extracted"
    [[ -n "$extracted" ]] && echo "extracted_value=$extracted"
    [[ -n "$sarif_path" ]] && echo "sarif_path=$sarif_path"
    echo "summary_markdown<<CEV_SUMMARY_EOF"
    echo "$summary_md"
    echo "CEV_SUMMARY_EOF"
    echo "artifact_path=$ARTIFACT_DIR"
  } >>"${GITHUB_OUTPUT:?}"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## ${INPUT_JOB_SUMMARY_TITLE:-Cloudeval}"
      echo ""
      echo "$summary_md"
    } >>"$GITHUB_STEP_SUMMARY"
  fi
}

stage_artifacts() {
  cp -f "$SUMMARY_FILE" "$ARTIFACT_DIR/summary.md" 2>/dev/null || true
  if [[ -f "$JSON_FILE" ]]; then
    cp -f "$JSON_FILE" "$ARTIFACT_DIR/cloudeval-out.json" || true
  fi
}

summarize_fail() {
  local msg="$1"
  {
    echo "### Cloudeval failed"
    echo ""
    echo "$msg"
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs fail "" ""
  exit 1
}

safe_file_preview() {
  local file="$1"
  local max_chars="${2:-1200}"
  [[ -s "$file" ]] || return 0
  head -c "$max_chars" "$file" | tr -d '\r' | tr -cd '\11\12\15\40-\176' || true
}

extract_error_field() {
  local field="$1"
  local file
  for file in "$JSON_FILE" "$CLI_LOG_FILE"; do
    [[ -s "$file" ]] || continue
    if command -v jq >/dev/null 2>&1; then
      local value
      value="$(jq -er ".${field} // .error.${field} // empty" "$file" 2>/dev/null | head -n 1 || true)"
      if [[ -n "$value" && "$value" != "null" ]]; then
        printf '%s' "$value"
        return 0
      fi
    fi
    local sed_expr
    sed_expr="s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
    value="$(sed -n "$sed_expr" "$file" | head -n 1 || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

combined_cli_preview() {
  {
    safe_file_preview "$JSON_FILE" 800
    echo ""
    safe_file_preview "$CLI_LOG_FILE" 1200
  } | sed '/^[[:space:]]*$/d' | head -c 1600
}

summarize_review_cli_failure() {
  local status="${1:-1}"
  local code message preview
  code="$(extract_error_field code || true)"
  message="$(extract_error_field message || true)"
  preview="$(combined_cli_preview || true)"

  if [[ "$code" == "credential_expired" ]] || printf '%s\n' "$preview" | grep -qi 'credential_expired\|access-key credential has expired'; then
    {
      echo "### Cloudeval failed"
      echo ""
      echo "Cloudeval review could not run because the **Cloudeval access key is expired**."
      echo ""
      echo "#### Next steps: Renew the repository secret"
      echo ""
      echo "1. In Cloudeval, open **Developer -> API & CLI access keys**."
      echo "2. Create a new **GitHub Actions CI** key scoped to this project."
      echo "3. Include the review/report capabilities your workflow uses. Add **github:comment** for Cloudeval App PR comments and **github:checks** for native Check Runs."
      echo "4. Update the repository secret **CLOUDEVAL_ACCESS_KEY** in GitHub."
      echo "5. Re-run this workflow."
      echo ""
      echo "Docs: [Renew an expired access key](https://docs.cloudeval.ai/guides/review/github-actions#renew-an-expired-access-key)"
      echo ""
      echo "#### Error"
      echo ""
      echo "- **Code:** \`${code:-credential_expired}\`"
      [[ -n "$message" ]] && echo "- **Message:** ${message}"
      append_run_metadata
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs fail "" ""
    exit "$status"
  fi

  if [[ "$code" == "credential_revoked" || "$code" == "invalid_credential" || "$code" == "unauthorized" ]] ||
    printf '%s\n' "$preview" | grep -qi 'invalid.*access key\|credential_revoked\|unauthorized'; then
    {
      echo "### Cloudeval failed"
      echo ""
      echo "Cloudeval review could not authenticate with the configured **CLOUDEVAL_ACCESS_KEY**."
      echo ""
      echo "#### Next steps"
      echo ""
      echo "1. Confirm the GitHub secret **CLOUDEVAL_ACCESS_KEY** is set on this repository or environment."
      echo "2. Create a new **GitHub Actions CI** key in Cloudeval if the current key was revoked or rotated."
      echo "3. Confirm the key is scoped to the target project and includes the capabilities used by this workflow."
      echo "4. Re-run this workflow."
      echo ""
      echo "Docs: [GitHub Actions authentication](https://docs.cloudeval.ai/guides/review/github-actions#renew-an-expired-access-key)"
      echo ""
      echo "#### Error"
      echo ""
      [[ -n "$code" ]] && echo "- **Code:** \`${code}\`"
      [[ -n "$message" ]] && echo "- **Message:** ${message}"
      append_run_metadata
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs fail "" ""
    exit "$status"
  fi

  {
    echo "### Cloudeval failed"
    echo ""
    echo "Cloudeval review did not produce a usable review summary."
    echo ""
    echo "#### Next steps"
    echo ""
    echo "1. Check that **CLOUDEVAL_ACCESS_KEY** and **CLOUDEVAL_PROJECT_ID** are set."
    echo "2. Confirm the project is linked to this GitHub repository and branch."
    echo "3. Confirm the runner has no unexpected local changes, or set **ignore_dirty: \"true\"** intentionally."
    echo "4. Re-run the workflow after correcting the configuration."
    echo ""
    echo "Docs: [Troubleshoot GitHub Actions review](https://docs.cloudeval.ai/guides/review/github-actions#troubleshooting)"
    if [[ -n "$preview" ]]; then
      echo ""
      echo "#### CLI output"
      echo ""
      echo '```text'
      echo "$preview"
      echo '```'
    fi
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs fail "" ""
  exit "$status"
}

MODE_RAW="${INPUT_MODE:-ask}"
MODE="$(printf '%s' "$MODE_RAW" | tr '[:upper:]' '[:lower:]')"

cd "${INPUT_WORKING_DIRECTORY:-.}"

BASE_ARGS=(--non-interactive --format json)
build_common_cli_flags
BASE_ARGS+=("${COMMON_FLAGS[@]}")

if [[ -n "${INPUT_BASE_URL:-}" ]]; then
  BASE_ARGS+=(--base-url "$INPUT_BASE_URL")
fi
if [[ -n "${INPUT_PROJECT_ID:-}" ]]; then
  BASE_ARGS+=(--project "$INPUT_PROJECT_ID")
fi

USE_AGENT=false
if [[ -n "${INPUT_AGENT_TASK:-}" ]]; then
  USE_AGENT=true
fi

run_llm() {
  local prompt="$1"
  if [[ "$USE_AGENT" == true ]]; then
    cloudeval agent "${INPUT_AGENT_TASK}" "${BASE_ARGS[@]}" | tee "$JSON_FILE"
  else
    cloudeval ask "$prompt" "${BASE_ARGS[@]}" | tee "$JSON_FILE"
  fi
  validate_cli_json
}

download_reports() {
  local out_rel="$1"
  mkdir -p "$out_rel"
  local dl=(reports download --project "${INPUT_PROJECT_ID}" --type "${INPUT_REPORTS_TYPE:-all}" --output "$out_rel" --non-interactive --format json)
  dl+=("${COMMON_FLAGS[@]}")
  if [[ -n "${INPUT_BASE_URL:-}" ]]; then
    dl+=(--base-url "$INPUT_BASE_URL")
  fi
  cloudeval "${dl[@]}"
}

run_reports_flow() {
  local title="$1"
  local run_args=(reports run --type "${INPUT_REPORTS_TYPE:-all}")
  run_args+=(--region "${INPUT_REPORTS_REGION:-eastus}")
  run_args+=(--currency "${INPUT_REPORTS_CURRENCY:-USD}")
  if [[ "${INPUT_REPORTS_WAIT:-false}" == "true" ]]; then
    run_args+=(--wait --poll-interval "${INPUT_REPORTS_POLL_INTERVAL_MS:-2500}")
  fi
  run_args+=("${BASE_ARGS[@]}")
  cloudeval "${run_args[@]}" | tee "$JSON_FILE"
  validate_cli_json

  local report_path_out=""
  if [[ "${INPUT_REPORTS_DOWNLOAD:-true}" == "true" ]]; then
    local out_rel="${INPUT_REPORTS_OUTPUT_DIR:-cloudeval-reports}"
    download_reports "$out_rel"
    report_path_out="$(pwd)/$out_rel"
    cp -r "$out_rel" "$ARTIFACT_DIR/reports" 2>/dev/null || true
  fi
  {
    echo "### ${title}"
    echo ""
    echo "- **Project:** \`${INPUT_PROJECT_ID}\`"
    echo "- **Type:** ${INPUT_REPORTS_TYPE:-all}"
    echo "- **Region:** ${INPUT_REPORTS_REGION:-eastus} · **Currency:** ${INPUT_REPORTS_CURRENCY:-USD}"
    if [[ "${INPUT_REPORTS_WAIT:-false}" == "true" ]]; then
      echo "- **Wait for jobs:** yes (poll ${INPUT_REPORTS_POLL_INTERVAL_MS:-2500} ms)"
    fi
    append_answer_snippet
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs pass "" "$report_path_out"
}

json_string() {
  local expr="$1"
  [[ ! -f "$JSON_FILE" ]] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r "$expr // empty" "$JSON_FILE" 2>/dev/null
}

run_review_flow() {
  local out_rel="${INPUT_REVIEW_OUTPUT_DIR:-cloudeval-review}"
  local review_args=(review)
  review_args+=("${BASE_ARGS[@]}")
  review_args+=(--output "$out_rel")
  if [[ -n "${INPUT_REPO:-}" ]]; then
    review_args+=(--repo "$INPUT_REPO")
  elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    review_args+=(--repo "$GITHUB_REPOSITORY")
  fi
  if [[ -n "${INPUT_REF:-}" ]]; then
    review_args+=(--ref "$INPUT_REF")
  elif [[ -n "${GITHUB_REF_NAME:-}" ]]; then
    review_args+=(--ref "$GITHUB_REF_NAME")
  fi
  if [[ -n "${INPUT_COMMIT_SHA:-}" ]]; then
    review_args+=(--commit-sha "$INPUT_COMMIT_SHA")
  elif [[ -n "${GITHUB_SHA:-}" ]]; then
    review_args+=(--commit-sha "$GITHUB_SHA")
  fi
  if [[ -n "${INPUT_SOURCE_ROOT:-}" ]]; then
    review_args+=(--source-root "$INPUT_SOURCE_ROOT")
  fi
  if [[ -n "${INPUT_CONFIG_PATH:-}" ]]; then
    review_args+=(--config "$INPUT_CONFIG_PATH")
  fi
  if [[ "${INPUT_IGNORE_DIRTY:-false}" == "true" ]]; then
    review_args+=(--ignore-dirty)
  fi
  if [[ "${INPUT_REVIEW_WAIT:-true}" != "true" ]]; then
    review_args+=(--no-wait)
  fi
  if [[ -n "${INPUT_REVIEW_WAIT_TIMEOUT_MS:-}" ]]; then
    review_args+=(--wait-timeout "$INPUT_REVIEW_WAIT_TIMEOUT_MS")
  fi
  if [[ -n "${INPUT_REVIEW_POLL_INTERVAL_MS:-}" ]]; then
    review_args+=(--poll-interval "$INPUT_REVIEW_POLL_INTERVAL_MS")
  fi
  if [[ "${INPUT_AI_SUMMARY:-true}" != "true" ]]; then
    review_args+=(--no-ai-summary)
  fi
  if [[ -n "${INPUT_AI_SUMMARY_MODE:-}" ]]; then
    review_args+=(--ai-summary-mode "$INPUT_AI_SUMMARY_MODE")
  fi
  if [[ -n "${INPUT_AI_SUMMARY_PROFILE:-}" ]]; then
    review_args+=(--ai-summary-profile "$INPUT_AI_SUMMARY_PROFILE")
  fi
  if [[ "${INPUT_GITHUB_CHECKS:-false}" == "true" ]]; then
    review_args+=(--github-checks)
  fi
  if [[ -n "${INPUT_CHECKS_ANNOTATION_LIMIT:-}" ]]; then
    review_args+=(--checks-annotation-limit "$INPUT_CHECKS_ANNOTATION_LIMIT")
  fi
  if [[ "${INPUT_CHECKS_ALL_FILES:-false}" == "true" ]]; then
    review_args+=(--checks-all-files)
  fi
  if [[ "${INPUT_CHECKS_INCLUDE_NOTICES:-false}" == "true" ]]; then
    review_args+=(--checks-include-notices)
  fi
  if [[ "${INPUT_SARIF:-false}" == "true" ]]; then
    review_args+=(--sarif)
  fi
  if [[ -n "${INPUT_SARIF_OUTPUT:-}" ]]; then
    review_args+=(--sarif-output "$INPUT_SARIF_OUTPUT")
  fi

  local status=0
  : >"$JSON_FILE"
  : >"$CLI_LOG_FILE"
  set +e
  cloudeval "${review_args[@]}" >"$JSON_FILE" 2>"$CLI_LOG_FILE"
  status=$?
  set -e
  [[ -s "$JSON_FILE" ]] && cat "$JSON_FILE"
  [[ -s "$CLI_LOG_FILE" ]] && cat "$CLI_LOG_FILE" >&2
  if [[ "$status" -ne 0 && ! -f "$out_rel/review.md" ]]; then
    summarize_review_cli_failure "$status"
  fi
  if [[ ! -s "$JSON_FILE" ]]; then
    summarize_review_cli_failure 1
  fi
  validate_cli_json

  if [[ -f "$out_rel/review.md" ]]; then
    cp "$out_rel/review.md" "$SUMMARY_FILE"
  else
    local summary
    summary="$(json_string '.data.summaryMarkdown' || true)"
    {
      echo "### Cloudeval review"
      echo ""
      if [[ -n "$summary" ]]; then
        echo "$summary"
      else
        echo "Review completed."
      fi
    } >"$SUMMARY_FILE"
  fi
  if ! review_summary_has_run_metadata; then
    append_run_metadata >>"$SUMMARY_FILE"
  fi
  cp -r "$out_rel" "$ARTIFACT_DIR/review" 2>/dev/null || true
  stage_artifacts
  local extracted
  extracted="$(json_string '.data.gate.overallScore' || true)"
  if [[ "$status" -eq 0 ]]; then
    write_outputs pass "$extracted" ""
    exit 0
  fi
  write_outputs fail "$extracted" ""
  exit "$status"
}

gate_compare() {
  local op_raw="$1"
  local v="$2"
  local t="$3"
  local op
  op="$(printf '%s' "$op_raw" | tr '[:upper:]' '[:lower:]')"
  case "$op" in
  ge | gte)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 >= tt + 0) }'
    ;;
  gt)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 > tt + 0) }'
    ;;
  le | lte)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 <= tt + 0) }'
    ;;
  lt)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 < tt + 0) }'
    ;;
  eq | =)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 == tt + 0) }'
    ;;
  ne | !=)
    awk -v vv="$v" -v tt="$t" 'BEGIN { exit !(vv + 0 != tt + 0) }'
    ;;
  *)
    summarize_fail "unknown gate_operator: ${op_raw} (use ge, gt, le, lte, lt, eq, ne)"
    ;;
  esac
}

apply_gate_if_needed() {
  local threshold="$1"
  [[ -z "$threshold" ]] && return 0

  if ! command -v jq >/dev/null 2>&1; then
    summarize_fail "gating requested but jq is not available on runner"
  fi

  local jq_expr="${INPUT_GATE_JQ:-.score}"
  local raw
  if ! raw="$(jq -e -r "(${jq_expr}) | tonumber" "$JSON_FILE" 2>/dev/null)"; then
    summarize_fail "gate_jq '${jq_expr}' did not yield a number in cli json"
  fi

  local score="$raw"
  local op="${INPUT_GATE_OPERATOR:-ge}"
  if gate_compare "$op" "$score" "$threshold"; then
    {
      echo "### Cloudeval gate"
      echo ""
      echo "- **Extracted value:** ${score}"
      echo "- **Operator:** \`${op}\` vs **threshold:** ${threshold}"
      echo "- **Result:** pass"
      append_answer_snippet
      append_run_metadata
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs pass "$score" ""
    exit 0
  fi

  {
    echo "### Cloudeval gate failed"
    echo ""
    echo "- **Extracted value:** ${score}"
    echo "- **Operator:** \`${op}\` vs **threshold:** ${threshold}"
    append_answer_snippet
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs fail "$score" ""
  exit 1
}

case "$MODE" in
ask)
  if [[ "$USE_AGENT" == true ]]; then
    if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
      summarize_fail "agent_task is required for agent mode"
    fi
    run_llm ""
  else
    if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
      summarize_fail "mode ask requires ask_prompt (or agent_task for agent)"
    fi
    run_llm "${INPUT_ASK_PROMPT}"
  fi
  if [[ -n "${INPUT_GATE_THRESHOLD:-}" ]]; then
    apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
  fi
  {
    echo "### Cloudeval ask"
    echo ""
    echo "Completed successfully."
    append_answer_snippet
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs pass "" ""
  ;;

gate)
  if [[ -z "${INPUT_GATE_THRESHOLD:-}" ]]; then
    summarize_fail "mode gate requires gate_threshold"
  fi
  if [[ "$USE_AGENT" == true ]]; then
    if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
      summarize_fail "gate with agent requires agent_task"
    fi
    run_llm ""
  else
    if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
      summarize_fail "gate requires ask_prompt or agent_task"
    fi
    run_llm "${INPUT_ASK_PROMPT}"
  fi
  apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
  ;;

agent)
  if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
    summarize_fail "mode agent requires agent_task"
  fi
  USE_AGENT=true
  run_llm ""
  if [[ -n "${INPUT_GATE_THRESHOLD:-}" ]]; then
    apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
  fi
  {
    echo "### Cloudeval agent"
    echo ""
    echo "Completed successfully."
    append_answer_snippet
    append_run_metadata
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs pass "" ""
  ;;

reports)
  if [[ -z "${INPUT_PROJECT_ID:-}" ]]; then
    summarize_fail "mode reports requires project_id"
  fi
  run_reports_flow "Cloudeval reports"
  ;;

review)
  run_review_flow
  ;;

nightly)
  if [[ -n "${INPUT_PROJECT_ID:-}" ]]; then
    run_reports_flow "Cloudeval nightly (reports)"
  else
    if [[ "$USE_AGENT" == true ]]; then
      if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
        summarize_fail "nightly requires agent_task when using agent"
      fi
      run_llm ""
    else
      if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
        summarize_fail "nightly without project_id requires ask_prompt or agent_task"
      fi
      run_llm "${INPUT_ASK_PROMPT}"
    fi
    if [[ -n "${INPUT_GATE_THRESHOLD:-}" ]]; then
      apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
    fi
    {
      echo "### Cloudeval nightly (ask)"
      echo ""
      echo "Scheduled check completed."
      append_answer_snippet
      append_run_metadata
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs pass "" ""
  fi
  ;;

*)
  summarize_fail "unknown mode: ${MODE_RAW} (use review, ask, gate, agent, reports, nightly)"
  ;;
esac
