# CloudEval access keys in CI

This action authenticates with a **scoped access key** (`cev_<env>_ak_<id>_<secret>`), not a legacy shared API key.

## Issuance

- **Product UI:** Developer workspace → **API & CLI access keys** (`/app/developer`, keys tab).
- **RBAC:** Creating and revoking keys requires `credentials:manage` (see frontend auth guide).
- **One-time secret:** The raw key is shown once; store it only in GitHub **Secrets** (e.g. `CLOUDEVAL_ACCESS_KEY`).

## Runtime verification (backend)

The CLI sends `Authorization: Bearer <access_key>`. The API validates via `verify_access_key` (hash, expiry, revocation, IP allowlist, daily budgets, capabilities, project scope, audit). Details: `cloudeval-cli/docs/credentials-api-contract.md` and `cloudeval-backend` credentials middleware.

## GitHub Actions hygiene

- Prefer **environment secrets** for production repos.
- Use **least-capability** key templates (e.g. CI read-only) when available.
- If your key has an **IP allowlist**, GitHub-hosted runner egress IPs change; use allowlist “any” for GitHub Actions or self-hosted runners with stable egress.
- Rotate keys from the Developer workspace if a secret is exposed.

## Env vars (CLI)

- `CLOUDEVAL_ACCESS_KEY` — preferred for automation.
- `CLOUDEVAL_BASE_URL` — optional; matches action input `base_url`.
- `CLOUDEVAL_API_KEY` — deprecated; migrate to `CLOUDEVAL_ACCESS_KEY`.
