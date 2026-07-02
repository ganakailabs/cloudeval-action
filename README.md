# CloudEval GitHub Action

<p align="center">
  <img src="media/logo-abstract-cloud-256.png" alt="CloudEval" width="128" height="128" />
</p>

Composite action that installs the [CloudEval CLI](https://github.com/ganakailabs/cloudeval-cli) and runs **review**, **ask**, **agent**, **reports**, **merge gating**, and **nightly** flows, with **job summaries**, **PR comments**, and **artifacts**.

The image above is the same **abstract cloud** mark as in the web app ([`app/layout.tsx` OpenGraph](https://github.com/ganakailabs/cloudeval-frontend/blob/main/app/layout.tsx) uses `/common/logo-abstract-cloud-dark-v3.png`). The GitHub Marketplace badge still uses GitHub’s **Feather `cloud`** icon because [custom images are not supported](https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#branding) in `action.yml` `branding`.

Authentication uses a **scoped access key** (`cev_…`). Create keys in the app: **Developer → API & CLI access keys**. Store the secret as `CLOUDEVAL_ACCESS_KEY` (see [docs/ci-access-keys.md](docs/ci-access-keys.md)). For PR review, use the **GitHub Actions CI** key template so CloudEval can run reports, generate AI summaries, and post GitHub App comments for GitHub-linked projects.

**Full guide (modes, gating, repo behavior, every input family):** [docs/github-action.md](docs/github-action.md)

## Public example

Use [ganakailabs/cloudeval-azure-arm-review-example](https://github.com/ganakailabs/cloudeval-azure-arm-review-example) as a clean public reference. It includes nested Azure ARM templates, `.cloudeval/config.yaml`, this action wired in `.github/workflows/cloudeval-review.yml`, and demo PRs for [security hardening](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/3), [risky regression](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/1), and [cost optimization](https://github.com/ganakailabs/cloudeval-azure-arm-review-example/pull/2).

## Quick start

```yaml
name: CloudEval review

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
          mode: review
          post_pr_comment: true
          upload_artifacts: true
```

Pin the action and `actions/checkout` to **tags or SHAs** you trust (see [RELEASING.md](RELEASING.md)).

## Features

| Area | What you get |
|------|----------------|
| **Modes** | `review`, `ask`, `agent`, `gate`, `reports`, `nightly` (reports if `project_id` set, else ask/agent). |
| **Review** | Runs `cloudeval review`, waits for GitHub sync/report refresh by default, evaluates `.cloudeval/config.yaml` `ci.gates`, includes WAF/cost/validation drill-downs plus an evidence-based AI summary, and writes `review.json` / `review.md`. |
| **Gating** | `review` uses config gates; prompt-based `gate` uses `gate_jq`, `gate_operator`, and `gate_threshold`. |
| **CLI ergonomics** | `quiet`, `progress` (default `none`), optional `model`, `profile`. |
| **Reports** | `reports_type`, `reports_region`, `reports_currency`, optional `reports_wait` + poll interval, then `reports download`. |
| **Summaries** | GitHub **job summary** + optional `summary_answer_jq` snippet from JSON. |
| **PR feedback** | Adds PR reactions for review lifecycle (`eyes` when started, `+1`/`confused` when finished), attempts to clear stale pass/fail reactions across reruns, and writes one idempotent result comment (`<!-- cloudeval-action -->`) with a merge-gate table, CloudEval report badges, visible AI summary, folded detailed AI reviewer note, action queue, Well-Architected radar/table drilldown, resource-cost pie, and savings impact chart. For GitHub App-linked projects, comment posting is delegated to the CloudEval GitHub App so the comment uses the CloudEval App identity and logo; otherwise it falls back to `github-actions[bot]`. |
| **Artifacts** | Staged JSON, summary, and downloaded reports with configurable **retention-days**. |
| **Outputs** | `result`, `score` / `extracted_value`, `summary_markdown`, `summary_file`, `json_path`, `report_path`, `artifact_path`, `run_url`. |
| **Reusable workflow** | [cloudeval-reusable.yml](.github/workflows/cloudeval-reusable.yml) forwards secrets and the same review/report inputs to `ganakailabs/cloudeval-action@v1`. |
| **CI / tests** | Stubbed `cloudeval` jobs validate gating without live API keys. |
| **Advanced** | `skip_cli_install`, custom `cli_install_url`, `base_url` for self-hosted API. If the install script is temporarily unavailable, the action falls back to the npm package. |

## Inputs (summary)

See [`action.yml`](action.yml) for the full list. Common ones:

- **`access_key`** (required) — `secrets.CLOUDEVAL_ACCESS_KEY`
- **`mode`**, **`project_id`**, **`ask_prompt`**, **`agent_task`**
- **`repo`**, **`ref`**, **`commit_sha`**, **`source_root`**, **`config_path`**, **`ignore_dirty`**, **`review_wait`**, **`review_wait_timeout_ms`**, **`review_poll_interval_ms`**, **`ai_summary`**, **`ai_summary_mode`**, **`ai_summary_profile`**, **`review_output_dir`** for `mode: review`
- **`gate_threshold`**, **`gate_jq`**, **`gate_operator`**
- **`summary_answer_jq`** — e.g. `.reason` or `.answer` for human-readable summary text
- **`reports_*`**, **`quiet`**, **`progress`**, **`model`**, **`profile`**
- **`post_pr_comment`**, **`pr_comment_collapsed_details`**, **`pr_comment_json_excerpt`**
- **`upload_artifacts`**, **`artifact_name`**, **`artifact_retention_days`**
- **`include_run_metadata`**, **`job_summary_title`**

Review PR comments are expanded by default. The visible header separates the configured **Merge gate** result from observed Well-Architected posture, validation, policy checks, and cost budget status. CloudEval project, report, PDF, workflow, and artifact links render as badges. The `PDF` badge points to the CloudEval-hosted PDF; when `.cloudeval/config.yaml` enables `ci.review.outputs.pdf.enabled` and `upload_artifacts: true`, the uploaded GitHub artifact also contains `review/review.pdf`, including failed review runs. The AI summary stays visible, while the detailed AI reviewer note folds by default; action queue, Well-Architected, cost, validation, and architecture evidence sections use GitHub-native disclosures.

PDF artifact output supports `report_type` (`all`, `architecture`, `cost`, `unit_tests`), `verbosity` (`brief`, `detailed`, `evidence`), and `fail_on_error` for teams that want PDF export failures to block the review.

## Requirements

- Ubuntu runners (or compatible) with `bash`, `curl`, `npm`, `jq`, `gh` (for fallback PR comments and reactions).
- Valid CloudEval access key with capabilities for the operations you run.
- For PR comments from **forks**, GitHub may block token permissions; document that for contributors.
- To block merges, configure GitHub branch protection/rulesets to require the workflow job that uses `mode: review`. The action fails that job only when `.cloudeval/config.yaml` gates are present and `enforcement` is `block_pull_request` (or the older compatible `required` value); low score labels such as `CRITICAL` are informational unless your gates require them to fail.

## Documentation

- [GitHub Action — full guide](docs/github-action.md) (how it affects repos, modes, configuration)
- [Access keys in CI](docs/ci-access-keys.md)
- [Releasing & Marketplace](RELEASING.md)
- [Security](SECURITY.md)
- Upstream contract: [credentials-api-contract.md](https://github.com/ganakailabs/cloudeval-cli/blob/main/docs/credentials-api-contract.md)

## License

See [LICENSE](LICENSE).
