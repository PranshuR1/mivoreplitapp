# Milo AI service

The iPhone sends selected bundled notes and a question to this authenticated proxy. The model
server must expose an OpenAI-compatible `POST /v1/chat/completions` endpoint. The proxy keeps its
model credential on the server, bounds input/output sizes, and returns generic upstream errors.
It checks the caller with Supabase Auth; no service-role credential is needed.

Configure these secrets in the intended Supabase project:

- `MIVO_AI_URL`: the HTTPS model-server base URL, without `/v1/chat/completions`.
- `MIVO_AI_HF_TOKEN`: the model server's bearer credential.

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are supplied by the Edge Function runtime. Keep secrets in
Supabase or a private file outside the repositories. Do not put them in the app or commit them.

After signing in to the Supabase CLI, set the secrets and deploy:

```sh
supabase secrets set --project-ref '<project-ref>' --env-file /absolute/path/to/private-secrets.env
supabase functions deploy mivo-ai --project-ref '<project-ref>' --no-verify-jwt
```

Gateway JWT verification is disabled because this handler validates the user itself, matching
the other authenticated Mivo functions. Once configured, a request without a valid signed-in
user must return `401 authentication_required`. Until the required secrets exist, the handler
returns `500 service_not_configured` before its authentication check; this is not a successful
readiness result.

Run the handler's isolated checks without credentials or model traffic:

```sh
TYPESCRIPT_MODULE=/absolute/path/to/typescript/lib/typescript.js node scripts/test_mivo_ai_edge.mjs
python3 scripts/check_completion_services.py
```

The service probe sends only empty/invalid anonymous requests. It checks deployment and access
boundaries without generating a model response or creating user data. It reports a missing or
unconfigured function as a failure. A signed-in, nonsensitive question in Ask Milo is still
needed to confirm the actual model server after deployment.

During an outage, Ask Milo explicitly labels its bundled-note fallback. Lock-in retains its
existing review fallback; an unavailable or unreadable model response does not itself unlock a
protected commitment.
