# Brand assets (from cloudeval-frontend)

These files mirror the CloudEval product identity from the Next.js app (`cloudeval-frontend`).

| File | Source |
|------|--------|
| `logo-abstract-cloud-256.png` | Resized from `public/common/logo-abstract-cloud-dark-v3.png` (OpenGraph / marketing logo in [`app/layout.tsx`](https://github.com/ganakailabs/cloudeval-frontend/blob/main/app/layout.tsx)). |
| `logo-favicon.png` | Copy of `public/common/logo-favicon.png` (compact icon). |

The full-resolution originals stay in the frontend repo to avoid bloating this action repo.

**GitHub Action `branding`:** Marketplace only accepts a [Feather icon name](https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#branding) plus a fixed palette color. This repo uses `icon: cloud` and `color: blue` as the closest built-in badge to the product cloud mark.
