#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
response_file=""
payload_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      response_file="$2"
      shift 2
      ;;
    --data-binary)
      payload_file="${2#@}"
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
cp "$payload_file" "${CAPTURE_PAYLOAD:?}"
printf '{"status":"posted","check_run_id":202,"html_url":"https://github.test/org/repo/runs/202"}' > "$response_file"
printf '200'
CURL
chmod +x "$tmpdir/bin/curl"

cat >"$tmpdir/review.json" <<'JSON'
{
  "data": {
    "projectId": "project-1",
    "repo": "org/repo",
    "commitSha": "abc123def456",
    "gate": {
      "status": "warn"
    },
    "github": {
      "checks": {
        "enabled": true,
        "name": "CloudEval review",
        "annotations": [
          {
            "path": "infra/main.json",
            "start_line": 12,
            "end_line": 12,
            "annotation_level": "failure",
            "message": "Parameter must not contain a plain-text secret.",
            "title": "Secure parameter"
          }
        ]
      }
    }
  }
}
JSON

cat >"$tmpdir/summary.md" <<'MD'
## CloudEval infrastructure review

| Signal | Result |
| --- | --- |
| Merge gate | 🟡 **WARN** |
MD

export PATH="$tmpdir/bin:$PATH"
export CAPTURE_PAYLOAD="$tmpdir/payload.json"
export CLOUDEVAL_ACCESS_KEY="cev_test_ak_mock"
export INPUT_PROJECT_ID="project-1"
export INPUT_BASE_URL="https://cloudeval.test/api/v1"
export INPUT_GITHUB_CHECK_NAME="CloudEval"
export SUMMARY_FILE="$tmpdir/summary.md"
export JSON_PATH="$tmpdir/review.json"
export RESULT="pass"
export REPO="org/repo"
export GITHUB_SERVER_URL="https://github.test"
export GITHUB_REPOSITORY="org/repo"
export GITHUB_RUN_ID="123"
export GITHUB_SHA="abc123def456"
export GITHUB_OUTPUT="$tmpdir/output.txt"

bash "$(dirname "$0")/check-run.sh"

jq -e '
  .repo_full_name == "org/repo"
  and .name == "CloudEval review"
  and .head_sha == "abc123def456"
  and .conclusion == "neutral"
  and .details_url == "https://github.test/org/repo/actions/runs/123"
  and .output.title == "CloudEval infrastructure review"
  and (.output.summary | contains("CloudEval infrastructure review"))
  and .annotations[0].path == "infra/main.json"
  and .annotations[0].annotation_level == "failure"
' "$CAPTURE_PAYLOAD" >/dev/null

grep -F 'check_run_url=https://github.test/org/repo/runs/202' "$GITHUB_OUTPUT" >/dev/null
