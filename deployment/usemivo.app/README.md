# usemivo.app referral deployment

- Serve `.well-known/apple-app-site-association` at exactly `https://usemivo.app/.well-known/apple-app-site-association` with `Content-Type: application/json` and no redirect.
- Rewrite `/r/*` to `/r/index.html` while preserving the original path.
- Serve `/events/referral-challenge` from `/events/referral-challenge/index.html`. This is the App Store In-App Event deep link and opens Mivo's Referral Hub.
- Keep HTTPS enabled. Apple verifies the association file before universal links open Mivo directly.
- The fallback page uses `mivo://referral?code=...` and otherwise leaves visitors on `usemivo.app`.
- Rewrite `/accountability/*` to `/accountability/index.html` while preserving the `token` query string. This page displays only the sanitized, expiring weekly summary returned by the Supabase Edge Function.
