#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR" "$TMP_DIR/posts"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"--method DELETE"* ]]; then
  printf '%s\n' "$*" >>"$CAPTURE_DIR/deletes.txt"
  exit 0
fi

if [[ "$*" == *"--method POST"* ]]; then
  input_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)
        input_file="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  index="$(find "$CAPTURE_DIR/posts" -type f | wc -l | tr -d ' ')"
  cp "$input_file" "$CAPTURE_DIR/posts/comment-$index.json"
  printf '{"id":%s}\n' "$((1000 + index))"
  exit 0
fi

if [[ "$*" == *"repos/ganakailabs/example/pulls/8/comments"* ]]; then
  if [[ "$*" == *"--jq"* ]]; then
    printf '%s\n' '777'
  else
    printf '%s\n' '[{"id":777,"user":{"login":"github-actions[bot]"},"body":"<!-- cloudeval-line-comment --> old"}]'
  fi
  exit 0
fi

exit 1
EOF
chmod +x "$BIN_DIR/gh"

cat >"$TMP_DIR/review.json" <<'JSON'
{
  "data": {
    "github": {
      "checks": {
        "annotations": [
          {
            "path": "azuredeploy.json",
            "start_line": 30,
            "annotation_level": "failure",
            "title": "Storage account permits public access",
            "message": "Set allowBlobPublicAccess to false.",
            "raw_details": "well_architected · high"
          },
          {
            "path": "nested/database.json",
            "start_line": 12,
            "annotation_level": "warning",
            "title": "SQL public network access",
            "message": "Disable public network access for production SQL servers.",
            "raw_details": "policy_check · warning"
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
export GITHUB_TOKEN="ghs_mock"
export PR_NUMBER="8"
export REPO="ganakailabs/example"
export GITHUB_HEAD_SHA="abcdef123456"
export INPUT_PR_LINE_COMMENT_LIMIT="5"

bash "$ROOT_DIR/scripts/pr-line-comments.sh" >"$TMP_DIR/output.txt"

grep -F "pulls/comments/777" "$TMP_DIR/deletes.txt" >/dev/null
test "$(find "$TMP_DIR/posts" -type f | wc -l | tr -d ' ')" = "2"
jq -e '.path == "azuredeploy.json" and .line == 30 and .side == "RIGHT" and .commit_id == "abcdef123456"' "$TMP_DIR/posts/comment-0.json" >/dev/null
jq -e '.body | contains("<!-- cloudeval-line-comment -->") and contains("Storage account permits public access") and contains("allowBlobPublicAccess")' "$TMP_DIR/posts/comment-0.json" >/dev/null
jq -e '.path == "nested/database.json" and .line == 12' "$TMP_DIR/posts/comment-1.json" >/dev/null
! grep -R "overall score 48" "$TMP_DIR/posts" >/dev/null
grep -F "pr-line-comments: posted 2 line comment(s)" "$TMP_DIR/output.txt" >/dev/null

echo "pr line comments test passed"
