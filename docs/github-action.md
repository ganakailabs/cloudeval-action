# Cloudeval GitHub Action — full guide

This document describes how the **composite action** in this repository runs in GitHub Actions, what it can do to a **repository** (and what it cannot), and every major **input** and **output**.

The canonical metadata is always [`action.yml`](../action.yml) at the repo root.

## What this action does to a repository

The action **does not** push commits, change branch protection, or modify repository settings by default. It:

1. **Runs on GitHub-hosted (or self-hosted) runners** inside a workflow you define in **your** repo.
2. **Installs the Cloudeval CLI** (unless `skip_cli_install` is true) and invokes `cloudeval` with your **scoped access key**. The action tries the official install script first and falls back to the npm package if the installer endpoint is unavailable.
3. **Calls the Cloudeval API** using that key — the same backend as the web app and CLI. Operations are limited by the key’s **capabilities**, **project scope**, **IP allowlist**, and **budgets** (see [ci-access-keys.md](ci-access-keys.md)).
4. **Optionally** adds PR reactions for review lifecycle, posts a **single result comment** (updated in place), and/or uploads **workflow artifacts** (JSON summary, downloaded reports).

For `mode: review`, checked-out **repository files** are used to identify the repository, branch, commit SHA, and dirty working tree state. Other modes only use checked-out files if your prompt or custom steps reference them.

**Important:** Merge gating is **workflow-level**: a failing job blocks merge only if your branch rules require that check. The action exits **non-zero** when a gate fails or the CLI errors.

## Authentication

- Set a repository (or environment) secret **`CLOUDEVAL_ACCESS_KEY`** with a `cev_…` access key from the app: **Developer → API & CLI access keys**. Use the **GitHub Actions CI** template so review mode can read projects/reports, run summaries, and post GitHub App comments when the project is linked to GitHub.
- Pass it to the action as `access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}`.
- Optional **`project_id`** input (or secret) when commands must target a specific Cloudeval project.

Do not commit raw keys. Rotate keys from the Developer workspace if exposed.

### Renew an expired access key

Cloudeval access keys are intentionally time-limited credentials. They are **not renewed in place**, because GitHub repository secrets are write-only and the original secret value cannot be read back.

When a workflow fails with `credential_expired`:

1. Open Cloudeval and go to **Developer → API & CLI access keys**.
2. Create a new **GitHub Actions CI** key scoped to the Cloudeval project used by the workflow.
3. Include the capabilities your workflow uses:
   - project/report read and review capabilities for `mode: review`
   - `review:summary` when AI summaries are enabled
   - `github:comment` for Cloudeval App-authored PR comments
   - `github:checks` for native Cloudeval Check Runs
4. In GitHub, open the repository or environment secrets and replace **`CLOUDEVAL_ACCESS_KEY`** with the new key.
5. Re-run the failed workflow.
6. Revoke or delete the old key in Cloudeval if it is still listed.

For CLI-driven rotation, create the key from an authenticated local session, then update the GitHub secret:

```bash
cloudeval credentials create \
  --name "GitHub Actions CI - owner/repo" \
  --template ci \
  --project "$CLOUDEVAL_PROJECT_ID" \
  --expires 90d \
  --show-secret \
  --format json

gh secret set CLOUDEVAL_ACCESS_KEY --repo owner/repo
```

Never print the new secret in CI logs. Run the command locally or in a secure administrative environment.

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

Use review mode for pull requests after the repository is already linked to a Cloudeval GitHub App project.

