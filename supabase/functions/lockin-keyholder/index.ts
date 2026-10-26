import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Lock-in keyholders. Two audiences share this function:
//
//   * The signed-in owner (JWT): invite a keyholder, check whether they've agreed,
//     revoke them, ask them to unlock, and read their answer.
//   * The keyholder (a random token from an emailed link, no account): read what they
//     are being asked, then agree, approve or decline.
//
// Tokens are random and only their SHA-256 is stored.

const origin = "https://usemivo.app";
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "access-control-allow-origin": origin },
});

const encoder = new TextEncoder();

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function validEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

function maskEmail(value: string): string {
  const [local, domain] = value.toLowerCase().split("@", 2);
  return local && domain ? `${local.slice(0, 1)}***@${domain}` : "hidden email";
}

/** User-written text that ends up in an email or a web page: one tidy line, no control characters. */
function clean(value: unknown, max: number): string {
  return String(value ?? "")
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

const DAY_MS = 86_400_000;
const MAX_INVITES_PER_DAY = 5;
const MAX_REQUESTS_PER_LOCK = 3;
const MAX_REQUESTS_PER_DAY = 12;
const INVITE_TTL_MS = 14 * DAY_MS;

async function sendEmail(to: string, subject: string, text: string): Promise<boolean> {
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const from = Deno.env.get("MIVO_LOCKIN_FROM_EMAIL") ?? "";
  if (!resendKey || !from) return false;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${resendKey}`, "content-type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject, text }),
  });
  return response.ok;
}

const linkFor = (token: string) => `${origin}/keyholder?token=${encodeURIComponent(token)}`;

type Keyholder = {
  id: string; owner_user_id: string; owner_name: string; keyholder_name: string; keyholder_email: string;
  status: "pending" | "active" | "revoked"; created_at: string; accepted_at: string | null;
};

type UnlockRequest = {
  id: string; keyholder_id: string; owner_user_id: string; lock_id: string; task: string; summary: string;
  status: "pending" | "approved" | "declined" | "expired"; keyholder_note: string | null;
  ends_at: string; created_at: string; decided_at: string | null;
};

/** A request whose lock has already ended can no longer be approved. */
function effectiveStatus(request: UnlockRequest): UnlockRequest["status"] {
  if (request.status === "pending" && new Date(request.ends_at) <= new Date()) return "expired";
  return request.status;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": origin,
        "access-control-allow-headers": "authorization,content-type,apikey",
        "access-control-allow-methods": "GET,POST,OPTIONS",
      },
    });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseURL || !serviceKey) return json(500, { error: "service_not_configured" });
  const service = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  // MARK: The keyholder's page (no account, a token from the email)

  if (request.method === "GET") {
    const token = new URL(request.url).searchParams.get("token") ?? "";
    if (token.length < 32) return json(400, { error: "invalid_link" });
    const view = await keyholderView(service, token);
    return view ? json(200, view) : json(410, { error: "link_expired_or_revoked" });
  }

  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;

  if (typeof body.token === "string") {
    return await keyholderDecision(service, body.token, String(body.decision ?? ""), clean(body.note, 200));
  }

  // MARK: The owner (signed in)

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization || !anonKey) return json(401, { error: "authentication_required" });
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const userID = authData.user?.id;
  if (authError || !userID) return json(401, { error: "authentication_required" });
  const ownerEmail = authData.user?.email?.toLowerCase() ?? "";

  switch (body.action) {
    case "invite": return await invite(service, userID, ownerEmail, body);
    case "keyholder_status": return await keyholderStatus(service, userID, String(body.keyholder_id ?? ""));
    case "revoke": return await revoke(service, userID, String(body.keyholder_id ?? ""));
    case "request_unlock": return await requestUnlock(service, userID, body);
    case "request_status": return await requestStatus(service, userID, String(body.request_id ?? ""));
    default: return json(400, { error: "unsupported_action" });
  }
});

// deno-lint-ignore no-explicit-any
type Service = any;

// MARK: Owner actions

async function invite(service: Service, userID: string, ownerEmail: string, body: Record<string, unknown>) {
  const name = clean(body.keyholder_name, 40);
  const email = clean(body.keyholder_email, 254).toLowerCase();
  const ownerName = clean(body.owner_name, 40);
  if (!name || !validEmail(email)) return json(400, { error: "valid_email_required" });
  if (email === ownerEmail) return json(400, { error: "keyholder_must_be_someone_else" });

  const since = new Date(Date.now() - DAY_MS).toISOString();
  const { count } = await service.from("lock_in_keyholders").select("id", { count: "exact", head: true })
    .eq("owner_user_id", userID).gte("created_at", since);
  if ((count ?? 0) >= MAX_INVITES_PER_DAY) return json(429, { error: "rate_limited" });

  // A new keyholder replaces the old one.
  await service.from("lock_in_keyholders").update({ status: "revoked", revoked_at: new Date().toISOString() })
    .eq("owner_user_id", userID).neq("status", "revoked");

  const token = randomToken();
  const inserted = await service.from("lock_in_keyholders").insert({
    owner_user_id: userID, owner_name: ownerName, keyholder_name: name, keyholder_email: email,
    invite_token_hash: await sha256(token),
  }).select("id,status").single();
  if (inserted.error) return json(500, { error: "invite_failed" });

  const who = ownerName || "A friend";
  const sent = await sendEmail(
    email,
    `${who} would like you to be their keyholder`,
    `Hi ${name},\n\n${who} is using Mivo to stay off their phone while they get something done. ` +
      `They'd like you to be their keyholder: when they say they're finished, you decide whether to unlock their apps.\n\n` +
      `You don't need the app or an account. When they ask, you'll get an email with what they did and one button to approve or decline.\n\n` +
      `Agree to be their keyholder: ${linkFor(token)}\n\n` +
      `The link works for 14 days. If you don't know ${who}, ignore this email and nothing happens.`,
  );
  if (!sent) {
    await service.from("lock_in_keyholders").delete().eq("id", inserted.data.id);
    return json(502, { error: "email_delivery_failed" });
  }

  return json(200, { id: inserted.data.id, name, email_masked: maskEmail(email), status: "pending" });
}

