# Agent notes — cloudeval-action

- Composite action: root `action.yml` + `scripts/run.sh` + `scripts/pr-comment.sh`.
- Auth: `CLOUDEVAL_ACCESS_KEY` from `inputs.access_key` only; never log it.
- Gating: `gate_jq` must yield a JSON number (`tonumber`); `gate_operator` is `ge|gt|le|lte|lt|eq|ne`.
- PR comments: marker `<!-- cloudeval-action -->`; update existing `github-actions[bot]` comment; body built via `jq` + temp file for size safety.
- Reusable workflow must pin `uses: ${{ inputs.action_repository }}@${{ inputs.action_ref }}` — never `uses: ./` for the action step when called from another repo.
- Pin third-party actions by SHA in workflows; let Dependabot propose bumps.
- Install step: `curl` retries + timeout; override with `skip_cli_install` for vetted binaries.
