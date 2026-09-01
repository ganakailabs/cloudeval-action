#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${JSON_PATH:-}" || ! -f "$JSON_PATH" ]]; then
  echo "emit-annotations: review JSON not found; skipping" >&2
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "emit-annotations: jq unavailable; skipping" >&2
  exit 0
fi

escape_data() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\r'/'%0D'}"
  value="${value//$'\n'/'%0A'}"
  printf '%s' "$value"
}

escape_property() {
  local value
  value="$(escape_data "$1")"
  value="${value//','/'%2C'}"
  value="${value//':'/'%3A'}"
  printf '%s' "$value"
}

annotation_count=0
while IFS= read -r annotation; do
  [[ -z "$annotation" ]] && continue
  path="$(jq -r '.path // empty' <<<"$annotation")"
  line="$(jq -r '.start_line // .line // 1' <<<"$annotation")"
  end_line="$(jq -r '.end_line // .start_line // .line // 1' <<<"$annotation")"
  level="$(jq -r '.annotation_level // "notice"' <<<"$annotation")"
  title="$(jq -r '.title // "Cloudeval review finding"' <<<"$annotation")"
  message="$(jq -r '.message // "Cloudeval reported a review finding for this line."' <<<"$annotation")"

  [[ -z "$path" ]] && continue
  [[ "$line" =~ ^[0-9]+$ ]] || line=1
  [[ "$end_line" =~ ^[0-9]+$ ]] || end_line="$line"

  case "$level" in
    failure)
      command="error"
      ;;
    warning)
      command="warning"
      ;;
    *)
      command="notice"
      ;;
  esac

  printf '::%s file=%s,line=%s,endLine=%s,title=%s::%s\n' \
    "$command" \
    "$(escape_property "$path")" \
    "$line" \
    "$end_line" \
    "$(escape_property "$title")" \
    "$(escape_data "$message")"
  annotation_count=$((annotation_count + 1))
done < <(jq -c '(.data // .).github.checks.annotations // [] | .[]' "$JSON_PATH")

echo "emit-annotations: emitted ${annotation_count} GitHub workflow annotation(s)"