Reference implementation: [ganakailabs/cloudeval-azure-arm-review-example](https://github.com/ganakailabs/cloudeval-azure-arm-review-example) contains nested ARM templates, `.cloudeval/config.yaml`, a Cloudeval review workflow, and demo PRs for [security hardening](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/3), [risky regression](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/1), and [cost optimization](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/2). Fork it when you want to test this action against your own Cloudeval project.

Setup checklist:

1. Install the **Cloudeval GitHub App** on the repository and create/import the Cloudeval project from that repository.
2. Create a **GitHub Actions CI** access key in Cloudeval, scoped to that project. Include `github:comment` when you want comments posted by the Cloudeval GitHub App identity and `github:checks` when you want native GitHub Check Runs.
3. Add `CLOUDEVAL_ACCESS_KEY` and `CLOUDEVAL_PROJECT_ID` as GitHub repository or environment secrets.
4. Add the workflow below and make its check required in branch protection if it should block merges.

```yaml
permissions:
  contents: read
  pull-requests: write
  issues: write
  checks: write # only needed for the optional Cloudeval App Check Run
  security-events: write # only needed for the optional SARIF upload step

on:
  pull_request:

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: cloudeval
        uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
          mode: review
          post_pr_comment: true
          github_checks: true
          emit_annotations: true
          # Optional: posts bounded comments directly on changed PR lines.
          pr_line_comments: false
          sarif: true
          upload_artifacts: true
      - uses: github/codeql-action/upload-sarif@v4
        if: always() && steps.cloudeval.outputs.sarif_path != ''
        with:
          sarif_file: ${{ steps.cloudeval.outputs.sarif_path }}
```

Defaults:

- `repo`: `github.repository`
- `ref`: `github.ref_name`
- `commit_sha`: `github.sha`
- `review_output_dir`: `cloudeval-review`
- `review_wait`: `true`; set `false` only if you want `cloudeval review --no-wait`
- `ai_summary`: `true`; set `false` to omit the AI-written summary from `review.json`, `review.md`, and PR comments. The summary starts with direct prose. The detailed AI reviewer note folds by default and contains evidence, reasoning, and next actions when available.
- `ai_summary_mode`: `ask` by default; set `agent` to generate the narrative summary through an Agent Profile
- `ai_summary_profile`: `architecture` by default when `ai_summary_mode: agent`
- `review_wait_timeout_ms`: `900000`
- `review_poll_interval_ms`: `5000`

The CLI blocks dirty worktrees before calling Cloudeval:

```text
Reviews pushed commits only. Add --ignore-dirty to review HEAD anyway.
```

Set `ignore_dirty: "true"` only if the workflow intentionally generates local files before review.

When `post_pr_comment: true`, the action reacts to the PR with `eyes` when review starts and adds a completion reaction when it finishes (`+1` for pass, `confused` for failure). Reruns make a best-effort attempt to clear stale pass/fail reactions before adding the latest state; GitHub may keep historical reactions if the token cannot delete them.

The review itself is written as one idempotent PR comment after the run has result data. For projects linked through the Cloudeval GitHub App, the action first asks Cloudeval to post or update the comment through the app installation. That makes the visible comment author the Cloudeval GitHub App and uses the app logo. If the app route is unavailable, the key is missing the comment capability, or the project is not GitHub-linked, the action falls back to the existing `github-actions[bot]` comment path.

With `emit_annotations: true`, the action emits GitHub Actions line annotations from the review data. These annotations appear in the workflow Checks UI and, when GitHub can map the location to the PR diff, beside changed lines. This path uses the normal workflow run and does not require Cloudeval GitHub App Checks permission.

When `github_checks: true`, the action also asks Cloudeval to post a native GitHub Check Run using the same GitHub App installation. Findings with source paths become inline annotations on the changed files by default. This keeps the workflow runner free of GitHub App private keys; it only sends the Cloudeval access key to the Cloudeval API. The app installation must include **Checks: read and write**, and the access key must include `github:checks`.

Example gates:

```yaml
# .cloudeval/config.yaml
version: 1

# Stack selection tells Cloudeval which file drives diagrams and reports.
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

  review:
    diff:
      # Compare the PR/branch against this base ref for changed-file evidence.
      base_ref: origin/main
      # Keep patch snippets bounded in review.json.
      max_patch_bytes: 40000
    github:
      checks:
        # Post a Cloudeval GitHub App Check Run with source annotations.
        enabled: true
        name: Cloudeval
        # Keep annotations focused on files changed in the PR.
        changed_files_only: true
        annotation_limit: 50
        include_notices: false
      sarif:
        # Write review.sarif.json. Upload it with github/codeql-action/upload-sarif.
        enabled: true
        category: cloudeval-iac
```

If `ci.gates` is missing, review mode reports a warning rather than failing by default. If gates are present, `enforcement: block_pull_request` fails the job on gate failures. Use `enforcement: comment_only` when you want full review output without blocking merges yet. Existing `required`, `warn`, `overall_score_min`, `pillar_score_min`, `fail_on_high_risk`, `fail_on_validation_errors`, and `max_monthly_cost` keys are still accepted for compatibility.

The PR comment distinguishes configured gates from observed posture:

```md
## Cloudeval infrastructure review

| Signal | Result |
| --- | --- |
| Merge gate | 🟢 **PASS** |
| Observed posture | 🔴 **23.1/100 (CRITICAL)** |
| Validation | 🔴 **3 unit tests failed** |
| Policy | 🟢 **GOOD** |
| Cost | 🟢 **143.81 USD/mo (under 100K budget)** |

### Links

[![Project](...)](...) [![Report](...)](...) [![Cost](...)](...) [![Validation](...)](...) [![PDF](...)](...) [![Workflow](...)](...)

### Decision

🟢 **PASS** - configured gates passed, but observed Well-Architected posture is **23.1/100 (CRITICAL)**. Tighten gate thresholds if this posture should block pull requests.
```

`Merge gate` is the configured gate result. A `CRITICAL` posture can still show with `Merge gate: PASS` if your config sets permissive thresholds, disables validation/high-risk failures, or uses a high cost budget. Tighten `minimum_well_architected_score`, `minimum_pillar_score`, `fail_when_high_risk_findings_exist`, `fail_when_validation_fails`, and `max_monthly_cost_usd` when the PR should fail.

Review Markdown also includes a **Links** section with badges when URLs are available:

- project preview
- architecture report
- cost report
- validation details
- PDF download
- workflow run
- review artifacts

The `PDF` badge links to the Cloudeval-hosted PDF download. To also attach a generated PDF to the GitHub workflow artifact, enable review PDF output in `.cloudeval/config.yaml` and keep `upload_artifacts: true`:

```yaml
ci:
  review:
    outputs:
      pdf:
        enabled: true
        report_type: all
        verbosity: evidence
        fail_on_error: false
```

The uploaded artifact then contains `review/review.pdf` alongside `review/review.md` and `review/review.json`, including failed review runs. This gives the PR both links: the hosted `PDF` badge and the GitHub `Artifacts` badge.

Supported PDF output keys:

| Key | Supported values | Default |
| --- | --- | --- |
| `enabled` | `true`, `false` | `false` |
| `report_type` | `all`, `architecture`, `cost`, `unit_tests` | `all` |
| `verbosity` | `brief`, `detailed`, `evidence` | `evidence` |
| `fail_on_error` | `true`, `false` | `false` |

The visible AI summary is followed by a folded detailed AI reviewer note and an open action queue. Well-Architected drilldowns include a Mermaid `radar-beta` chart when enough pillar scores are available, plus a table fallback for GitHub renderers that do not support radar charts yet. Cost drilldowns include a resource-cost pie chart, a projected-versus-optimized savings chart, and a compact service-cost table. If resource-level cost rows do not add up to the displayed total, the chart includes an `Unallocated` slice so the visual reconciles to the monthly estimate.

## GitHub Checks and SARIF

Use these when reviewers should see Cloudeval findings in GitHub's native review surfaces, not only in one PR comment.

| Feature | Action input | Required GitHub permission | Required Cloudeval key capability |
| --- | --- | --- | --- |
| Cloudeval App Check Run | `github_checks: "true"` | Cloudeval GitHub App: **Checks: read and write** | `github:checks` |
| Workflow line annotations | `emit_annotations: "true"` | Workflow token only | project/report read capabilities |
| PR review line comments | `pr_line_comments: "true"` | Workflow token: `pull-requests: write` | project/report read capabilities |
| Cloudeval App Check Run annotations | `github_checks: "true"` | Cloudeval GitHub App: **Checks: read and write** | `github:checks` |
| SARIF file generation | `sarif: "true"` | None by itself | reports/project read capabilities |
| GitHub code scanning upload | `github/codeql-action/upload-sarif` | Workflow token: `security-events: write` | None beyond SARIF generation |

Annotations and PR line comments are created only from source-mapped Cloudeval findings. If the backend report only provides aggregate gate failures, those failures remain in the PR summary comment instead of being attached to arbitrary changed lines. By default Cloudeval annotates changed files only. Set `checks_all_files: "true"` for repository-wide annotations or `checks_include_notices: "true"` when informational findings should appear.

Use `pr_line_comments: "true"` only when you want visible review comments in the **Files changed** tab. The action deletes stale comments with marker `<!-- cloudeval-line-comment -->` from previous `github-actions[bot]` runs, then posts up to `pr_line_comment_limit` fresh comments. This mode is intentionally separate from `emit_annotations` because review comments are more visible and can become noisy on large PRs.

SARIF is written to `review.sarif.json` under `review_output_dir` unless `sarif_output` is set. The composite action exposes the path as `steps.<id>.outputs.sarif_path`; upload it with GitHub's SARIF upload action as shown in the review workflow above.

To actually block merges, add a GitHub branch protection rule or ruleset that requires the workflow job running this action (for example `Cloudeval review / review`). GitHub Actions cannot prevent someone from clicking **Approve** on a PR; the enforcement point is the required status check before merge.

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

- **`include_run_metadata`**: adds workflow metadata to markdown. In `mode: review`, current CLI output renders workflow and artifact links as badges when available. Older review output gets a small appended metadata table instead of being rewritten. Other modes append the same compact metadata table.
- **`summary_answer_jq`**: optional jq on stdout JSON to embed a short excerpt (e.g. `.reason`) in the job summary / gate summary.
- **`job_summary_title`**: heading on the Actions **Summary** tab.
- **`post_pr_comment`**: when `true` and event is `pull_request`, adds PR reactions and updates one result comment (marker `<!-- cloudeval-action -->`). GitHub App-linked projects post the comment through the Cloudeval App identity when the access key has `github:comment`; otherwise the action falls back to **github-actions[bot]**. The fallback and reactions require `permissions: pull-requests: write` and `issues: write`; the PR reaction endpoint uses GitHub's issue reactions API. **Fork PRs** often cannot post comments or reactions due to token restrictions.
- **`pr_comment_collapsed_details`**, **`pr_comment_json_excerpt`**, **`pr_comment_max_json_chars`**: control PR comment layout and optional JSON appendix. Review comments are expanded by default so the one-line result is visible, while detailed review sections can still fold themselves.
- **`pr_line_comments`**, **`pr_line_comment_limit`**: optionally post bounded review comments directly on changed PR lines using the same annotation payload as workflow annotations.
- **`github_checks`**, **`github_check_name`**, **`checks_annotation_limit`**, **`checks_all_files`**, **`checks_include_notices`**: enable Cloudeval App-authored Check Runs and tune annotation volume.
- **`sarif`**, **`sarif_output`**: write source-mapped SARIF for upload to GitHub code scanning or another SARIF consumer.

## Artifacts

- **`upload_artifacts`**: uploads a staged directory containing summary markdown, captured CLI JSON, copied reports (when present), and `review/review.pdf` when CLI review PDF output is enabled in `.cloudeval/config.yaml`.
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
| `artifact_path` | Staged artifact directory before upload |
| `run_url` | Link to the workflow run |
| `sarif_path` | Generated SARIF path when SARIF is enabled |
| `check_run_url` | Cloudeval GitHub App Check Run URL when posted |

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
