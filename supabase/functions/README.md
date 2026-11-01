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

## Spots orders

Apply `20261028120000_spot_orders.sql` and `20261028130000_spot_order_picks.sql` (apply the second before deploying a function version that saves `spot_picks`), then deploy the Stripe webhook receiver with JWT verification off (Stripe signs each request instead):

```sh
supabase functions deploy stripe-spot-orders --no-verify-jwt
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
```

In the Stripe Dashboard (Developers, Webhooks, Add destination) send `checkout.session.completed`, `checkout.session.async_payment_succeeded` and `charge.refunded` to `https://<project-ref>.supabase.co/functions/v1/stripe-spot-orders`, and copy the signing secret into `STRIPE_WEBHOOK_SECRET`. The function uses the runtime-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

Every paid checkout emails `pranshuraithatha@gmail.com` with what was bought, the total, the shipping address and a Stripe link. It sends through Gmail's SMTP server (smtp.gmail.com, port 465 with TLS; Supabase blocks outgoing ports 25 and 587), using `denomailer`. Set `GMAIL_APP_PASSWORD` to an app password for the sending account (Google Account, Security, App passwords, which needs 2-step verification; Google shows it as four groups of four letters, and spaces are stripped). The sending account is `GMAIL_USER`, default `info.mivoapp@gmail.com`, so the mail arrives from a different address than the one it goes to and your phone notifies. Override the recipient with `MIVO_ORDER_ALERT_TO`. If the order cannot be saved, the email still goes out with a warning, and Stripe's retries repeat it until the save works. To name products other than the two known links, set `STRIPE_SECRET_KEY` to a restricted key that can read Checkout Sessions; without it those show as "an item this function does not recognize" with the Stripe link. Check the function logs for `order_alert_not_sent` or `order_alert_failed` if no email arrives.

Customers see their orders on usemivo.app/account through `my_spot_orders()`. When you mail one, mark it:

```sql
select public.admin_update_spot_order('ABCD1234', 'mailed', 'https://tools.usps.com/go/TrackConfirmAction?tLabels=...');
```

The Payment Link ids are in the function's `PAYMENT_LINKS` map; add new ones there (or rely on the price fallback: $14.99 is one Spot, $34.99 three, $54.99 five, $99.99 ten).

Buyers pick a place for each Spot on usemivo.app/shop. The picks arrive in the Payment Link's `client_reference_id` (`[<account id>_]p_desk_blank_car`), are saved in `spot_orders.spot_picks`, and are listed in the order email so you can write them on the card. The place list lives in two spots that must match: `PLACES` in `stripe-spot-orders/index.ts` and `data/spot-places.ts` in the website repo.

## Study sync and rooms

Apply `20261029120000_study_sync_and_rooms.sql`. There is no Edge Function: the iPhone app and usemivo.app call its functions directly with the signed-in user's token, and two of them (`study_room_view`, `study_room_sit`) can also be called without signing in, which is how a friend opens a study room link with no account.

- `sync_study_sessions` / `my_study_sessions` keep each finished study session (task, start, end, seconds on video) on the account, so the app and the website show the same streak. They cannot credit scroll time; that stays on the phone.
- The room is one row per person, closed until they open it, and live only while their phone or browser has pinged `study_room_ping` in the last two minutes.
- Until the migration is applied, the app hides the study room card and keeps syncing quietly, and the website shows "Study sync is on its way".

The migration is re-runnable. Visitor names are kept only while someone is on the page and are deleted after a day. Account deletion removes the sessions and the room (they reference `auth.users` with `on delete cascade`).