async function ownedKeyholder(service: Service, userID: string, id: string): Promise<Keyholder | null> {
  if (!id) return null;
  const { data } = await service.from("lock_in_keyholders").select("*").eq("id", id).eq("owner_user_id", userID).maybeSingle();
  return data as Keyholder | null;
}

async function keyholderStatus(service: Service, userID: string, id: string) {
  const keyholder = await ownedKeyholder(service, userID, id);
  if (!keyholder) return json(404, { error: "not_found" });
  return json(200, {
    id: keyholder.id, name: keyholder.keyholder_name, email_masked: maskEmail(keyholder.keyholder_email),
    status: keyholder.status,
  });
}

async function revoke(service: Service, userID: string, id: string) {
  const keyholder = await ownedKeyholder(service, userID, id);
  if (!keyholder) return json(404, { error: "not_found" });
  const now = new Date().toISOString();
  await service.from("lock_in_keyholders").update({ status: "revoked", revoked_at: now }).eq("id", id);
  // Anything they were still being asked can no longer be approved.
  await service.from("lock_in_unlock_requests").update({ status: "expired", decided_at: now })
    .eq("keyholder_id", id).eq("status", "pending");
  return json(200, {});
}

async function requestUnlock(service: Service, userID: string, body: Record<string, unknown>) {
  const keyholder = await ownedKeyholder(service, userID, String(body.keyholder_id ?? ""));
  if (!keyholder || keyholder.status !== "active") return json(409, { error: "keyholder_not_active" });

  const lockID = clean(body.lock_id, 64);
  const task = clean(body.task, 80);
  const summary = clean(body.summary, 400);
  const ownerName = clean(body.owner_name, 40) || keyholder.owner_name;
  const endsAt = new Date(String(body.ends_at ?? ""));
  if (!lockID || !task || !summary || Number.isNaN(endsAt.getTime())) return json(400, { error: "invalid_request" });
  if (endsAt <= new Date()) return json(409, { error: "lock_already_ended" });

  const { data: forLock } = await service.from("lock_in_unlock_requests").select("id,status")
    .eq("owner_user_id", userID).eq("lock_id", lockID);
  if ((forLock ?? []).some((row: { status: string }) => row.status === "pending")) return json(409, { error: "request_pending" });
  if ((forLock ?? []).length >= MAX_REQUESTS_PER_LOCK) return json(429, { error: "rate_limited" });

  const since = new Date(Date.now() - DAY_MS).toISOString();
  const { count } = await service.from("lock_in_unlock_requests").select("id", { count: "exact", head: true })
    .eq("owner_user_id", userID).gte("created_at", since);
  if ((count ?? 0) >= MAX_REQUESTS_PER_DAY) return json(429, { error: "rate_limited" });

  const token = randomToken();
  const inserted = await service.from("lock_in_unlock_requests").insert({
    keyholder_id: keyholder.id, owner_user_id: userID, lock_id: lockID, task, summary,
    token_hash: await sha256(token), ends_at: endsAt.toISOString(),
  }).select("id,status,created_at").single();
  if (inserted.error) return json(500, { error: "request_failed" });

  const who = ownerName || "Your friend";
  const sent = await sendEmail(
    keyholder.keyholder_email,
    `${who} is asking you to unlock their apps`,
    `Hi ${keyholder.keyholder_name},\n\n${who} says they're done with: "${task}"\n\n` +
      `What they showed: ${summary}\n\n` +
      `Approve or decline here: ${linkFor(token)}\n\n` +
      `Their apps open as soon as you approve. If you decline, they can keep going and ask again. ` +
      `This request stops working at ${endsAt.toUTCString()}, when their lock ends anyway.`,
  );
  if (!sent) {
    await service.from("lock_in_unlock_requests").delete().eq("id", inserted.data.id);
    return json(502, { error: "email_delivery_failed" });
  }

  return json(200, { id: inserted.data.id, status: "pending", note: null, created_at: inserted.data.created_at });
}

