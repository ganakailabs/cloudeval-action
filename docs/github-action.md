# CloudEval GitHub Action — full guide

This document describes how the **composite action** in this repository runs in GitHub Actions, what it can do to a **repository** (and what it cannot), and every major **input** and **output**.

The canonical metadata is always [`action.yml`](../action.yml) at the repo root.

## What this action does to a repository

The action **does not** push commits, change branch protection, or modify repository settings by default. It:

1. **Runs on GitHub-hosted (or self-hosted) runners** inside a workflow you define in **your** repo.
2. **Installs the CloudEval CLI** (unless `skip_cli_install` is true) and invokes `cloudeval` with your **scoped access key**. The action tries the official install script first and falls back to the npm package if the installer endpoint is unavailable.
3. **Calls the CloudEval API** using that key — the same backend as the web app and CLI. Operations are limited by the key’s **capabilities**, **project scope**, **IP allowlist**, and **budgets** (see [ci-access-keys.md](ci-access-keys.md)).
4. **Optionally** adds PR reactions for review lifecycle, posts a **single result comment** (updated in place), and/or uploads **workflow artifacts** (JSON summary, downloaded reports).

For `mode: review`, checked-out **repository files** are used to identify the repository, branch, commit SHA, and dirty working tree state. Other modes only use checked-out files if your prompt or custom steps reference them.

**Important:** Merge gating is **workflow-level**: a failing job blocks merge only if your branch rules require that check. The action exits **non-zero** when a gate fails or the CLI errors.

## Authentication

- Set a repository (or environment) secret **`CLOUDEVAL_ACCESS_KEY`** with a `cev_…` access key from the app: **Developer → API & CLI access keys**. Use the **GitHub Actions CI** template so review mode can read projects/reports, run summaries, and post GitHub App comments when the project is linked to GitHub.
- Pass it to the action as `access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}`.
- Optional **`project_id`** input (or secret) when commands must target a specific CloudEval project.

Do not commit raw keys. Rotate keys from the Developer workspace if exposed.

## Modes (`mode` input)

| Mode | Behavior |
|------|----------|
| **`review`** | Runs `cloudeval review`, waits for GitHub sync/report refresh by default, evaluates `.cloudeval/config.yaml` `ci.gates`, writes `review.json` / `review.md` with WAF/cost/validation drill-downs plus an evidence-based AI summary, and exits non-zero on explicit gate failure. |
| **`ask`** | Runs `cloudeval ask` with `ask_prompt` (JSON to stdout). If `agent_task` is set, runs `cloudeval agent` instead. Optional gating if `gate_threshold` is set. |
| **`gate`** | Same as ask/agent, then **fails the job** unless the numeric value from `gate_jq` satisfies `gate_operator` vs `gate_threshold`. |
| **`agent`** | Runs `cloudeval agent` with `agent_task` (requires `agent_task`). Optional gating. |
| **`reports`** | Requires `project_id`. Runs `cloudeval reports run`, optionally `reports download` into `reports_output_dir`. |
| **`nightly`** | If `project_id` is set: same as **reports**. Otherwise: ask/agent path (for scheduled smoke or policy strings) with optional gating. |

All LLM-facing modes use **`--format json`** and **`--non-interactive`**.

## Review mode

Use review mode for pull requests after the repository is already linked to a CloudEval GitHub App project:

```yaml
permissions:
  contents: read
  pull-requests: write
  issues: write

on:
  pull_request:

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
          mode: review
          post_pr_comment: true
          upload_artifacts: true
```

Defaults:

- `repo`: `github.repository`
- `ref`: `github.ref_name`
- `commit_sha`: `github.sha`
- `review_output_dir`: `cloudeval-review`
- `review_wait`: `true`; set `false` only if you want `cloudeval review --no-wait`
- `ai_summary`: `true`; set `false` to omit the AI-written summary from `review.json`, `review.md`, and PR comments. The summary starts with direct prose, then folds evidence and recommended actions when the model returns details.
- `ai_summary_mode`: `ask` by default; set `agent` to generate the narrative summary through an Agent Profile
- `ai_summary_profile`: `architecture` by default when `ai_summary_mode: agent`
- `review_wait_timeout_ms`: `900000`
- `review_poll_interval_ms`: `5000`

