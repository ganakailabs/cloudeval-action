# Releasing CloudEval Action

## Tags

1. Ensure `main` is green (CI on this repo).
2. Create an **immutable** tag: `v1.2.3`.
3. Move the floating tag **`v1`** to that commit for consumers using `@v1`.
4. In GitHub **Releases**, publish the release and opt in to **Publish to Marketplace** when the repo is public and metadata is final.

## Marketplace

- `action.yml` **`name:`** must be unique on the Marketplace (adjust at publish if GitHub rejects it).
- README and SECURITY.md support review and trust signals.

## Pinning dependencies

Workflows in this repo pin third-party actions to **commit SHAs** (see `.github/workflows/*.yml`). Dependabot opens weekly PRs to bump them; review release notes before merge.

## Consumer pinning

- Recommend `uses: ganakailabs/cloudeval-action@v1` for semver-style updates, or `@v1.x.y` / full SHA for strict supply-chain control.
- Reusable workflow callers can set `action_ref` to a SHA.

## Smoke (optional)

In a private test repo, run `mode: ask` with a real `CLOUDEVAL_ACCESS_KEY` and verify job summary + exit 0.
