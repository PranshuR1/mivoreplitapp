---
title: Mivo AI API
sdk: docker
app_port: 7860
license: apache-2.0
---

# Reviewable model-hosting option

This container is prepared for a **private** Hugging Face Docker Space. It has not been created
or activated. As checked on November 4, 2026, creating Docker compute Spaces requires a paid
personal plan; [PRO is $9/month](https://huggingface.co/pricing), and CPU Basic has no additional
hourly charge. See the [current Spaces rules](https://huggingface.co/docs/hub/spaces-overview).
An existing HTTPS model server can be used instead, with no new hosting subscription here.

The recipe uses the upstream **Qwen2.5-1.5B-Instruct Q4_K_M** model with Mivo's retrieved notes.
It does not contain a Mivo fine-tune; no trained checkpoint was present in the connected
`mivoscrolling` account. Both container images and the model revision are pinned. The model's
checksum is verified during build, and its license and model card are included in the image.

The server exposes `/v1/chat/completions` on port 7860 with one generation slot and a 4096-token
context. It runs without root privileges. Request logging and the web UI are disabled. It does
not write conversation transcripts. The Hugging Face Space must remain private: its access
token belongs only in Supabase's encrypted `MIVO_AI_HF_TOKEN` secret.

After a hosting decision:

1. Build and smoke-test the container. Docker is not installed on the current Mac, so the image
   itself has not been executed here. The client/proxy contract has separate passing tests.
2. Create a private Docker Space using CPU Basic and these three files. Approve any subscription
   charge before changing the account plan; do not enable paid hardware automatically.
3. Set `MIVO_AI_URL` to the resulting HTTPS Space base URL and `MIVO_AI_HF_TOKEN` to a restricted
   token that can access that private Space. Keep the token out of repositories and chat.
4. Confirm a signed-in nonsensitive question, JSON proof review, response latency, a cold start,
   and concurrent-request behavior before calling the model production-ready.

The already-deployed Supabase proxy bounds requests and validates users. Ask Milo has an
explicit bundled-note fallback when the model is missing, unavailable, or waking up. A server
outage does not itself approve a Lock-in proof.
