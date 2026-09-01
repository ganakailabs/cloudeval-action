#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
            "title": "Cloudeval gate failed",
            "message": "Gate evidence: overall score 48 is below 60."
          },
          {
            "path": "nested/database.json",
            "start_line": 1,
            "annotation_level": "warning",
            "title": "Cloudeval review context",
            "message": "Review needs attention."
          }
        ]
      }
    }
  }
}
JSON

export JSON_PATH="$TMP_DIR/review.json"
bash "$ROOT_DIR/scripts/emit-annotations.sh" >"$TMP_DIR/output.txt"

grep -F "::error file=azuredeploy.json,line=30,endLine=30,title=Cloudeval gate failed::Gate evidence: overall score 48 is below 60." "$TMP_DIR/output.txt" >/dev/null
grep -F "::warning file=nested/database.json,line=1,endLine=1,title=Cloudeval review context::Review needs attention." "$TMP_DIR/output.txt" >/dev/null
grep -F "emit-annotations: emitted 2 GitHub workflow annotation(s)" "$TMP_DIR/output.txt" >/dev/null

echo "emit annotations test passed"
