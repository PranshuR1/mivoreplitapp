# Mivo Backend

This backend sends Mivo verification codes through Gmail, stores shared login/register accounts outside the iPhone, and serves Mivo's online AI/adaptive recommendation endpoints. Passwords are hashed with PBKDF2 before being written to disk.

## Local Setup

1. In Gmail, enable 2-Step Verification for `info.mivoapp@gmail.com`.
2. Create a Gmail app password.
3. Start the server:

```bash
MIVO_GMAIL_USER=info.mivoapp@gmail.com MIVO_GMAIL_APP_PASSWORD="your-app-password" node backend/email-server.mjs
```

The local app can call:

```text
http://127.0.0.1:8787/send-verification-code
http://127.0.0.1:8787/auth/login
http://127.0.0.1:8787/api/ai/screen-time-plan
```

For a physical iPhone or TestFlight build, this must be deployed to a public HTTPS backend. The phone cannot reach your Mac's localhost after the backend stops running.

Accounts are stored at `backend-data/users.json` by default. In production, set `MIVO_DATA_DIR` to a persistent disk path on your host so users remain after redeploys.

## Online AI Endpoints

The iOS app will use `AI_API_BASE_URL` when it is set. If that is empty, it now falls back to `MIVO_AUTH_API_URL`, so one deployed backend can handle auth, verification email, and AI decisions.

```text
POST /api/ai/recommend-focus
POST /api/ai/recommend-protected-apps
POST /api/ai/estimate-saved
POST /api/ai/estimate-life-breakdown
POST /api/ai/screen-time-plan
```

These endpoints currently use the same deterministic Mivo decision engine as the on-device fallback. That keeps the app working online without requiring an OpenAI key.

## Public Deployment

This repo includes a Render blueprint at `render.yaml`.

1. Push this repo to GitHub.
2. In Render, create a new Blueprint from the repo.
3. Set the secret `MIVO_GMAIL_APP_PASSWORD` to the Gmail app password.
4. Keep the generated `MIVO_EMAIL_API_KEY`; copy that value into the app's `MIVO_AUTH_EMAIL_API_KEY`.
5. Copy the Render service URL into `MIVO_AUTH_EMAIL_API_URL` and `MIVO_AUTH_API_URL` in `Mivo/Info.plist`. You can leave `AI_API_BASE_URL` blank because the app falls back to `MIVO_AUTH_API_URL`:

```text
https://your-render-service.onrender.com/send-verification-code
https://your-render-service.onrender.com
```

6. Confirm the server is live:

```text
https://your-render-service.onrender.com/health
```

## Security Note

Do not put the Gmail app password inside the iOS app. It belongs only in the hosted backend environment variables. Do not expose `backend-data/users.json`; only the `/auth/*` API should access it.
