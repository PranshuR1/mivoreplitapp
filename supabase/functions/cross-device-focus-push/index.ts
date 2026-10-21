// Wakes the iPhone with a silent push when the Mac starts or ends a
// "Block my iPhone too" session, so CrossDeviceFocusService.reconcile()
// can run and apply/clear the shield even while the phone is locked or
// the app is backgrounded — the gap documented in
// FamilyControlsManager.scheduleCrossDeviceFocusBackgroundCheck(), whose
// BGAppRefreshTask has no delivery guarantee and a 15-minute-minimum
// delay. A silent (content-available) push has no such minimum.
//
// Reuses the exact APNs JWT + send pattern already proven in
// new-account-alert/index.ts, and the same dual auth path: a trusted
// caller (this project's own Mac client, or a future DB webhook) sends
// x-mivo-webhook-secret; anything else must present the session's own
// user JWT and can only ever push to its own account.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

type WebhookRecord = {
  user_id?: string;
  id?: string;
  status?: string;
  ends_at?: string;
};

async function apnsJWT(): Promise<string> {
  const keyID = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamID = Deno.env.get("APNS_TEAM_ID") ?? "";
  const rawKey = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  if (!keyID || !teamID || !rawKey) throw new Error("apns_credentials_missing");
  const key = await importPKCS8(rawKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt()
    .sign(key);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseURL || !serviceKey) return json(500, { error: "supabase_service_not_configured" });
  const supabase = createClient(supabaseURL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const payload = await request.json().catch(() => ({}));
  const record: WebhookRecord = payload.record ?? payload;
  const userID = String(record.user_id ?? "");
  if (!userID) return json(400, { error: "user_id_required" });

  const expectedSecret = Deno.env.get("MIVO_WEBHOOK_SECRET") ?? "";
  const validWebhook = Boolean(expectedSecret)
    && request.headers.get("x-mivo-webhook-secret") === expectedSecret;
  if (!validWebhook) {
    const authorization = request.headers.get("authorization") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!authorization || !anonKey) return json(401, { error: "authentication_required" });
    const userClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || authData.user?.id !== userID) {
      return json(401, { error: "invalid_push_request" });
    }
  }

  const { data: devices, error: deviceError } = await supabase
    .from("user_push_devices")
    .select("user_id,installation_id,device_token,environment")
    .eq("user_id", userID);
  if (deviceError) return json(500, { error: "device_lookup_failed" });
  if (!devices?.length) return json(200, { ok: true, sent: 0, reason: "no_registered_devices" });

  let jwt: string;
  try {
    jwt = await apnsJWT();
  } catch (error) {
    return json(500, { error: error instanceof Error ? error.message : String(error) });
  }
  const bundleID = Deno.env.get("APNS_BUNDLE_ID") ?? "app.mivo.com";

  let sent = 0;
  const failures: string[] = [];
  for (const device of devices) {
    const host = device.environment === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";
    const response = await fetch(`${host}/3/device/${device.device_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleID,
        // Silent push: no banner, no sound — this exists purely to wake
        // the app so it can reconcile the cross-device focus command
        // itself. Apple requires priority 5 (not 10) for background pushes.
        "apns-push-type": "background",
        "apns-priority": "5",
      },
      body: JSON.stringify({
        aps: { "content-available": 1 },
        mivoRoute: "crossDeviceFocus",
      }),
    });
    if (response.ok) {
      sent += 1;
      continue;
    }
    const failure = await response.json().catch(() => ({}));
    const reason = String(failure.reason ?? `http_${response.status}`);
    failures.push(reason);
    if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
      // Stale token — the app re-registers a fresh one on next launch, so
      // just drop the dead row rather than tracking an "active" flag.
      await supabase
        .from("user_push_devices")
        .delete()
        .eq("user_id", device.user_id)
        .eq("installation_id", device.installation_id);
    }
  }

  return json(200, { ok: true, sent, attempted: devices.length, failures });
});
