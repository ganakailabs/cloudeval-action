# CloudEval GitHub Action

Run the [CloudEval CLI](https://github.com/ganakailabs/cloudeval-cli) in GitHub Actions using a **scoped access key** (`cev_…`). Create keys in the product under **Developer → API & CLI access keys** (see [Auth keys](https://github.com/ganakailabs/cloudeval-frontend/blob/main/docs/guides/auth-and-security.md) in the frontend repo).

## Setup

1. Create an access key in CloudEval and add it as a repository secret named `CLOUDEVAL_ACCESS_KEY`.
2. Optional: set `CLOUDEVAL_PROJECT_ID` as a secret or env if your key is project-scoped and you pass `project_id` through the action.

Do **not** commit raw keys. Rotate keys from the Developer workspace if exposed.

## Usage

### Merge gate (score threshold)

Runs `cloudeval ask` (or `agent` if `agent_task` is set), parses JSON stdout, and fails the job if the numeric value from `gate_jq` is below `gate_threshold`.

```yaml
permissions:
  contents: read
  pull-requests: write

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          mode: gate
          ask_prompt: 'Rate this IaC diff for security on a scale 0-1. Reply JSON only with {"score": <number>}.'
          gate_threshold: '0.7'
          gate_jq: '.score'
          post_pr_comment: true
```

Adjust `gate_jq` to match the JSON your prompt returns (must be a single number for `tonumber`).

### One-shot ask (policy / IaC check)

```yaml
- uses: ganakailabs/cloudeval-action@v1
  with:
    access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
    mode: ask
    project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
    ask_prompt: 'Does this ARM template violate our tagging policy? Summarize yes/no and why.'
    upload_artifacts: true
```

### Reports + artifact

Requires `project_id`.

```yaml
- uses: ganakailabs/cloudeval-action@v1
  with:
    access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
    mode: reports
    project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
    reports_type: all
    upload_artifacts: true
```

### Nightly regression

- If `project_id` is set: runs **reports** (same as `mode: reports`).
- Otherwise: runs **ask** (or **agent** if `agent_task` is set); optional `gate_threshold` applies.

```yaml
on:
  schedule:
    - cron: '0 6 * * *'

jobs:
  nightly:
    runs-on: ubuntu-latest
    steps:
      - uses: ganakailabs/cloudeval-action@v1
        with:
          access_key: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
          mode: nightly
          project_id: ${{ secrets.CLOUDEVAL_PROJECT_ID }}
          upload_artifacts: true
```

### Reusable workflow

From another repository:

```yaml
jobs:
  cloud-eval:
    uses: ganakailabs/cloudeval-action/.github/workflows/cloudeval-reusable.yml@v1
    secrets:
      CLOUDEVAL_ACCESS_KEY: ${{ secrets.CLOUDEVAL_ACCESS_KEY }}
    with:
      mode: ask
      ask_prompt: 'Smoke check: list blocking issues only.'
```

Override `action_repository` / `action_ref` if you fork this action.

## Inputs

| Input | Description |
| ----- | ----------- |
| `access_key` | **Required.** Scoped access key; pass `secrets.CLOUDEVAL_ACCESS_KEY`. |
| `base_url` | Optional API base URL (self-hosted / staging). |
| `mode` | `ask`, `gate`, `agent`, `reports`, or `nightly`. |
| `project_id` | Project id for scoped commands. |
| `ask_prompt` | Prompt for `ask` (required for `ask` unless `agent_task` is used). |
| `agent_task` | Task for `cloudeval agent`; when set, `ask`/`gate`/`nightly` use agent instead of ask where applicable. |
| `gate_threshold` | Required for `gate`; optional for `ask` / `nightly` to fail below threshold. |
| `gate_jq` | jq expression yielding one number (default `.score`). |
| `reports_type` | Passed to `reports run` / `download` (default `all`). |
| `reports_download` | `true` to run `reports download` after `reports run` (default `true`). |
| `reports_output_dir` | Download directory (default `cloudeval-reports`). |
| `working_directory` | Working directory for CLI (default `.`). |
| `cli_install_url` | Install script URL (default official installer). |
| `skip_cli_install` | If `true`, skip installer; `cloudeval` must be on `PATH` (mirrors/tests only). |
| `post_pr_comment` | Update a single PR comment (marker `<!-- cloudeval-action -->`). Needs `pull-requests: write`. |
| `upload_artifacts` | Upload `cloudeval-out` bundle (JSON + summary + reports when present). |
| `artifact_name` | Artifact name (default `cloudeval-output`). |

## Outputs

| Output | Description |
| ------ | ----------- |
| `result` | `pass` or `fail`. |
| `score` | Numeric score when gating ran. |
| `summary_markdown` | Job summary / PR body source. |
| `summary_file` | Path to summary file on the runner. |
| `report_path` | Reports directory when download ran. |
| `json_path` | Captured CLI JSON path when applicable. |

## References

- [Credentials / access key contract (CLI)](https://github.com/ganakailabs/cloudeval-cli/blob/main/docs/credentials-api-contract.md)
- [Auth & security (frontend)](https://github.com/ganakailabs/cloudeval-frontend/blob/main/docs/guides/auth-and-security.md)

## Developing in this repo

- `bash -n scripts/run.sh scripts/pr-comment.sh`
- Workflow **CI** validates `action.yml` and shell syntax.
- To dogfood before publish, use `uses: ./` in a branch workflow in this repository.

See [RELEASING.md](RELEASING.md) for tags and Marketplace.
