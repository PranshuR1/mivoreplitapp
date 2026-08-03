import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

type WebhookRecord = {
  user_id?: string;
  email?: string;
  name?: string;
};

function maskEmail(email: string): string {
  const [local, domain] = email.toLowerCase().split("@", 2);
  if (!local || !domain) return "hidden email";
  return `${local.slice(0, 1)}***@${domain}`;
}

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
      return json(401, { error: "invalid_alert_request" });
    }
  }

  const { data: profile, error: profileError } = await supabase
    .from("user_profiles")
    .select("user_id,email,name")
    .eq("user_id", userID)
    .maybeSingle();
  if (profileError || !profile) return json(404, { error: "user_not_found" });

  const { data: claim, error: claimError } = await supabase.rpc("claim_new_account_alert", {
    input_user_id: userID,
  });
  if (claimError) return json(500, { error: "alert_claim_failed" });
  if (!claim?.claimed) return json(200, { ok: true, duplicate: true });
  const existing = {
    push_status: String(claim.push_status ?? "pending"),
    email_status: String(claim.email_status ?? "pending"),
  };

  const firstName = String(profile.name ?? "New user").trim().split(/\s+/)[0] || "New user";
  const maskedEmail = maskEmail(String(profile.email ?? ""));
  const alertTitle = "New Mivo account";
  const alertBody = `${firstName} (${maskedEmail}) just joined.`;

  let pushStatus = existing?.push_status === "sent" ? "sent" : "unavailable";
  let pushError: string | null = null;
  if (pushStatus !== "sent") {
    try {
      const jwt = await apnsJWT();
      const bundleID = Deno.env.get("APNS_BUNDLE_ID") ?? "app.mivo.com";
      const { data: devices, error: deviceError } = await supabase
        .from("admin_push_devices")
        .select("id,device_token,environment")
        .eq("active", true);
      if (deviceError) throw deviceError;
      if (!devices?.length) throw new Error("no_active_admin_devices");

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
            "apns-push-type": "alert",
            "apns-priority": "10",
          },
          body: JSON.stringify({
            aps: {
              alert: { title: alertTitle, body: alertBody },
              sound: "default",
              category: "MIVO_ADMIN_ACCOUNT",
            },
            mivoRoute: "adminUser",
            userID,
          }),
        });
        if (response.ok) {
          sent += 1;
        } else {
          const failure = await response.json().catch(() => ({}));
          const reason = String(failure.reason ?? `http_${response.status}`);
          failures.push(reason);
          if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
            await supabase.from("admin_push_devices").update({ active: false }).eq("id", device.id);
          }
        }
      }
      pushStatus = sent > 0 ? "sent" : "failed";
      pushError = failures.length ? failures.join(",") : null;
    } catch (error) {
      pushStatus = "failed";
      pushError = error instanceof Error ? error.message : String(error);
    }
  }

  let emailStatus = existing?.email_status === "sent" ? "sent" : "unavailable";
  let emailError: string | null = null;
  if (emailStatus !== "sent") {
    const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const from = Deno.env.get("MIVO_ADMIN_ALERT_FROM_EMAIL") ?? "";
    if (!resendKey || !from) {
      emailStatus = "failed";
      emailError = "email_credentials_missing";
    } else {
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            authorization: `Bearer ${resendKey}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            from,
            to: ["pranshuraithatha0@gmail.com"],
            subject: "New Mivo account created",
            text: `${firstName} (${maskedEmail}) created a Mivo account. Open the protected Mivo admin user database for full details.`,
          }),
        });
        if (!response.ok) throw new Error(`resend_http_${response.status}`);
        emailStatus = "sent";
      } catch (error) {
        emailStatus = "failed";
        emailError = error instanceof Error ? error.message : String(error);
      }
    }
  }

  await supabase.from("admin_account_alerts").update({
    push_status: pushStatus,
    email_status: emailStatus,
    push_error: pushError,
    email_error: emailError,
    completed_at: new Date().toISOString(),
  }).eq("user_id", userID);
  await supabase.from("new_account_alert_jobs").update({
    processed_at: new Date().toISOString(),
  }).eq("user_id", userID);

  return json(200, { ok: true, push_status: pushStatus, email_status: emailStatus });
});
