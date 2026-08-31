#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

cat >"$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
response_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      response_file="$2"
      shift 2
      ;;
    -w)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "$response_file" ]]; then
  printf '%s' '{"code":"credential_expired","message":"This access-key credential has expired."}' >"$response_file"
fi
printf '401'
EOF
chmod +x "$BIN_DIR/curl"

cat >"$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--method POST"* ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)
        cp "$2" "$CAPTURED_COMMENT_JSON"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  printf '{"id":12345}\n'
  exit 0
fi
if [[ "$*" == *"/comments"* ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$BIN_DIR/gh"

export PATH="$BIN_DIR:$PATH"
export REPO="ganakailabs/example"
export PR_NUMBER="8"
export GITHUB_TOKEN="ghs_mock"
export GITHUB_RUN_ID="123456789"
export INPUT_PROJECT_ID="project-123"
export CLOUDEVAL_ACCESS_KEY="cev_live_ak_expired"
export SUMMARY_FILE="$TMP_DIR/summary.md"
export CAPTURED_COMMENT_JSON="$TMP_DIR/comment.json"
export PR_COMMENT_COLLAPSED="false"

cat >"$SUMMARY_FILE" <<'MD'
## CloudEval infrastructure review

CloudEval access key is expired.

Next steps: Renew the repository secret.

https://docs.cloudeval.ai/workflows/github-actions#renew-an-expired-access-key
MD

bash "$ROOT_DIR/scripts/pr-comment.sh" >/tmp/pr-comment-fallback.out

jq -e '.body | contains("<!-- cloudeval-action -->")' "$CAPTURED_COMMENT_JSON" >/dev/null
jq -e '.body | contains("CloudEval access key is expired")' "$CAPTURED_COMMENT_JSON" >/dev/null
jq -e '.body | contains("Renew the repository secret")' "$CAPTURED_COMMENT_JSON" >/dev/null
jq -e '.body | contains("https://docs.cloudeval.ai/workflows/github-actions#renew-an-expired-access-key")' "$CAPTURED_COMMENT_JSON" >/dev/null

echo "pr comment fallback guidance test passed"
