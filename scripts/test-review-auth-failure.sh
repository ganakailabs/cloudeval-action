#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

cat >"$BIN_DIR/cloudeval" <<'EOF'
#!/usr/bin/env bash
echo '{"code":"credential_expired","message":"This access-key credential has expired.","request_id":"test-request"}' >&2
exit 1
EOF
chmod +x "$BIN_DIR/cloudeval"

export PATH="$BIN_DIR:$PATH"
export RUNNER_TEMP="$TMP_DIR/runner"
export GITHUB_OUTPUT="$TMP_DIR/github-output.txt"
export GITHUB_STEP_SUMMARY="$TMP_DIR/step-summary.md"
export GITHUB_SERVER_URL="https://github.com"
export GITHUB_REPOSITORY="ganakailabs/example"
export GITHUB_RUN_ID="123456789"
export GITHUB_REF_NAME="feature/example"
export GITHUB_SHA="abcdef1234567890"
export INPUT_MODE="review"
export INPUT_PROJECT_ID="project-123"
export INPUT_REPO="ganakailabs/example"
export INPUT_REF="feature/example"
export INPUT_COMMIT_SHA="abcdef1234567890"
export INPUT_REVIEW_OUTPUT_DIR="cloudeval-review"
export INPUT_INCLUDE_RUN_METADATA="true"
export INPUT_QUIET="true"
export INPUT_PROGRESS="none"
export INPUT_REVIEW_WAIT="true"
export INPUT_AI_SUMMARY="true"

set +e
(cd "$TMP_DIR" && bash "$ROOT_DIR/scripts/run.sh")
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "expected review auth failure to exit non-zero" >&2
  exit 1
fi

grep -F "Cloudeval access key is expired" "$GITHUB_OUTPUT" >/dev/null
grep -F "Renew the repository secret" "$GITHUB_OUTPUT" >/dev/null
grep -F "https://docs.cloudeval.ai/guides/review/github-actions#renew-an-expired-access-key" "$GITHUB_OUTPUT" >/dev/null
grep -F "credential_expired" "$GITHUB_OUTPUT" >/dev/null

echo "review auth failure summary test passed"