The CLI blocks dirty worktrees before calling CloudEval:

```text
Reviews pushed commits only. Add --ignore-dirty to review HEAD anyway.
```

Set `ignore_dirty: "true"` only if the workflow intentionally generates local files before review.

When `post_pr_comment: true`, the action reacts to the PR with `eyes` when review starts and adds a completion reaction when it finishes (`+1` for pass, `confused` for failure). Reruns make a best-effort attempt to clear stale pass/fail reactions before adding the latest state; GitHub may keep historical reactions if the token cannot delete them.

The review itself is written as one idempotent PR comment after the run has result data. For projects linked through the CloudEval GitHub App, the action first asks CloudEval to post or update the comment through the app installation. That makes the visible comment author the CloudEval GitHub App and uses the app logo. If the app route is unavailable, the key is missing the comment capability, or the project is not GitHub-linked, the action falls back to the existing `github-actions[bot]` comment path.

Example gates:

```yaml
# .cloudeval/config.yaml
version: 1

# Stack selection tells CloudEval which file drives diagrams and reports.
stacks:
  - id: primary-architecture
    name: Primary architecture
    entry: azuredeploy.json
    parameters: azuredeploy.parameters.json

resolve:
  # Follow relative ARM templateLink files before graph/report analysis.
  linked_templates: true

ci:
  gates:
    # block_pull_request fails the job; comment_only keeps the PR comment but does not block.
    enforcement: block_pull_request

    # Minimum Well-Architected score out of 100.
    minimum_well_architected_score: 85

    # Optional default minimum for every pillar. Per-pillar overrides below win.
    minimum_pillar_score: 80
    pillars:
      security: 90
      reliability: 85

    # Fail on high-risk architecture findings.
    fail_when_high_risk_findings_exist: true

    # Fail when policy checks or unit tests fail.
    fail_when_validation_fails: true

    # Optional monthly budget gate. Omit if cost should be reported but not gated.
    max_monthly_cost_usd: 500
```

If `ci.gates` is missing, review mode reports a warning rather than failing by default. If gates are present, `enforcement: block_pull_request` fails the job on gate failures. Use `enforcement: comment_only` when you want full review output without blocking merges yet. Existing `required`, `warn`, `overall_score_min`, `pillar_score_min`, `fail_on_high_risk`, `fail_on_validation_errors`, and `max_monthly_cost` keys are still accepted for compatibility.

The PR comment distinguishes configured gates from observed posture:

```md
🟢 **Overall** : PASS
🔴 Well-Architected Posture: 23.1/100 (CRITICAL)
🔴 Validation: 3 unit tests failed
🟢 Policy checks: GOOD
🟢 Cost: 143.81 USD/mo (under 100K budget)
**Cloudeval Project**: [GitHub Nested E2E](https://cloudeval.ai/app/projects/...)
```

`Overall` is the configured gate result. A `CRITICAL` posture can still show with `Overall: PASS` if your config sets permissive thresholds, disables validation/high-risk failures, or uses a high cost budget. Tighten `minimum_well_architected_score`, `minimum_pillar_score`, `fail_when_high_risk_findings_exist`, `fail_when_validation_fails`, and `max_monthly_cost_usd` when the PR should fail.

To actually block merges, add a GitHub branch protection rule or ruleset that requires the workflow job running this action (for example `CloudEval review / review`). GitHub Actions cannot prevent someone from clicking **Approve** on a PR; the enforcement point is the required status check before merge.

## Gating (`gate_*`)

