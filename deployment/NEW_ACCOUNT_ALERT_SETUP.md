# New Mivo Account Alerts

The database tables, idempotency logic, iOS token registration, push routing, and Edge Function source are implemented. Complete these credential-dependent steps once to activate delivery.

## 1. Create the Apple push key

1. Open Apple Developer, then Certificates, Identifiers & Profiles.
2. Confirm Push Notifications is enabled for App ID `app.mivo.com`.
3. Under Keys, create a key with Apple Push Notifications service enabled.
4. Download the `.p8` file once and record its Key ID.
5. Record the Apple Team ID `45UT26F58Q`.
6. Regenerate the development and App Store provisioning profiles for Mivo.

Never add the `.p8` file to this repository.

## 2. Deploy the Supabase function

From the repository root:

```bash
supabase login
supabase link --project-ref pgmbqxcshgvznxdbpyre

WEBHOOK_SECRET="$(openssl rand -hex 32)"
supabase secrets set \
  APNS_KEY_ID="YOUR_KEY_ID" \
  APNS_TEAM_ID="45UT26F58Q" \
  APNS_PRIVATE_KEY="$(cat /secure/path/AuthKey_YOUR_KEY_ID.p8)" \
  APNS_BUNDLE_ID="app.mivo.com" \
  MIVO_WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  MIVO_ADMIN_ALERT_FROM_EMAIL="Mivo <alerts@usemivo.app>"

supabase functions deploy new-account-alert --no-verify-jwt
```

`RESEND_API_KEY` must also exist in Supabase secrets. The sender address must be on a domain verified in Resend.

Keep the terminal open until the webhook is configured so `$WEBHOOK_SECRET` remains available.

## 3. Create the database webhook

In Supabase Dashboard:

1. Open Database, then Webhooks.
2. Create a webhook named `new-mivo-account-alert`.
3. Select table `public.user_profiles` and event `INSERT`.
4. Use URL `https://pgmbqxcshgvznxdbpyre.supabase.co/functions/v1/new-account-alert`.
5. Add header `x-mivo-webhook-secret` with the value printed by:

```bash
printf '%s\n' "$WEBHOOK_SECRET"
```

The app also requests the function after successful registration as a fallback. The server verifies that the authenticated user matches the new account, and the database claim prevents duplicate push or email delivery.

## 4. Verify

1. Install a signed Mivo build on the founder's physical iPhone.
2. Sign in as `pranshuraithatha0@gmail.com` and allow notifications.
3. In Settings, confirm New-account alerts says Enabled on this device.
4. Create one test account on another device.
5. Confirm one masked push and one masked email arrive.
6. Tap the push and confirm the matching user opens in Mivo's protected user database.
