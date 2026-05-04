import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import tls from "node:tls";

const port = Number(process.env.PORT || 8787);
const gmailUser = process.env.MIVO_GMAIL_USER || "info.mivoapp@gmail.com";
const gmailAppPassword = process.env.MIVO_GMAIL_APP_PASSWORD;
const emailApiKey = process.env.MIVO_EMAIL_API_KEY;
const dataDir = process.env.MIVO_DATA_DIR || path.join(process.cwd(), "backend-data");
const usersPath = path.join(dataDir, "users.json");
const passwordIterations = 180_000;

function jsonResponse(res, status, payload) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  });
  res.end(JSON.stringify(payload));
}

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function publicUser(record) {
  return {
    email: record.email,
    name: record.name,
    createdAt: record.createdAt,
    onboardingProfile: record.onboardingProfile || null,
  };
}

async function readUsers() {
  try {
    const raw = await fs.readFile(usersPath, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") return { users: {} };
    throw error;
  }
}

async function writeUsers(db) {
  await fs.mkdir(dataDir, { recursive: true });
  const tempPath = `${usersPath}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(db, null, 2));
  await fs.rename(tempPath, usersPath);
}

function hashPassword(password, saltHex = crypto.randomBytes(32).toString("hex")) {
  const hash = crypto.pbkdf2Sync(String(password), Buffer.from(saltHex, "hex"), passwordIterations, 32, "sha256");
  return {
    salt: saltHex,
    hash: hash.toString("hex"),
    iterations: passwordIterations,
  };
}

function verifyPassword(password, record) {
  const computed = crypto.pbkdf2Sync(
    String(password),
    Buffer.from(record.passwordSalt, "hex"),
    record.passwordIterations,
    32,
    "sha256"
  );
  const saved = Buffer.from(record.passwordHash, "hex");
  return saved.length === computed.length && crypto.timingSafeEqual(saved, computed);
}

function validatePassword(password) {
  return typeof password === "string" && password.length >= 8;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function profilePayload(payload) {
  return payload.onboardingProfile || payload.profile || null;
}

function offlineRecommendFocus(payload) {
  const focusLevel = Number(payload.focusLevel || 3);
  const timeAvailable = Number(payload.timeAvailable || 30);
  const intendedDuration = Number(payload.intendedDuration || 25);

  if (focusLevel <= 2 || intendedDuration <= 10) {
    return {
      mode: "micro",
      workMinutes: 7,
      restMinutes: 2,
      rationale: "Your focus feels low right now. A short 7-minute burst is better than forcing a long session. Small wins matter.",
      dailySchedule: "Try one micro session now, then reassess in 30 minutes.",
    };
  }

  if (focusLevel >= 4 && timeAvailable >= 50) {
    const work = timeAvailable >= 60 ? 60 : 50;
    return {
      mode: "classic",
      workMinutes: work,
      restMinutes: work === 60 ? 5 : 10,
      rationale: `You have good focus and plenty of time. A ${work}-minute session will let you go deep without burning out.`,
      dailySchedule: "One session now, one more this afternoon if needed.",
    };
  }

  if (focusLevel === 3 && timeAvailable >= 30) {
    return {
      mode: "adaptive",
      workMinutes: 10,
      restMinutes: 5,
      rationale: "With a middling focus level, starting adaptive lets Mivo extend your session as you warm up. No pressure to commit upfront.",
      dailySchedule: "Begin with 10 minutes and see how you feel.",
    };
  }

  if (intendedDuration >= 25 && focusLevel >= 3) {
    return {
      mode: "academic",
      workMinutes: 25,
      restMinutes: 5,
      rationale: "A 25/5 sprint gives your brain clear on/off cycles. It works especially well when you need structure to stay on task.",
      dailySchedule: "Aim for 2-4 sprints total today.",
    };
  }

  return {
    mode: "classic",
    workMinutes: 25,
    restMinutes: 5,
    rationale: "A classic 25-minute session is a solid starting point. It is long enough to get into flow but short enough to not feel daunting.",
    dailySchedule: "One session now. Add another later if you have time.",
  };
}

function offlineProtectedApps(payload) {
  const profile = profilePayload(payload);
  const selectedApps = Array.isArray(payload.selectedApps) ? payload.selectedApps : [];
  const chosen = selectedApps.length ? selectedApps : profile?.preferredApps || [];
  const common = ["TikTok", "Instagram", "YouTube", "Reddit", "Twitter / X", "Snapchat", "Facebook", "Threads"];
  const scores = Object.fromEntries(common.map((app) => [app, 1]));

  for (const app of chosen) scores[app] = (scores[app] || 1) + 5;

  const intentions = Array.isArray(profile?.intentions) ? profile.intentions : [];
  if (intentions.includes("Kill time") || intentions.includes("Bored")) {
    scores.TikTok = (scores.TikTok || 1) + 3;
    scores.Instagram = (scores.Instagram || 1) + 3;
    scores.YouTube = (scores.YouTube || 1) + 2;
    scores.Reddit = (scores.Reddit || 1) + 2;
  }
  if (intentions.includes("Relax")) {
    scores.YouTube = (scores.YouTube || 1) + 3;
    scores.Instagram = (scores.Instagram || 1) + 2;
    scores.TikTok = (scores.TikTok || 1) + 2;
  }

  const apps = Object.entries(scores)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 4)
    .map(([app]) => app);

  return {
    apps,
    rationale: chosen.length
      ? "Based on what you selected, these are the apps Mivo would protect first."
      : "Start with the apps most likely to create quick, repeated checking loops.",
  };
}

function estimateSavedMinutes(payload) {
  const profile = profilePayload(payload);
  const scroll = Number(profile?.scrollEstimateMinutes || 60);
  const intentions = Array.isArray(profile?.intentions) ? profile.intentions : [];
  let multiplier = 0.1;

  multiplier += Math.min(intentions.length, 4) * 0.03;
  if (intentions.includes("Kill time") || intentions.includes("Bored")) multiplier += 0.18;
  if (intentions.includes("Relax")) multiplier += 0.06;
  if (intentions.includes("Looking for something specific")) multiplier += 0.01;
  multiplier += Math.min(Number(profile?.preferredApps?.length || 0) * 0.02, 0.12);

  let ageFactor = 1;
  const age = Number(profile?.age || 0);
  if (age && age < 25) ageFactor = 1.12;
  else if (age > 54) ageFactor = 0.92;
  else if (age >= 35 && age <= 44) ageFactor = 0.97;

  multiplier = clamp(multiplier, 0.06, 0.75);
  let estimated = Math.round(scroll * multiplier * ageFactor);
  if (profile?.primaryIntention === "Kill time" || profile?.primaryIntention === "Bored") {
    estimated += Math.round(Math.max(estimated, 1) * 0.12);
  }
  return clamp(estimated, 3, 240);
}

function estimateLifeBreakdown(payload) {
  const profile = profilePayload(payload);
  const lifeExpectancy = Number(payload.lifeExpectancy || 80);
  const scrollHours = Number(profile?.scrollEstimateMinutes || 60) / 60;
  const years = (hours) => Math.round((hours / 24) * lifeExpectancy);
  const sleepYears = years(8);
  const workYears = years(8);
  const eatYears = years(2);
  const basicsYears = years(1);
  const scrollYears = years(scrollHours);
  const freeYears = Math.max(0, lifeExpectancy - (sleepYears + workYears + eatYears + basicsYears + scrollYears));
  return { sleepYears, workYears, eatYears, basicsYears, scrollYears, freeYears };
}

function parseHour(isoString) {
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return null;
  return date.getHours();
}

function recommendedScrollWindows(sessions, targetMinutes) {
  const bucketInfo = {
    morning: { start: 8, end: 9, fallbackReason: "Useful if you tend to check early." },
    afternoon: { start: 14, end: 15, fallbackReason: "Keeps scrolling away from the whole afternoon." },
    evening: { start: 19, end: 20, fallbackReason: "Matches common after-school or after-work drift." },
    night: { start: 21, end: 22, fallbackReason: "Contains late-night scrolling before it spreads." },
  };
  const scores = { morning: 0, afternoon: 0, evening: 0, night: 0 };

  for (const session of sessions) {
    const hour = parseHour(session.startTime);
    if (hour === null) continue;
    const weight = Math.max(Number(session.actualDuration || 0), 1);
    if (hour >= 21 || hour < 6) scores.night += weight;
    else if (hour < 12) scores.morning += weight;
    else if (hour < 17) scores.afternoon += weight;
    else scores.evening += weight;
  }

  let chosen = Object.keys(scores)
    .sort((a, b) => scores[b] - scores[a] || a.localeCompare(b))
    .slice(0, 2);
  if (chosen.every((key) => scores[key] === 0)) chosen = ["afternoon", "evening"];

  const firstMinutes = Math.max(8, Math.round(targetMinutes * 0.55));
  const secondMinutes = Math.max(7, targetMinutes - firstMinutes);

  return chosen.map((key, index) => {
    const info = bucketInfo[key];
    return {
      id: `${key}-${index}`,
      title: index === 0 ? "Scroll session 1" : "Scroll session 2",
      startHour: info.start,
      endHour: info.end,
      minutes: index === 0 ? firstMinutes : secondMinutes,
      reason: scores[key] > 0 ? "Chosen because your collected sessions cluster here." : info.fallbackReason,
    };
  });
}

function screenTimeReductionPlan(payload) {
  const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
  const truthChecks = Array.isArray(payload.truthChecks) ? payload.truthChecks : [];
  const profile = payload.onboardingProfile || profilePayload(payload);
  const daysNeeded = 3;
  const dailyTotals = {};

  for (const session of sessions) {
    if (!session.date) continue;
    dailyTotals[session.date] = (dailyTotals[session.date] || 0) + Number(session.actualDuration || 0);
  }

  const observedDays = new Set([...Object.keys(dailyTotals), ...truthChecks.map((check) => check.date).filter(Boolean)]);
  const daysCollected = observedDays.size;
  const totals = Object.values(dailyTotals);
  const fallbackEstimate = Math.max(Number(profile?.scrollEstimateMinutes || 90), Number(payload.todayScreenTimeMinutes || 0), 45);
  const baselineMinutes = Math.max(totals.length ? Math.round(totals.reduce((sum, value) => sum + value, 0) / totals.length) : fallbackEstimate, 20);

  if (daysCollected < daysNeeded) {
    return {
      id: `collecting-${daysCollected}`,
      collecting: true,
      daysCollected,
      daysNeeded,
      dayIndex: 0,
      baselineMinutes,
      targetMinutes: baselineMinutes,
      strictnessPercent: 0,
      summary: "Mivo is still learning your normal scroll pattern. For the first few days, keep using your phone normally so the plan is based on your real habits.",
      decisionReason: `Collecting mode keeps the limits open until Mivo has at least ${daysNeeded} days of session and truth-check history.`,
      windows: recommendedScrollWindows(sessions, baselineMinutes),
    };
  }

  const dayIndex = Math.max(1, daysCollected - daysNeeded + 1);
  const strictnessPercent = Math.min(45, 8 + (dayIndex - 1) * 6);
  const targetMinutes = Math.max(15, Math.round(baselineMinutes * (1 - strictnessPercent / 100)));
  return {
    id: `active-${dayIndex}-${targetMinutes}`,
    collecting: false,
    daysCollected,
    daysNeeded,
    dayIndex,
    baselineMinutes,
    targetMinutes,
    strictnessPercent,
    summary: `Mivo made today stricter by ${strictnessPercent}% from your collected baseline. Keep scrolling inside two planned windows instead of scattered checks all day.`,
    decisionReason: "The plan uses your highest-scroll time buckets, average daily session minutes, and truth-check history. Each new day lowers the target a little until the plan reaches a steady challenge.",
    windows: recommendedScrollWindows(sessions, targetMinutes),
  };
}

async function handleAI(req, res) {
  const body = await readBody(req);
  const payload = JSON.parse(body || "{}");

  if (req.url === "/api/ai/recommend-focus") {
    jsonResponse(res, 200, offlineRecommendFocus(payload));
    return;
  }
  if (req.url === "/api/ai/recommend-protected-apps") {
    jsonResponse(res, 200, offlineProtectedApps(payload));
    return;
  }
  if (req.url === "/api/ai/estimate-saved") {
    jsonResponse(res, 200, { estimatedSavedMinutes: estimateSavedMinutes(payload) });
    return;
  }
  if (req.url === "/api/ai/estimate-life-breakdown") {
    jsonResponse(res, 200, estimateLifeBreakdown(payload));
    return;
  }
  if (req.url === "/api/ai/screen-time-plan") {
    jsonResponse(res, 200, screenTimeReductionPlan(payload));
    return;
  }

  jsonResponse(res, 404, { error: "Not found" });
}

async function handleAuth(req, res) {
  const body = await readBody(req);
  const payload = JSON.parse(body || "{}");
  const email = normalizeEmail(payload.email);
  const db = await readUsers();
  const existing = db.users[email];

  if (!email || !email.includes("@")) {
    jsonResponse(res, 400, { error: "invalidEmail" });
    return;
  }

  if (req.url === "/auth/exists") {
    jsonResponse(res, 200, { ok: true, exists: Boolean(existing) });
    return;
  }

  if (req.url === "/auth/register") {
    if (existing) {
      jsonResponse(res, 409, { error: "emailAlreadyExists" });
      return;
    }
    if (!validatePassword(payload.password)) {
      jsonResponse(res, 400, { error: "weakPassword" });
      return;
    }

    const password = hashPassword(payload.password);
    const record = {
      email,
      name: String(payload.name || email.split("@")[0]).trim() || email.split("@")[0],
      createdAt: new Date().toISOString(),
      passwordHash: password.hash,
      passwordSalt: password.salt,
      passwordIterations: password.iterations,
      onboardingProfile: payload.onboardingProfile || null,
    };
    db.users[email] = record;
    await writeUsers(db);
    jsonResponse(res, 201, { ok: true, user: publicUser(record) });
    return;
  }

  if (req.url === "/auth/login") {
    if (!existing || !validatePassword(payload.password) || !verifyPassword(payload.password, existing)) {
      jsonResponse(res, 401, { error: "invalidCredentials" });
      return;
    }
    jsonResponse(res, 200, { ok: true, user: publicUser(existing) });
    return;
  }

  if (req.url === "/auth/reset-password") {
    if (!existing) {
      jsonResponse(res, 404, { error: "noAccount" });
      return;
    }
    if (!validatePassword(payload.password)) {
      jsonResponse(res, 400, { error: "weakPassword" });
      return;
    }
    const password = hashPassword(payload.password);
    existing.passwordHash = password.hash;
    existing.passwordSalt = password.salt;
    existing.passwordIterations = password.iterations;
    await writeUsers(db);
    jsonResponse(res, 200, { ok: true });
    return;
  }

  if (req.url === "/auth/profile") {
    if (!existing) {
      jsonResponse(res, 404, { error: "noAccount" });
      return;
    }
    existing.onboardingProfile = payload.onboardingProfile || null;
    await writeUsers(db);
    jsonResponse(res, 200, { ok: true, user: publicUser(existing) });
    return;
  }

  jsonResponse(res, 404, { error: "Not found" });
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

  if (req.method === "GET" && req.url === "/health") {
    jsonResponse(res, 200, {
      ok: true,
      service: "mivo-backend",
      gmailConfigured: Boolean(gmailAppPassword),
      apiKeyRequired: Boolean(emailApiKey),
      authDatabase: usersPath,
    });
    return;
  }

  if (req.method === "POST" && req.url.startsWith("/auth/")) {
    try {
      await handleAuth(req, res);
    } catch (error) {
      console.error("[Mivo auth server]", error.message);
      jsonResponse(res, 500, { error: "Auth failed" });
    }
    return;
  }

  if (req.method === "POST" && req.url.startsWith("/api/ai/")) {
    try {
      await handleAI(req, res);
    } catch (error) {
      console.error("[Mivo AI server]", error.message);
      jsonResponse(res, 500, { error: "AI request failed" });
    }
    return;
  }

  if (req.method !== "POST" || req.url !== "/send-verification-code") {
    jsonResponse(res, 404, { error: "Not found" });
    return;
  }

  try {
    if (emailApiKey && req.headers["x-mivo-email-key"] !== emailApiKey) {
      jsonResponse(res, 401, { error: "Unauthorized" });
      return;
    }

    const body = await readBody(req);
    const payload = JSON.parse(body || "{}");
    await sendWithGmailSMTP(payload);
    jsonResponse(res, 200, { ok: true });
  } catch (error) {
    console.error("[Mivo email server]", error.message);
    jsonResponse(res, 500, { error: "Email delivery failed" });
  }
});

server.listen(port, () => {
  console.log(`Mivo backend listening on port ${port}`);
  console.log(`Health check: /health`);
  console.log(`Verification endpoint: /send-verification-code`);
  console.log(`Auth endpoints: /auth/register /auth/login /auth/exists /auth/reset-password /auth/profile`);
  console.log(`AI endpoints: /api/ai/recommend-focus /api/ai/recommend-protected-apps /api/ai/estimate-saved /api/ai/estimate-life-breakdown /api/ai/screen-time-plan`);
  console.log(`Auth database: ${usersPath}`);
  console.log(`Sending as ${gmailUser}`);
  console.log(`API key required: ${emailApiKey ? "yes" : "no"}`);
});
