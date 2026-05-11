# Agent notes — cloudeval-action

- Composite action only: `action.yml` + `scripts/*.sh`. No checked-in secrets.
- Auth: `CLOUDEVAL_ACCESS_KEY` env (set from `inputs.access_key`). Do not log the key.
- CLI install: default `https://cli.cloudeval.ai/install.sh`; pin via `cli_install_url` if needed.
- Machine output: always `--format json` for `ask` / `agent` / `reports run` paths used for gating.
- PR comments: marker `<!-- cloudeval-action -->`; update-in-place for `github-actions[bot]`.
- Reusable workflow must **not** use `uses: ./` for the action step — callers run in another repo; pin `action_repository` / `action_ref`.
