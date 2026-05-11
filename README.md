# CloudEval GitHub Action

<p align="center">
  <img src="media/logo-abstract-cloud-256.png" alt="CloudEval" width="128" height="128" />
</p>

Composite action that installs the [CloudEval CLI](https://github.com/ganakailabs/cloudeval-cli) and runs **ask**, **agent**, **reports**, **merge gating**, **nightly** flows, with **job summaries**, **PR comments**, and **artifacts**.

The image above is the same **abstract cloud** mark as in the web app ([`app/layout.tsx` OpenGraph](https://github.com/ganakailabs/cloudeval-frontend/blob/main/app/layout.tsx) uses `/common/logo-abstract-cloud-dark-v3.png`). The GitHub Marketplace badge still uses GitHub’s **Feather `cloud`** icon because [custom images are not supported](https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#branding) in `action.yml` `branding`.

Authentication uses a **scoped access key** (`cev_…`). Create keys in the app: **Developer → API & CLI access keys**. Store the secret as `CLOUDEVAL_ACCESS_KEY` (see [docs/ci-access-keys.md](docs/ci-access-keys.md)).

## Quick start

```yaml
permissions:
  contents: read
  pull-requests: write

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
          mode: gate
          ask_prompt: 'Return JSON only: {"score": <0-1>, "reason": "..."} evaluating IaC risk for this repo.'
          gate_threshold: '0.7'
          gate_jq: '.score'
          gate_operator: ge
          summary_answer_jq: '.reason // .answer // empty'
          post_pr_comment: true
          upload_artifacts: true
```

Pin the action and `actions/checkout` to **tags or SHAs** you trust (see [RELEASING.md](RELEASING.md)).

## Features

| Area | What you get |
|------|----------------|
| **Modes** | `ask`, `agent`, `gate`, `reports`, `nightly` (reports if `project_id` set, else ask/agent). |
| **Gating** | `gate_jq` extracts a number; `gate_operator` one of `ge`, `gt`, `le`, `lte`, `lt`, `eq`, `ne`; fail job on mismatch. |
| **CLI ergonomics** | `quiet`, `progress` (default `none`), optional `model`, `profile`. |
| **Reports** | `reports_type`, `reports_region`, `reports_currency`, optional `reports_wait` + poll interval, then `reports download`. |
| **Summaries** | GitHub **job summary** + optional `summary_answer_jq` snippet from JSON. |
| **PR feedback** | One idempotent comment (`<!-- cloudeval-action -->`), collapsible details, optional JSON excerpt, run metadata + link. |
| **Artifacts** | Staged JSON, summary, and downloaded reports with configurable **retention-days**. |
| **Outputs** | `result`, `score` / `extracted_value`, `summary_markdown`, `summary_file`, `json_path`, `report_path`, `run_url`. |
| **Reusable workflow** | [cloudeval-reusable.yml](.github/workflows/cloudeval-reusable.yml) forwards secrets and inputs; set `action_repository` / `action_ref` if you fork. |
| **CI / tests** | Stubbed `cloudeval` jobs validate gating without live API keys. |
| **Advanced** | `skip_cli_install`, custom `cli_install_url`, `base_url` for self-hosted API. |

## Inputs (summary)

See [`action.yml`](action.yml) for the full list. Common ones:

- **`access_key`** (required) — `secrets.CLOUDEVAL_ACCESS_KEY`
- **`mode`**, **`project_id`**, **`ask_prompt`**, **`agent_task`**
- **`gate_threshold`**, **`gate_jq`**, **`gate_operator`**
- **`summary_answer_jq`** — e.g. `.reason` or `.answer` for human-readable summary text
- **`reports_*`**, **`quiet`**, **`progress`**, **`model`**, **`profile`**
- **`post_pr_comment`**, **`pr_comment_collapsed_details`**, **`pr_comment_json_excerpt`**
- **`upload_artifacts`**, **`artifact_name`**, **`artifact_retention_days`**
- **`include_run_metadata`**, **`job_summary_title`**

## Requirements

- Ubuntu runners (or compatible) with `bash`, `curl`, `jq`, `gh` (for PR comments).
- Valid CloudEval access key with capabilities for the operations you run.
- For PR comments from **forks**, GitHub may block token permissions; document that for contributors.

## Documentation

- [Access keys in CI](docs/ci-access-keys.md)
- [Releasing & Marketplace](RELEASING.md)
- [Security](SECURITY.md)
- Upstream contract: [credentials-api-contract.md](https://github.com/ganakailabs/cloudeval-cli/blob/main/docs/credentials-api-contract.md)

## License

See [LICENSE](LICENSE).
