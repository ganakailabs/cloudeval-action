#!/usr/bin/env bash
# cloudeval github action — run cloudeval cli and set github outputs
set -euo pipefail

OUT_DIR="${RUNNER_TEMP:-/tmp}/cloudeval-action-$$"
mkdir -p "$OUT_DIR"
JSON_FILE="$OUT_DIR/cloudeval-out.json"
SUMMARY_FILE="$OUT_DIR/summary.md"
ARTIFACT_DIR="$OUT_DIR/artifact-staging"
mkdir -p "$ARTIFACT_DIR"

write_outputs() {
  local result="$1"
  local score="${2:-}"
  local report_path="${3:-}"
  local summary_md
  summary_md="$(cat "$SUMMARY_FILE")"

  {
    echo "result=$result"
    echo "json_path=$JSON_FILE"
    echo "report_path=$report_path"
    echo "summary_file=$SUMMARY_FILE"
    [[ -n "$score" ]] && echo "score=$score"
    echo "summary_markdown<<CEV_SUMMARY_EOF"
    echo "$summary_md"
    echo "CEV_SUMMARY_EOF"
    echo "artifact_path=$ARTIFACT_DIR"
  } >>"${GITHUB_OUTPUT:?}"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## CloudEval"
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
    echo "### CloudEval failed"
    echo ""
    echo "$msg"
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs fail "" ""
  exit 1
}

MODE_RAW="${INPUT_MODE:-ask}"
MODE="$(printf '%s' "$MODE_RAW" | tr '[:upper:]' '[:lower:]')"

cd "${INPUT_WORKING_DIRECTORY:-.}"

BASE_ARGS=(--non-interactive --format json)
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
}

download_reports() {
  local out_rel="$1"
  mkdir -p "$out_rel"
  local dl=(reports download --project "${INPUT_PROJECT_ID}" --type "${INPUT_REPORTS_TYPE:-all}" --output "$out_rel" --non-interactive --format json)
  if [[ -n "${INPUT_BASE_URL:-}" ]]; then
    dl+=(--base-url "$INPUT_BASE_URL")
  fi
  cloudeval "${dl[@]}"
}

run_reports_flow() {
  local title="$1"
  cloudeval reports run --type "${INPUT_REPORTS_TYPE:-all}" "${BASE_ARGS[@]}" | tee "$JSON_FILE"
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
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs pass "" "$report_path_out"
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
    summarize_fail "gate jq expression '${jq_expr}' did not produce a numeric value from cli json"
  fi

  local score="$raw"
  if awk -v v="$score" -v t="$threshold" 'BEGIN { exit !(v + 0 >= t + 0) }'; then
    {
      echo "### CloudEval gate"
      echo ""
      echo "- **Extracted value:** ${score}"
      echo "- **Threshold:** ${threshold}"
      echo "- **Result:** pass"
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs pass "$score" ""
    exit 0
  fi

  {
    echo "### CloudEval gate failed"
    echo ""
    echo "- **Extracted value:** ${score}"
    echo "- **Minimum required:** ${threshold}"
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs fail "$score" ""
  exit 1
}

case "$MODE" in
ask)
  if [[ "$USE_AGENT" == true ]]; then
    if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
      summarize_fail "agent_task is required when using agent (agent_task set)"
    fi
    run_llm ""
  else
    if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
      summarize_fail "mode ask requires ask_prompt (or set agent_task for agent mode)"
    fi
    run_llm "${INPUT_ASK_PROMPT}"
  fi
  if [[ -n "${INPUT_GATE_THRESHOLD:-}" ]]; then
    apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
  fi
  {
    echo "### CloudEval ask"
    echo ""
    echo "Completed successfully."
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
      summarize_fail "mode gate with agent requires agent_task"
    fi
    run_llm ""
  else
    if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
      summarize_fail "mode gate requires ask_prompt (or agent_task)"
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
    echo "### CloudEval agent"
    echo ""
    echo "Completed successfully."
  } >"$SUMMARY_FILE"
  stage_artifacts
  write_outputs pass "" ""
  ;;

reports)
  if [[ -z "${INPUT_PROJECT_ID:-}" ]]; then
    summarize_fail "mode reports requires project_id"
  fi
  run_reports_flow "CloudEval reports"
  ;;

nightly)
  if [[ -n "${INPUT_PROJECT_ID:-}" ]]; then
    run_reports_flow "CloudEval nightly (reports)"
  else
    if [[ "$USE_AGENT" == true ]]; then
      if [[ -z "${INPUT_AGENT_TASK:-}" ]]; then
        summarize_fail "nightly ask/agent requires agent_task when using agent"
      fi
      run_llm ""
    else
      if [[ -z "${INPUT_ASK_PROMPT:-}" ]]; then
        summarize_fail "mode nightly without project_id requires ask_prompt or agent_task"
      fi
      run_llm "${INPUT_ASK_PROMPT}"
    fi
    if [[ -n "${INPUT_GATE_THRESHOLD:-}" ]]; then
      apply_gate_if_needed "${INPUT_GATE_THRESHOLD}"
    fi
    {
      echo "### CloudEval nightly (ask)"
      echo ""
      echo "Scheduled check completed."
    } >"$SUMMARY_FILE"
    stage_artifacts
    write_outputs pass "" ""
  fi
  ;;

*)
  summarize_fail "unknown mode: ${MODE_RAW} (use ask, gate, agent, reports, nightly)"
  ;;
esac
