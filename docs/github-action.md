# CloudEval GitHub Action — full guide

This document describes how the **composite action** in this repository runs in GitHub Actions, what it can do to a **repository** (and what it cannot), and every major **input** and **output**.

The canonical metadata is always [`action.yml`](../action.yml) at the repo root.

## What this action does to a repository

The action **does not** push commits, change branch protection, or modify repository settings by default. It:

1. **Runs on GitHub-hosted (or self-hosted) runners** inside a workflow you define in **your** repo.
2. **Installs the CloudEval CLI** (unless `skip_cli_install` is true) and invokes `cloudeval` with your **scoped access key**.
3. **Calls the CloudEval API** using that key — the same backend as the web app and CLI. Operations are limited by the key’s **capabilities**, **project scope**, **IP allowlist**, and **budgets** (see [ci-access-keys.md](ci-access-keys.md)).
4. **Optionally** posts a **single PR comment** (updated in place) and/or uploads **workflow artifacts** (JSON summary, downloaded reports).

Checked-out **repository files** are only relevant if your workflow (or a later step) uses them — for example you might `actions/checkout` and pass template paths into a **custom** job that runs before this action, or use `working_directory` so relative paths in prompts refer to your tree. The action itself does not scan the repo unless you combine it with other steps or put file paths inside `ask_prompt` / `agent_task`.

**Important:** Merge gating is **workflow-level**: a failing job blocks merge only if your branch rules require that check. The action exits **non-zero** when a gate fails or the CLI errors.

## Authentication

- Set a repository (or environment) secret **`CLOUDEVAL_ACCESS_KEY`** with a `cev_…` access key from the app: **Developer → API & CLI access keys**.
- Pass it to the action as `access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}`.
- Optional **`project_id`** input (or secret) when commands must target a specific CloudEval project.

Do not commit raw keys. Rotate keys from the Developer workspace if exposed.

## Modes (`mode` input)

| Mode | Behavior |
|------|----------|
| **`ask`** | Runs `cloudeval ask` with `ask_prompt` (JSON to stdout). If `agent_task` is set, runs `cloudeval agent` instead. Optional gating if `gate_threshold` is set. |
| **`gate`** | Same as ask/agent, then **fails the job** unless the numeric value from `gate_jq` satisfies `gate_operator` vs `gate_threshold`. |
| **`agent`** | Runs `cloudeval agent` with `agent_task` (requires `agent_task`). Optional gating. |
| **`reports`** | Requires `project_id`. Runs `cloudeval reports run`, optionally `reports download` into `reports_output_dir`. |
| **`nightly`** | If `project_id` is set: same as **reports**. Otherwise: ask/agent path (for scheduled smoke or policy strings) with optional gating. |

All LLM-facing modes use **`--format json`** and **`--non-interactive`**.

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
- **`post_pr_comment`**: when `true` and event is `pull_request`, updates one **github-actions[bot]** comment (marker `<!-- cloudeval-action -->`). Requires `permissions: pull-requests: write`. **Fork PRs** often cannot post comments due to token restrictions.
- **`pr_comment_collapsed_details`**, **`pr_comment_json_excerpt`**, **`pr_comment_max_json_chars`**: control PR comment layout and optional JSON appendix.

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

This repo ships [`.github/workflows/cloudeval-reusable.yml`](../.github/workflows/cloudeval-reusable.yml). Call it from another repository with `workflow_call`, pass `secrets.CLOUDEVAL_ACCESS_KEY`, and set `action_repository` / `action_ref` if you fork the action.

## Supply chain and pinning

- Pin **`uses: ganakailabs/cloudeval-action@v1`** (or `@v1.0.0` / full SHA) in your workflows.
- Third-party steps inside this action use **pinned SHAs**; review Dependabot PRs here before merging.

## Further reading

- [Access keys in CI](ci-access-keys.md)
- [Releasing and tags](../RELEASING.md)
- [Security](../SECURITY.md)
- Upstream CLI contract: [credentials-api-contract](https://github.com/ganakailabs/cloudeval-cli/blob/main/docs/credentials-api-contract.md) (access key format and behavior)
