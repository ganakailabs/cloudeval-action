# Security

## Reporting

Please report vulnerabilities through your organization’s standard channel or contact the CloudEval maintainers privately. Do not file public issues for undisclosed security problems.

## Using this action safely

- Store **only** [scoped access keys](docs/ci-access-keys.md) (`cev_…`) in GitHub **Secrets** or **environments**, never in workflow YAML.
- **Fork PRs:** `GITHUB_TOKEN` often cannot post PR comments or may be read-only; failures are expected—use same-repo PRs or a PAT with minimal scope if policy allows.
- The install step runs the official CLI installer over HTTPS; pin `cli_install_url` or set `skip_cli_install` and supply `cloudeval` on `PATH` if your policy requires a vetted binary.
- Enable **branch protection** and **required reviews** on this repository; use Dependabot updates for workflow dependencies.

## Supply chain

- Third-party actions in this repo are pinned to full commit SHAs where feasible (see `.github/workflows`).
- Dependabot proposes updates weekly; review changelogs before merging.
