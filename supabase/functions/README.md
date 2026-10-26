# Mivo Supabase Functions

Deploy the parent-consent endpoint after applying `supabase_schema.sql`:

```sh
supabase functions deploy parental-consent --no-verify-jwt
supabase secrets set RESEND_API_KEY=... MIVO_CONSENT_FROM_EMAIL="Mivo <consent@usemivo.app>"
```

`MIVO_PARENT_CONSENT_URL` is optional. When omitted, the function uses its own public URL for the secure parent form.

The function uses the runtime-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key in the iOS app.
# New-account alerts

Deploy `new-account-alert` with JWT verification disabled, then configure a Supabase Database Webhook for `INSERT` events on `public.user_profiles`:

- URL: `https://<project-ref>.supabase.co/functions/v1/new-account-alert`
- Header: `x-mivo-webhook-secret: <MIVO_WEBHOOK_SECRET>`
- Secrets: `MIVO_WEBHOOK_SECRET`, `RESEND_API_KEY`, `MIVO_ADMIN_ALERT_FROM_EMAIL`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, and `APNS_BUNDLE_ID=app.mivo.com`

The function verifies that the profile exists and uses `admin_account_alerts` as an idempotency record, so webhook retries do not duplicate completed deliveries.
Newly registered iOS clients also request the same function with their authenticated user token as a delivery fallback. The function accepts that request only when the token belongs to the newly created user.

## Product expansion functions

Apply `20260713133000_complete_product_admin_expansion.sql`, then deploy:

```sh
supabase functions deploy accountability-summary --no-verify-jwt
supabase functions deploy app-store-analytics-import --no-verify-jwt
```

Accountability secrets: `RESEND_API_KEY`, `MIVO_ACCOUNTABILITY_FROM_EMAIL`, and a random `MIVO_ACCOUNTABILITY_CRON_SECRET`. Schedule a weekly authenticated POST with `{"action":"deliver_due"}` and the matching `x-mivo-cron-secret` header. Only connections that the user previewed and explicitly enabled are delivered.

App Store import secrets: `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY`, `ASC_APP_ID`, and a random `MIVO_ANALYTICS_CRON_SECRET`. The first ongoing Apple report request usually takes one to two days. Schedule this endpoint daily; absent or privacy-suppressed values remain unavailable rather than becoming zero.

The App Store Connect key must have an Apple role permitted to read Analytics Reports. Keep all private keys and Supabase service credentials in Edge Function secrets, never in the iPhone app.

## Feedback email delivery

Apply `20260721100000_feedback_email_delivery.sql`, then deploy:

```sh
supabase functions deploy feedback-email --no-verify-jwt
supabase secrets set MIVO_FEEDBACK_FROM_EMAIL="Mivo Feedback <feedback@usemivo.app>"
```

The function reuses `RESEND_API_KEY`, sends each saved feedback item once to
`info.mivoapp@gmail.com`, and sets the signed-in user's email as Reply-To. The
sender address must belong to a domain verified in Resend.

## Lock-in

Apply `20261025120000_lock_in_keyholder.sql`, then deploy both functions with JWT verification off (each checks the caller's token itself, and the keyholder's emailed link carries no account):

```sh
supabase functions deploy lockin-keyholder --no-verify-jwt
supabase functions deploy lockin-milo --no-verify-jwt
supabase secrets set ANTHROPIC_API_KEY=... MIVO_LOCKIN_FROM_EMAIL="Mivo <lockin@usemivo.app>"
```

`lockin-keyholder` also needs `RESEND_API_KEY` (already set for the other mail functions). It emails a keyholder an invite link and, later, unlock requests; both open `https://usemivo.app/keyholder/?token=…`, which is `app/keyholder` in the website repo — deploy that too.

`lockin-milo` is Milo's judgment of what a person shows. Photos are passed to the model once and are neither stored nor logged; only a per-user call count is kept (60 a day). Never put the Anthropic key in the iOS app.
