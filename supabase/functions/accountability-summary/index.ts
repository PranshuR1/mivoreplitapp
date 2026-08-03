import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "access-control-allow-origin": "https://usemivo.app" },
});

const encoder = new TextEncoder();
const allowedSummaryKeys = new Set([
  "id", "connectionId", "weekStart", "weekEnd", "plannedMinutes", "reflectedDays",
  "truthAccuracyTrend", "experimentStatus", "encouragement", "expiresAt", "sentAt",
]);

type ConnectionRecord = {
  id: string;
  status: "pending" | "active" | "revoked";
  created_at: string;
  revoked_at: string | null;
};

function validEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

function maskEmail(value: string): string {
  const [local, domain] = value.toLowerCase().split("@", 2);
  return local && domain ? `${local.slice(0, 1)}***@${domain}` : "hidden email";
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function sanitizeSummary(raw: Record<string, unknown>): Record<string, unknown> {
  const summary: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (allowedSummaryKeys.has(key)) summary[key] = value;
  }
  return summary;
}

async function sendSummaryEmail(partnerEmail: string, token: string): Promise<boolean> {
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const from = Deno.env.get("MIVO_ACCOUNTABILITY_FROM_EMAIL") ?? "";
  if (!resendKey || !from) return false;
  const link = `https://usemivo.app/accountability/?token=${encodeURIComponent(token)}`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${resendKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      from, to: [partnerEmail], subject: "A private weekly Mivo summary was shared with you",
      text: `Open the private summary: ${link}\n\nIt contains high-level progress only. The link expires in 14 days and can be revoked at any time.`,
    }),
  });
  return response.ok;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "https://usemivo.app", "access-control-allow-headers": "authorization,content-type" } });
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseURL || !serviceKey) return json(500, { error: "service_not_configured" });
  const service = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  if (request.method === "GET") {
    const token = new URL(request.url).searchParams.get("token") ?? "";
    if (token.length < 32) return json(400, { error: "invalid_link" });
    const tokenHash = await sha256(token);
    const { data, error } = await service.from("accountability_summaries")
      .select("summary,week_start,week_end,expires_at,revoked_at,accountability_connections!inner(status)")
      .eq("token_hash", tokenHash).maybeSingle();
    const related = Array.isArray(data?.accountability_connections)
      ? data.accountability_connections[0]
      : data?.accountability_connections;
    if (error || !data || data.revoked_at || new Date(data.expires_at) <= new Date() || related?.status === "revoked") {
      return json(410, { error: "link_expired_or_revoked" });
    }
    return json(200, { week_start: data.week_start, week_end: data.week_end, summary: sanitizeSummary(data.summary ?? {}) });
  }

  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const body = await request.json().catch(() => ({}));

  if (body.action === "deliver_due") {
    const expectedSecret = Deno.env.get("MIVO_ACCOUNTABILITY_CRON_SECRET") ?? "";
    if (!expectedSecret || request.headers.get("x-mivo-cron-secret") !== expectedSecret) {
      return json(401, { error: "invalid_scheduler_secret" });
    }
    const { data: connections, error: connectionError } = await service.from("accountability_connections")
      .select("id,owner_user_id,partner_email").eq("status", "active").eq("automatic_sharing_enabled", true)
      .not("preview_confirmed_at", "is", null);
    if (connectionError) return json(500, { error: "connections_unavailable" });
    const now = new Date();
    const daysSinceMonday = (now.getUTCDay() + 6) % 7;
    const weekStartDate = new Date(now.getTime() - daysSinceMonday * 86400000);
    const weekStart = weekStartDate.toISOString().slice(0, 10);
    const weekEnd = new Date(weekStartDate.getTime() + 6 * 86400000).toISOString().slice(0, 10);
    let delivered = 0;
    for (const connection of connections ?? []) {
      const { data: existing } = await service.from("accountability_summaries").select("id")
        .eq("connection_id", connection.id).eq("week_start", weekStart).maybeSingle();
      if (existing) continue;
      const [sessionResult, truthResult, experimentResult] = await Promise.all([
        service.from("sessions").select("date,planned_duration,reflection").eq("user_id", connection.owner_user_id).gte("date", weekStart).lte("date", weekEnd),
        service.from("truth_checks").select("guess,actual").eq("user_id", connection.owner_user_id).gte("date", weekStart).lte("date", weekEnd),
        service.from("weekly_experiments").select("status,starts_at,ends_at").eq("user_id", connection.owner_user_id).order("updated_at", { ascending: false }).limit(1),
      ]);
      const sessions = sessionResult.data ?? [];
      const checks = truthResult.data ?? [];
      const averageError = checks.length
        ? Math.round(checks.reduce((sum, item) => sum + Math.abs(item.actual - item.guess), 0) / checks.length)
        : null;
      const summary = {
        id: crypto.randomUUID(), connectionId: connection.id, weekStart, weekEnd,
        plannedMinutes: sessions.reduce((sum, item) => sum + Number(item.planned_duration ?? 0), 0),
        reflectedDays: new Set(sessions.filter((item) => item.reflection !== null).map((item) => item.date)).size,
        truthAccuracyTrend: averageError === null ? "No truth trend yet" : `Average estimate was within ${averageError} minutes`,
        experimentStatus: experimentResult.data?.[0]?.status === "active" ? "An approved experiment is active" : "No active experiment",
        encouragement: "A steady week of noticing patterns and choosing intentionally.",
        expiresAt: new Date(now.getTime() + 14 * 86400000).toISOString(), sentAt: null,
      };
      const token = randomToken();
      const inserted = await service.from("accountability_summaries").insert({
        connection_id: connection.id, owner_user_id: connection.owner_user_id,
        week_start: weekStart, week_end: weekEnd, summary, token_hash: await sha256(token), expires_at: summary.expiresAt,
      }).select("id").single();
      if (inserted.error) continue;
      if (await sendSummaryEmail(connection.partner_email, token)) {
        delivered += 1;
        await service.from("accountability_summaries").update({ sent_at: new Date().toISOString() }).eq("id", inserted.data.id);
      } else {
        await service.from("accountability_summaries").delete().eq("id", inserted.data.id);
      }
    }
    return json(200, { ok: true, delivered });
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization || !anonKey) return json(401, { error: "authentication_required" });
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const userID = authData.user?.id;
  if (authError || !userID) return json(401, { error: "authentication_required" });

  if (body.action !== "invite") return json(400, { error: "unsupported_action" });
  const partnerEmail = String(body.partner_email ?? "").trim().toLowerCase();
  if (!validEmail(partnerEmail)) return json(400, { error: "valid_partner_email_required" });
  if (partnerEmail === authData.user?.email?.toLowerCase()) return json(400, { error: "partner_must_be_someone_else" });
  const summary = sanitizeSummary((body.summary ?? {}) as Record<string, unknown>);
  const weekStart = String(summary.weekStart ?? "");
  const weekEnd = String(summary.weekEnd ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(weekStart) || !/^\d{4}-\d{2}-\d{2}$/.test(weekEnd)) {
    return json(400, { error: "invalid_summary_dates" });
  }

  const partnerHash = await sha256(partnerEmail);
  const { data: existing } = await service.from("accountability_connections")
    .select("id,status,created_at,revoked_at").eq("owner_user_id", userID).eq("partner_email_hash", partnerHash).maybeSingle();
  let connection = existing as ConnectionRecord | null;
  if (!connection) {
    const inserted = await service.from("accountability_connections").insert({
      owner_user_id: userID, partner_email: partnerEmail, partner_email_hash: partnerHash,
    }).select("id,status,created_at,revoked_at").single();
    if (inserted.error) return json(500, { error: "connection_create_failed" });
    connection = inserted.data as ConnectionRecord | null;
  } else if (connection.status === "revoked") {
    const restored = await service.from("accountability_connections").update({ status: "pending", revoked_at: null })
      .eq("id", connection.id).select("id,status,created_at,revoked_at").single();
    connection = restored.data as ConnectionRecord | null;
  }
  if (!connection) return json(500, { error: "connection_create_failed" });

  const token = randomToken();
  const expiresAt = new Date(Date.now() + 14 * 86400000).toISOString();
  const tokenHash = await sha256(token);
  await service.from("accountability_summaries").delete().eq("connection_id", connection.id).eq("week_start", weekStart);
  const insertedSummary = await service.from("accountability_summaries").insert({
    connection_id: connection.id, owner_user_id: userID, week_start: weekStart, week_end: weekEnd,
    summary, token_hash: tokenHash, expires_at: expiresAt,
  }).select("id").single();
  if (insertedSummary.error) return json(500, { error: "summary_create_failed" });

  if (!await sendSummaryEmail(partnerEmail, token)) return json(502, { error: "email_delivery_failed" });
  await service.from("accountability_summaries").update({ sent_at: new Date().toISOString() }).eq("id", insertedSummary.data.id);

  return json(200, {
    id: connection.id, partner_email_masked: maskEmail(partnerEmail), status: connection.status,
    automatic_sharing_enabled: false, created_at: connection.created_at, revoked_at: connection.revoked_at,
  });
});