- **`gate_jq`**: jq expression applied to the **CLI JSON on stdout**; result must be a **single number** (`tonumber` in the runner script).
- **`gate_threshold`**: number to compare against.
- **`gate_operator`**: `ge` (≥), `gt`, `le`, `lte` (≤), `lt`, `eq`, `ne`.

Design prompts so the model returns stable JSON (for example `{"score":0.85,"reason":"..."}`) and set `gate_jq` to `.score`.

## Reports (`reports_*`)

- **`reports_type`**: passed to `reports run` / `download` (e.g. `all`, `cost`, `waf`).
- **`reports_region`**, **`reports_currency`**: cost report defaults.
- **`reports_wait`**: when `true`, adds `--wait` and **`reports_poll_interval_ms`** for polling until jobs complete.
- **`reports_download`**: when `true`, runs `reports download` after `run`.
- **`reports_output_dir`**: local directory name for downloaded files.

## CLI tuning

- **`quiet`**: default `true` — passes `--quiet`.
- **`progress`**: default `none` — passes `--progress none` (recommended in CI).
- **`model`**, **`profile`**: forwarded as `--model` / `--profile` when set.
- **`base_url`**: non-default API base (staging / self-hosted).
- **`working_directory`**: cwd for all `cloudeval` invocations.

## Summaries and PR feedback

- **`include_run_metadata`**: adds workflow run link, ref, SHA to markdown.
- **`summary_answer_jq`**: optional jq on stdout JSON to embed a short excerpt (e.g. `.reason`) in the job summary / gate summary.
- **`job_summary_title`**: heading on the Actions **Summary** tab.
- **`post_pr_comment`**: when `true` and event is `pull_request`, adds PR reactions and updates one result comment (marker `<!-- cloudeval-action -->`). GitHub App-linked projects post the comment through the CloudEval App identity when the access key has `github:comment`; otherwise the action falls back to **github-actions[bot]**. The fallback and reactions require `permissions: pull-requests: write` and `issues: write`; the PR reaction endpoint uses GitHub's issue reactions API. **Fork PRs** often cannot post comments or reactions due to token restrictions.
- **`pr_comment_collapsed_details`**, **`pr_comment_json_excerpt`**, **`pr_comment_max_json_chars`**: control PR comment layout and optional JSON appendix. Review comments are expanded by default so the one-line result is visible, while detailed review sections can still fold themselves.

## Artifacts

- **`upload_artifacts`**: uploads a staged directory containing summary markdown, captured CLI JSON, and copied reports (when present).
- **`artifact_name`**, **`artifact_retention_days`**: passed to `actions/upload-artifact`.

## Outputs (for downstream steps)

| Output | Meaning |
|--------|---------|
| `result` | `pass` or `fail` |
| `score` / `extracted_value` | Numeric gate value when gating ran |
| `summary_markdown` | Full markdown summary |
| `summary_file` | Path on runner (for custom steps) |
| `json_path` | Captured CLI JSON path |
| `report_path` | Reports download directory when applicable |
| `run_url` | Link to the workflow run |

## Reusable workflow

This repo ships [`.github/workflows/cloudeval-reusable.yml`](../.github/workflows/cloudeval-reusable.yml). Call it from another repository with `workflow_call` and pass `secrets.CLOUDEVAL_ACCESS_KEY`. The reusable workflow forwards the same review/report inputs to `ganakailabs/cloudeval-action@v1`.

## Supply chain and pinning

- Pin **`uses: ganakailabs/cloudeval-action@v1`** (or `@v1.0.0` / full SHA) in your workflows.
- Third-party steps inside this action use **pinned SHAs**; review Dependabot PRs here before merging.

## Further reading

- [Access keys in CI](ci-access-keys.md)
- [Releasing and tags](../RELEASING.md)
- [Security](../SECURITY.md)
- Upstream CLI contract: [credentials-api-contract](https://github.com/ganakailabs/cloudeval-cli/blob/main/docs/credentials-api-contract.md) (access key format and behavior)
