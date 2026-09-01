#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh should not be called when Cloudeval App endpoint is available" >&2
exit 42
EOF
chmod +x "$BIN_DIR/gh"

cat >"$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

input_file=""
url=""
idempotency_key=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data|--data-binary|--data-raw)
      input_file="$2"
      shift 2
      ;;
    --header|-H)
      case "$2" in
        Idempotency-Key:*)
          idempotency_key="${2#Idempotency-Key: }"
          ;;
      esac
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$input_file" == @* ]]; then
  input_file="${input_file#@}"
fi
test -n "$input_file"
cp "$input_file" "$CAPTURE_DIR/app-payload.json"
printf '%s' "$url" >"$CAPTURE_DIR/app-url.txt"
printf '%s' "$idempotency_key" >"$CAPTURE_DIR/app-idempotency-key.txt"
posted_count="$(jq '.comments | length' "$input_file")"
printf '{"status":"posted","posted_count":%s,"deleted_count":1,"comments":[]}\n' "$posted_count"
EOF
chmod +x "$BIN_DIR/curl"

cat >"$TMP_DIR/review.json" <<'JSON'
{
  "data": {
    "github": {
      "checks": {
        "annotations": [
          {
            "path": "azuredeploy.json",
            "start_line": 30,
            "end_line": 30,
            "annotation_level": "failure",
            "title": "Storage account permits public access",
            "message": "Set allowBlobPublicAccess to false.",
            "raw_details": "local_iac_check · high"
          },
          {
            "path": "nested/database.json",
            "start_line": 12,
            "end_line": 12,
            "annotation_level": "warning",
            "title": "SQL public network access",
            "message": "Disable public network access for production SQL servers.",
            "raw_details": "local_iac_check · medium"
          },
          {
            "path": "nested/database.json",
            "start_line": 14,
            "annotation_level": "failure",
            "title": "Cloudeval gate failed",
            "message": "Gate evidence: overall score 48 is below 60.",
            "raw_details": "gate_summary · fail"
          }
        ]
      }
    }
  }
}
JSON

export PATH="$BIN_DIR:$PATH"
export CAPTURE_DIR="$TMP_DIR"
export JSON_PATH="$TMP_DIR/review.json"
export CLOUDEVAL_ACCESS_KEY="cev_mock"
unset INPUT_BASE_URL
unset CLOUDEVAL_BASE_URL
export INPUT_PROJECT_ID="project-123"
export PR_NUMBER="8"
export REPO="ganakailabs/example"
export GITHUB_HEAD_SHA="abcdef123456"
export GITHUB_RUN_ID="test-run"
export INPUT_PR_LINE_COMMENT_LIMIT="5"

bash "$ROOT_DIR/scripts/pr-line-comments.sh" >"$TMP_DIR/output.txt"

grep -F "https://cloudeval.ai/api/proxy/v1/projects/project-123/github/pr-line-comments" "$TMP_DIR/app-url.txt" >/dev/null
grep -F "cloudeval-pr-line-comments-test-run-8" "$TMP_DIR/app-idempotency-key.txt" >/dev/null
jq -e '
  .repo_full_name == "ganakailabs/example"
  and .pull_request_number == 8
  and .head_sha == "abcdef123456"
  and (.comments | length == 2)
  and .comments[0].path == "azuredeploy.json"
  and .comments[1].path == "nested/database.json"
' "$TMP_DIR/app-payload.json" >/dev/null
! grep -F "overall score 48" "$TMP_DIR/app-payload.json" >/dev/null
grep -F "pr-line-comments: posted 2 line comment(s) via Cloudeval GitHub App" "$TMP_DIR/output.txt" >/dev/null

cat >"$TMP_DIR/review-empty.json" <<'JSON'
{
  "data": {
    "github": {
      "checks": {
        "annotations": []
      }
    }
  }
}
JSON

export JSON_PATH="$TMP_DIR/review-empty.json"
bash "$ROOT_DIR/scripts/pr-line-comments.sh" >"$TMP_DIR/output-empty.txt"
jq -e '
  .repo_full_name == "ganakailabs/example"
  and .pull_request_number == 8
  and .head_sha == "abcdef123456"
  and (.comments | length == 0)
' "$TMP_DIR/app-payload.json" >/dev/null
grep -F "pr-line-comments: posted 0 line comment(s) via Cloudeval GitHub App" "$TMP_DIR/output-empty.txt" >/dev/null

echo "pr line comments app test passed"
