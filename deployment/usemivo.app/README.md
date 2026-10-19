# usemivo.app deployment

- Serve `.well-known/apple-app-site-association` at exactly `https://usemivo.app/.well-known/apple-app-site-association` with `Content-Type: application/json` and no redirect. It currently claims no universal-link paths.
- Keep HTTPS enabled. Apple verifies the association file before universal links open Mivo directly.
- Rewrite `/accountability/*` to `/accountability/index.html` while preserving the `token` query string. This page displays only the sanitized, expiring weekly summary returned by the Supabase Edge Function.
