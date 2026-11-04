import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Mivo's own AI. The app builds the prompt (it picks the notes on the phone) and this
// function passes it to Mivo's model server, a private Hugging Face Space running
// llama.cpp. The Hugging Face token lives here as a secret, never in the app.
// Nothing the person types is stored or logged.

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
});

const MAX_SYSTEM = 6000;
const MAX_USER = 1600;
const MAX_TOKENS = 220;
const TIMEOUT_MS = 55_000;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serverURL = (Deno.env.get("MIVO_AI_URL") ?? "").replace(/\/+$/, "");
  const hfToken = Deno.env.get("MIVO_AI_HF_TOKEN") ?? "";
  if (!supabaseURL || !anonKey || !serverURL || !hfToken) return json(500, { error: "service_not_configured" });

  // Only signed-in Mivo accounts may use the model.
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization) return json(401, { error: "authentication_required" });
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user?.id) return json(401, { error: "authentication_required" });

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const system = String(body?.system ?? "").trim();
  const user = String(body?.user ?? "").trim();
  if (!system || !user || system.length > MAX_SYSTEM || user.length > MAX_USER) {
    return json(400, { error: "invalid_request" });
  }
  const maxTokens = Math.min(MAX_TOKENS, Math.max(1, Math.round(Number(body?.max_tokens) || 180)));
  const temperature = Math.min(1, Math.max(0, Number(body?.temperature) || 0));
  // The start of the reply, written for the model. Ask Milo passes "[1]": the model reads the
  // notes well but can't pick which one to cite, and the phone's retriever ranks the best first.
  const prefill = String(body?.prefill ?? "");
  if (prefill && !/^\[\d\]$/.test(prefill)) return json(400, { error: "invalid_request" });
  const messages = [{ role: "system", content: system }, { role: "user", content: user }];
  if (prefill) messages.push({ role: "assistant", content: prefill });

  try {
    const response = await fetch(`${serverURL}/v1/chat/completions`, {
      method: "POST",
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { "content-type": "application/json", authorization: `Bearer ${hfToken}` },
      body: JSON.stringify({
        messages,
        max_tokens: maxTokens,
        temperature,
        cache_prompt: true,
      }),
    });
    if (!response.ok) {
      console.error("mivo-ai server status", response.status);
      return json(502, { error: "ai_unavailable" });
    }
    const result = await response.json();
    const text = String(result?.choices?.[0]?.message?.content ?? "").trim();
    if (!text) return json(502, { error: "ai_unavailable" });
    // llama.cpp's reply already starts with the prefill; add it only if it doesn't.
    return json(200, { text: prefill && !text.startsWith(prefill) ? prefill + text : text });
  } catch (error) {
    // A sleeping Space can take a minute to wake; the app falls back meanwhile.
    console.error("mivo-ai failed", error instanceof Error ? error.name : "unknown");
    return json(502, { error: "ai_unavailable" });
  }
});
