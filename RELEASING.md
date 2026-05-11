# Releasing CloudEval Action

## Version tags

1. Merge changes to `main`.
2. Tag a release: `v1.0.0` (immutable) and move floating `v1` to the same commit for Marketplace consumers using `@v1`.
3. In GitHub **Releases**, publish the release and opt in to **Publish to Marketplace** if this repository is public and meets [GitHub’s action rules](https://docs.github.com/actions/creating-actions/publishing-actions-in-github-marketplace).

## Pre-flight

- CI green on `main`.
- `action.yml` `name:` is unique on the Marketplace (adjust at publish if needed).
- README examples use the real org/repo slug (default `ganakailabs/cloudeval-action`).

## Consumer pinning

- Recommend `uses: <org>/cloudeval-action@v1` for automatic minor updates, or `@v1.x.y` for strict pins.
- Reusable workflow callers should pass `action_ref` when they need an exact SHA.

## Smoke (optional)

In a throwaway repo, add a workflow with `CLOUDEVAL_ACCESS_KEY` secret and run `mode: ask` with a minimal prompt; confirm job summary and exit 0.
