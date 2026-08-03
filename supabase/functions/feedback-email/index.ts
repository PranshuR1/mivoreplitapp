import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const recipient = "info.mivoapp@gmail.com";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = request.headers.get("authorization") ?? "";
  if (!supabaseURL || !anonKey || !serviceKey || !authorization) {
    return json(401, { error: "authentication_required" });
  }

  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json(401, { error: "invalid_session" });

  const body = await request.json().catch(() => ({}));
  const feedbackID = String(body.feedback_id ?? "");
  if (!feedbackID) return json(400, { error: "feedback_id_required" });

  const service = createClient(supabaseURL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: feedback, error: feedbackError } = await service
    .from("feedback_items")
    .select("id,user_id,type,subject,message,app_version,device_info,created_at")
    .eq("id", feedbackID)
    .maybeSingle();
  if (feedbackError || !feedback) return json(404, { error: "feedback_not_found" });
  if (feedback.user_id !== authData.user.id) return json(403, { error: "feedback_access_denied" });

  const { data: existing } = await service
    .from("feedback_email_deliveries")
    .select("status")
    .eq("feedback_id", feedbackID)
    .maybeSingle();
  if (existing?.status === "sent") return json(200, { ok: true, duplicate: true });

  await service.from("feedback_email_deliveries").upsert({
    feedback_id: feedbackID,
    recipient,
    status: "pending",
    error_message: null,
    last_attempted_at: new Date().toISOString(),
    attempt_count: 1,
    updated_at: new Date().toISOString(),
  }, { onConflict: "feedback_id" });

  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const from = Deno.env.get("MIVO_FEEDBACK_FROM_EMAIL")
    ?? Deno.env.get("MIVO_ADMIN_ALERT_FROM_EMAIL")
    ?? "";
  if (!resendKey || !from) {
    await service.from("feedback_email_deliveries").update({
      status: "failed",
      error_message: "email_credentials_missing",
      updated_at: new Date().toISOString(),
    }).eq("feedback_id", feedbackID);
    return json(503, { error: "feedback_email_not_configured" });
  }

  const senderEmail = String(authData.user.email ?? "").trim().toLowerCase();
  const safeSubject = String(feedback.subject ?? "Mivo feedback").trim();
  const safeMessage = String(feedback.message ?? "").trim();
  const type = String(feedback.type ?? "feedback");
  const text = [
    `New Mivo ${type}`,
    `Subject: ${safeSubject}`,
    `From: ${senderEmail || "Signed-in Mivo user"}`,
    `App version: ${feedback.app_version ?? "Unknown"}`,
    `Device: ${feedback.device_info ?? "Unknown"}`,
    "",
    safeMessage,
    "",
    `Feedback ID: ${feedbackID}`,
  ].join("\n");

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${resendKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [recipient],
        reply_to: senderEmail || undefined,
        subject: `[Mivo ${type}] ${safeSubject}`,
        text,
        html: `<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;color:#42210f;line-height:1.5"><h2>New Mivo ${escapeHTML(type)}</h2><p><strong>${escapeHTML(safeSubject)}</strong></p><p>${escapeHTML(safeMessage).replaceAll("\n", "<br>")}</p><hr><p style="font-size:13px;color:#7b624f">From: ${escapeHTML(senderEmail || "Signed-in Mivo user")}<br>App version: ${escapeHTML(String(feedback.app_version ?? "Unknown"))}<br>Device: ${escapeHTML(String(feedback.device_info ?? "Unknown"))}<br>Feedback ID: ${escapeHTML(feedbackID)}</p></div>`,
      }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(String(payload.message ?? `resend_http_${response.status}`));

    await service.from("feedback_email_deliveries").update({
      status: "sent",
      provider_message_id: String(payload.id ?? ""),
      error_message: null,
      sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("feedback_id", feedbackID);
    return json(200, { ok: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await service.from("feedback_email_deliveries").update({
      status: "failed",
      error_message: message.slice(0, 500),
      updated_at: new Date().toISOString(),
    }).eq("feedback_id", feedbackID);
    return json(502, { error: "feedback_email_delivery_failed" });
  }
});
