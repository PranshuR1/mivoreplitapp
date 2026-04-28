# Mivo Email Server

This tiny backend sends Mivo verification codes through Gmail without putting the Gmail password in the iOS app.

## Setup

1. In Gmail, enable 2-Step Verification for `info.mivoapp@gmail.com`.
2. Create a Gmail app password.
3. Start the server:

```bash
MIVO_GMAIL_USER=info.mivoapp@gmail.com MIVO_GMAIL_APP_PASSWORD="your-app-password" node backend/email-server.mjs
```

The app is configured to call:

```text
http://localhost:8787/send-verification-code
```

That works from the iOS Simulator. For a physical iPhone, deploy this server or expose it with an HTTPS tunnel and replace `MIVO_AUTH_EMAIL_API_URL` in `Mivo/Info.plist`.
