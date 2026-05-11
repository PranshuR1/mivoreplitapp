# Mivo Backend

This backend stores shared login/register accounts outside the iPhone and serves Mivo's online AI/adaptive recommendation endpoints. Passwords are hashed with PBKDF2 before being written to disk.

## Local Setup

1. Start the server:

```bash
node backend/auth-server.mjs
```

The local app can call:

```text
http://127.0.0.1:8787/auth/register
http://127.0.0.1:8787/auth/login
http://127.0.0.1:8787/api/ai/screen-time-plan
```

For a physical iPhone or TestFlight build, this must be deployed to a public HTTPS backend. The phone cannot reach your Mac's localhost after the backend stops running.

Accounts are stored at `backend-data/users.json` by default. In production, set `MIVO_DATA_DIR` to a persistent disk path on your host so users remain after redeploys.

## Online AI Endpoints

The iOS app will use `AI_API_BASE_URL` when it is set. If that is empty, it falls back to `MIVO_AUTH_API_URL`, so one deployed backend can handle auth and AI decisions.

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
3. Copy the Render service URL into `MIVO_AUTH_API_URL` in `Mivo/Info.plist`. You can leave `AI_API_BASE_URL` blank because the app falls back to `MIVO_AUTH_API_URL`:

```text
https://your-render-service.onrender.com
```

4. Confirm the server is live:

```text
https://your-render-service.onrender.com/health
```

## Security Note

Do not expose `backend-data/users.json`; only the `/auth/*` API should access it.
