import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

function json(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function html(status: number, body: string) {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function consentPage(requestId: string, token: string, message = "") {
  const action = `?request=${encodeURIComponent(requestId)}&token=${encodeURIComponent(token)}`;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mivo Parent Consent</title><style>
body{margin:0;background:#FAF3E8;color:#5C3317;font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:680px;margin:0 auto;padding:32px 20px 60px}.brand{display:flex;align-items:center;gap:12px;margin-bottom:28px}
.logo{width:48px;height:48px;border-radius:8px;background:#F0E4CC;display:grid;place-items:center;font-weight:800;color:#B5621E}
h1{font-size:30px;margin:0 0 10px}h2{font-size:18px;margin:26px 0 8px}p,li{line-height:1.55}.card{background:#F0E4CC;border:1px solid #C8A882;border-radius:8px;padding:20px;margin:18px 0}
label{display:block;font-weight:700;margin:14px 0 6px}input[type=text],input[type=file]{box-sizing:border-box;width:100%;padding:13px;border:1px solid #C8A882;border-radius:7px;background:white}
.check{display:flex;gap:10px;align-items:flex-start;margin:18px 0}.check input{margin-top:4px}button{width:100%;padding:15px;border:0;border-radius:8px;background:#D4872A;color:white;font-weight:800;font-size:16px}
.notice{color:#B5621E;font-weight:700}.small{font-size:13px;color:#8B4E28}a{color:#4A6FA5}</style></head>
<body><main><div class="brand"><div class="logo">mivo</div><strong>Parent verification</strong></div>
<h1>Review Mivo's data request</h1>${message ? `<p class="notice">${message}</p>` : ""}
<p>A person under age 13 requested permission to create a Mivo account. Mivo will not create that account or collect Screen Time and behavioral data until an authorized reviewer approves this request.</p>
<div class="card"><h2>Information Mivo may collect after consent</h2><ul>
<li>Account email, first name, and persistent device identifier.</li><li>Selected apps, Screen Time summaries, schedules, sessions, reflections, and intervention activity.</li></ul>
<p>You may later request access, revoke consent, or request deletion by emailing <a href="mailto:info.mivoapp@gmail.com">info.mivoapp@gmail.com</a>.</p></div>
<form method="post" enctype="multipart/form-data" action="${action}">
<label>Your full legal name</label><input required name="parent_name" type="text" autocomplete="name">
<label>Signed consent and identity evidence</label><input required name="evidence" type="file" accept="application/pdf,image/jpeg,image/png">
<p class="small">Upload one PDF, JPEG, or PNG up to 10 MB. Evidence is private, used only for manual verification, and deleted after review.</p>
<label class="check"><input required name="consent" type="checkbox" value="yes"><span>I am the parent or legal guardian, I have reviewed this notice, and I consent to the collection and uses described above.</span></label>
<button type="submit">Submit for Mivo review</button></form>
</main></body></html>`;
}

async function verifyRequest(requestId: string, token: string) {
  const tokenHash = await sha256(token);
  const { data, error } = await supabase
    .from("parental_consent_requests")
    .select("id,status,expires_at,evidence_storage_path,parent_email")
    .eq("id", requestId)
    .eq("request_token_hash", tokenHash)
    .maybeSingle();
  if (error || !data) return null;
  if (new Date(data.expires_at).getTime() <= Date.now()) return null;
  return data;
}

async function sendConsentEmail(parentEmail: string, consentURL: string) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("MIVO_CONSENT_FROM_EMAIL") ?? "Mivo <consent@usemivo.app>";
  if (!apiKey) return false;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: [parentEmail],
      subject: "Review a Mivo parent consent request",
      html: `<p>A person under age 13 requested permission to create a Mivo account.</p><p><a href="${consentURL}">Review the privacy notice and submit consent</a>.</p><p>Mivo will not create the account or collect Screen Time data before approval.</p>`,
    }),
  });
  return response.ok;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const url = new URL(request.url);
  const requestId = url.searchParams.get("request") ?? "";
  const token = url.searchParams.get("token") ?? "";

  if (request.method === "POST" && request.headers.get("content-type")?.includes("application/json")) {
    const body = await request.json();
    const parentEmail = String(body.parent_email ?? "").trim().toLowerCase();
    const birthMonth = Number(body.birth_month);
    const birthYear = Number(body.birth_year);
    if (!parentEmail.includes("@") || birthMonth < 1 || birthMonth > 12 || birthYear < 1900) {
      return json(400, { error: "invalid_parent_request" });
    }
    const id = crypto.randomUUID();
    const requestToken = crypto.randomUUID();
    const { error } = await supabase.from("parental_consent_requests").insert({
      id,
      request_token_hash: await sha256(requestToken),
      parent_email: parentEmail,
      birth_month: birthMonth,
      birth_year: birthYear,
    });
    if (error) return json(500, { error: "request_not_created" });
    const publicBase = Deno.env.get("MIVO_PARENT_CONSENT_URL") ?? `${url.origin}${url.pathname}`;
    const consentURL = `${publicBase}?request=${encodeURIComponent(id)}&token=${encodeURIComponent(requestToken)}`;
    const emailSent = await sendConsentEmail(parentEmail, consentURL);
    return json(201, { request_id: id, request_token: requestToken, status: "pending", email_sent: emailSent });
  }

  if (!requestId || !token) return html(400, "<h1>Invalid Mivo consent link</h1>");
  const record = await verifyRequest(requestId, token);
  if (!record) return html(404, "<h1>This Mivo consent link is invalid or expired.</h1>");

  if (request.method === "GET") {
    return html(200, consentPage(requestId, token, record.evidence_storage_path ? "Evidence received. Mivo review is pending." : ""));
  }

  if (request.method === "POST") {
    const form = await request.formData();
    const evidence = form.get("evidence");
    const parentName = String(form.get("parent_name") ?? "").trim();
    if (!(evidence instanceof File) || !parentName || form.get("consent") !== "yes") {
      return html(400, consentPage(requestId, token, "Complete every field before submitting."));
    }
    const allowed = ["application/pdf", "image/jpeg", "image/png"];
    if (!allowed.includes(evidence.type) || evidence.size > 10 * 1024 * 1024) {
      return html(400, consentPage(requestId, token, "Use one PDF, JPEG, or PNG file no larger than 10 MB."));
    }
    const extension = evidence.type === "application/pdf" ? "pdf" : evidence.type === "image/png" ? "png" : "jpg";
    const path = `${requestId}/evidence.${extension}`;
    const bytes = new Uint8Array(await evidence.arrayBuffer());
    const upload = await supabase.storage.from("parental-consent-evidence").upload(path, bytes, {
      contentType: evidence.type,
      upsert: true,
    });
    if (upload.error) return html(500, consentPage(requestId, token, "The secure upload failed. Please try again."));
    await supabase.from("parental_consent_requests").update({
      evidence_storage_path: path,
      reviewer_note: `Signed submission received from ${parentName}.`,
      updated_at: new Date().toISOString(),
    }).eq("id", requestId);
    return html(200, consentPage(requestId, token, "Your signed consent was submitted securely. Mivo will review it before account creation."));
  }

  return json(405, { error: "method_not_allowed" });
});
