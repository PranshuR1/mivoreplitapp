import http from "node:http";
import tls from "node:tls";

const port = Number(process.env.PORT || 8787);
const gmailUser = process.env.MIVO_GMAIL_USER || "info.mivoapp@gmail.com";
const gmailAppPassword = process.env.MIVO_GMAIL_APP_PASSWORD;

function jsonResponse(res, status, payload) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 20_000) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function smtpCommand(socket, command, expected) {
  return new Promise((resolve, reject) => {
    let buffer = "";

    function onData(data) {
      buffer += data.toString("utf8");
      const lines = buffer.trimEnd().split(/\r?\n/);
      const last = lines[lines.length - 1] || "";

      if (!/^\d{3} /.test(last)) return;

      socket.off("data", onData);
      const code = Number(last.slice(0, 3));
      if (!expected.includes(code)) {
        reject(new Error(`SMTP expected ${expected.join("/")} but received: ${buffer}`));
        return;
      }
      resolve(buffer);
    }

    socket.on("data", onData);
    if (command) socket.write(`${command}\r\n`);
  });
}

function encodeBase64(value) {
  return Buffer.from(value, "utf8").toString("base64");
}

function buildEmail({ from, to, subject, code }) {
  const safeSubject = subject || "Your Mivo verification code";
  const text = [
    `Your Mivo verification code is ${code}.`,
    "",
    "This code expires in 10 minutes.",
    "If you did not request this, you can ignore this email.",
  ].join("\n");

  const html = [
    "<div style=\"font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.5;color:#2E2E2E\">",
    "<h2 style=\"margin:0 0 12px\">Mivo verification code</h2>",
    `<p>Your verification code is <strong style=\"font-size:24px;letter-spacing:3px\">${code}</strong>.</p>`,
    "<p>This code expires in 10 minutes.</p>",
    "<p style=\"color:#777\">If you did not request this, you can ignore this email.</p>",
    "</div>",
  ].join("");

  return [
    `From: Mivo <${from}>`,
    `To: ${to}`,
    `Subject: ${safeSubject}`,
    "MIME-Version: 1.0",
    "Content-Type: multipart/alternative; boundary=mivo-boundary",
    "",
    "--mivo-boundary",
    "Content-Type: text/plain; charset=utf-8",
    "",
    text,
    "--mivo-boundary",
    "Content-Type: text/html; charset=utf-8",
    "",
    html,
    "--mivo-boundary--",
    "",
  ].join("\r\n");
}

async function sendWithGmailSMTP(payload) {
  if (!gmailAppPassword) {
    throw new Error("Missing MIVO_GMAIL_APP_PASSWORD. Create a Gmail app password and set it before starting the server.");
  }

  const from = gmailUser;
  const { to, subject, code } = payload;
  if (!to || !code || !/^\d{6}$/.test(String(code))) {
    throw new Error("Expected JSON body with to and 6-digit code.");
  }

  const message = buildEmail({ from, to, subject, code });
  const socket = tls.connect(465, "smtp.gmail.com", { servername: "smtp.gmail.com" });

  await new Promise((resolve, reject) => {
    socket.once("secureConnect", resolve);
    socket.once("error", reject);
  });

  try {
    await smtpCommand(socket, null, [220]);
    await smtpCommand(socket, "EHLO mivo.local", [250]);
    await smtpCommand(socket, "AUTH LOGIN", [334]);
    await smtpCommand(socket, encodeBase64(gmailUser), [334]);
    await smtpCommand(socket, encodeBase64(gmailAppPassword), [235]);
    await smtpCommand(socket, `MAIL FROM:<${from}>`, [250]);
    await smtpCommand(socket, `RCPT TO:<${to}>`, [250, 251]);
    await smtpCommand(socket, "DATA", [354]);
    await smtpCommand(socket, `${message}\r\n.`, [250]);
    await smtpCommand(socket, "QUIT", [221]);
  } finally {
    socket.end();
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    jsonResponse(res, 204, {});
    return;
  }

  if (req.method !== "POST" || req.url !== "/send-verification-code") {
    jsonResponse(res, 404, { error: "Not found" });
    return;
  }

  try {
    const body = await readBody(req);
    const payload = JSON.parse(body || "{}");
    await sendWithGmailSMTP(payload);
    jsonResponse(res, 200, { ok: true });
  } catch (error) {
    console.error("[Mivo email server]", error.message);
    jsonResponse(res, 500, { error: error.message });
  }
});

server.listen(port, () => {
  console.log(`Mivo email server listening on http://localhost:${port}/send-verification-code`);
  console.log(`Sending as ${gmailUser}`);
});