async function requestStatus(service: Service, userID: string, id: string) {
  if (!id) return json(400, { error: "invalid_request" });
  const { data } = await service.from("lock_in_unlock_requests").select("*")
    .eq("id", id).eq("owner_user_id", userID).maybeSingle();
  const row = data as UnlockRequest | null;
  if (!row) return json(404, { error: "not_found" });
  return json(200, {
    id: row.id, status: effectiveStatus(row), note: row.keyholder_note, created_at: row.created_at, summary: row.summary,
  });
}

// MARK: Keyholder side

async function keyholderView(service: Service, token: string) {
  const hash = await sha256(token);

  const { data: invite } = await service.from("lock_in_keyholders").select("*").eq("invite_token_hash", hash).maybeSingle();
  if (invite) {
    const row = invite as Keyholder;
    const expired = row.status === "pending" && Date.now() - new Date(row.created_at).getTime() > INVITE_TTL_MS;
    if (row.status === "revoked" || expired) return null;
    return {
      kind: "invite", owner_name: row.owner_name, keyholder_name: row.keyholder_name,
      status: row.status === "active" ? "agreed" : "waiting",
    };
  }

  const { data: found } = await service.from("lock_in_unlock_requests")
    .select("*, lock_in_keyholders!inner(keyholder_name, owner_name, status)").eq("token_hash", hash).maybeSingle();
  if (!found) return null;
  const row = found as UnlockRequest & { lock_in_keyholders: { keyholder_name: string; owner_name: string; status: string } };
  if (row.lock_in_keyholders.status === "revoked") return null;
  return {
    kind: "request", owner_name: row.lock_in_keyholders.owner_name, keyholder_name: row.lock_in_keyholders.keyholder_name,
    task: row.task, summary: row.summary, ends_at: row.ends_at, note: row.keyholder_note,
    status: effectiveStatus(row),
  };
}

async function keyholderDecision(service: Service, token: string, decision: string, note: string) {
  if (token.length < 32) return json(400, { error: "invalid_link" });
  const hash = await sha256(token);
  const now = new Date().toISOString();

  if (decision === "accept") {
    const { data } = await service.from("lock_in_keyholders").select("*").eq("invite_token_hash", hash).maybeSingle();
    const row = data as Keyholder | null;
    if (!row || row.status === "revoked") return json(410, { error: "link_expired_or_revoked" });
    if (row.status === "pending") {
      if (Date.now() - new Date(row.created_at).getTime() > INVITE_TTL_MS) return json(410, { error: "link_expired_or_revoked" });
      await service.from("lock_in_keyholders").update({ status: "active", accepted_at: now }).eq("id", row.id).eq("status", "pending");
    }
    return json(200, { status: "agreed" });
  }

  if (decision !== "approve" && decision !== "decline") return json(400, { error: "unsupported_decision" });

  const { data } = await service.from("lock_in_unlock_requests")
    .select("*, lock_in_keyholders!inner(status)").eq("token_hash", hash).maybeSingle();
  const row = data as (UnlockRequest & { lock_in_keyholders: { status: string } }) | null;
  if (!row || row.lock_in_keyholders.status === "revoked") return json(410, { error: "link_expired_or_revoked" });

  const status = effectiveStatus(row);
  // Answered already (or ended): report what stands, change nothing.
  if (status !== "pending") return json(200, { status });

  const next = decision === "approve" ? "approved" : "declined";
  await service.from("lock_in_unlock_requests")
    .update({ status: next, keyholder_note: note || null, decided_at: now })
    .eq("id", row.id).eq("status", "pending");
  return json(200, { status: next });
}
