import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const port = Number(process.env.PORT || 8787);
const dataDir = process.env.MIVO_DATA_DIR || path.join(process.cwd(), "backend-data");
const usersPath = path.join(dataDir, "users.json");
const passwordIterations = 180_000;
const adminEmail = normalizeEmail(process.env.MIVO_ADMIN_EMAIL || "");
const adminPassword = process.env.MIVO_ADMIN_PASSWORD || "";
const rateLimitWindowMs = boundedNumber(process.env.MIVO_RATE_LIMIT_WINDOW_MS, 15 * 60 * 1000, 60 * 1000, 60 * 60 * 1000);
const globalRateLimitMax = boundedNumber(process.env.MIVO_GLOBAL_RATE_LIMIT_MAX, 120, 10, 10_000);
const loginRateLimitMax = boundedNumber(process.env.MIVO_LOGIN_RATE_LIMIT_MAX, 5, 1, 100);
const maxBodyBytes = boundedNumber(process.env.MIVO_MAX_BODY_BYTES, 20_000, 1_000, 250_000);
const allowedOrigin = process.env.MIVO_ALLOWED_ORIGIN || "";
const trustProxy = process.env.MIVO_TRUST_PROXY === "true";
const sessionTtlMs = 1000 * 60 * 60 * 24 * 30;
const adminSessionTtlMs = 1000 * 60 * 60 * 24 * 14;
const tokenKeyPrefix = "sha256:";
const allowUnverifiedPasswordReset = process.env.MIVO_ALLOW_UNVERIFIED_PASSWORD_RESET === "true";
const googleClientIds = (process.env.MIVO_GOOGLE_CLIENT_IDS || "").split(",").map((v) => v.trim()).filter(Boolean);
const appleClientIds = (process.env.MIVO_APPLE_CLIENT_IDS || "app.mivo.com").split(",").map((v) => v.trim()).filter(Boolean);
const jwksCache = new Map();
const rateLimitBuckets = new Map();
const loginRateLimitedRoutes = new Set(["/auth/login", "/auth/register", "/auth/reset-password", "/auth/social", "/auth/profile"]);

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function boundedNumber(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return clamp(Math.floor(parsed), min, max);
}

function jsonResponse(res, status, payload) {
  const headers = {
    "Content-Type": "application/json",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
  };
  // The iOS app is not a browser, so CORS is opt-in via MIVO_ALLOWED_ORIGIN.
  if (allowedOrigin) {
    headers["Access-Control-Allow-Origin"] = allowedOrigin;
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
  }
  res.writeHead(status, headers);
  res.end(JSON.stringify(payload));
}

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function parseRoute(req) {
  if (!req.url || req.url.length > 2048) throw new HttpError(414, "urlTooLong");
  try {
    return new URL(req.url, "http://mivo.local").pathname;
  } catch {
    throw new HttpError(400, "malformedUrl");
  }
}

function clientIp(req) {
  if (trustProxy) {
    // Only the right-most entry is appended by our own proxy; earlier entries are client-controlled.
    const hops = String(req.headers["x-forwarded-for"] || "").split(",").map((h) => h.trim()).filter(Boolean);
    if (hops.length) return hops[hops.length - 1];
  }
  return req.socket.remoteAddress || "unknown";
}

function hitRateLimit(key, maxAttempts, windowMs) {
  const now = Date.now();
  const current = rateLimitBuckets.get(key);
  if (!current || current.resetAt <= now) {
    rateLimitBuckets.set(key, { count: 1, resetAt: now + windowMs });
    return null;
  }

  current.count += 1;
  if (current.count > maxAttempts) {
    return Math.ceil((current.resetAt - now) / 1000);
  }
  return null;
}

function enforceRateLimit(req, routePath) {
  const ip = clientIp(req);
  const globalRetryAfter = hitRateLimit(`global:${ip}`, globalRateLimitMax, rateLimitWindowMs);
  if (globalRetryAfter) {
    throw new HttpError(429, `rateLimited:${globalRetryAfter}`);
  }

  if (loginRateLimitedRoutes.has(routePath)) {
    const retryAfter = hitRateLimit(`login:${routePath}:${ip}`, loginRateLimitMax, rateLimitWindowMs);
    if (retryAfter) {
      throw new HttpError(429, `loginRateLimited:${retryAfter}`);
    }
  }
}

function pruneRateLimits() {
  const now = Date.now();
  for (const [key, value] of rateLimitBuckets) {
    if (value.resetAt <= now) rateLimitBuckets.delete(key);
  }
}

function requireJsonPost(req) {
  const contentType = String(req.headers["content-type"] || "").toLowerCase();
  if (!contentType.includes("application/json")) {
    throw new HttpError(415, "unsupportedContentType");
  }
}

function ensurePlainObject(value, field = "payload") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `${field}Malformed`);
  }
  return value;
}

function cleanString(value, field, { required = false, max = 500, min = 0 } = {}) {
  if (value === undefined || value === null) {
    if (required) throw new HttpError(400, `${field}Required`);
    return "";
  }
  if (typeof value !== "string") throw new HttpError(400, `${field}Malformed`);
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  if (cleaned.length < min) throw new HttpError(400, `${field}TooShort`);
  if (cleaned.length > max) throw new HttpError(413, `${field}TooLong`);
  return cleaned;
}

function cleanEmail(value, { required = true, field = "email" } = {}) {
  const email = normalizeEmail(cleanString(value, field, { required, max: 254 }));
  if (!email && !required) return "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError(400, "invalidEmail");
  }
  return email;
}

function cleanPassword(value) {
  return cleanString(value, "password", { required: true, min: 8, max: 256 });
}

function cleanJsonValue(value, field = "payload", depth = 0) {
  if (depth > 6) throw new HttpError(413, `${field}TooDeep`);
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "string") return cleanString(value, field, { max: 1_000 });
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new HttpError(400, `${field}Malformed`);
    return value;
  }
  if (Array.isArray(value)) {
    if (value.length > 80) throw new HttpError(413, `${field}TooLarge`);
    return value.map((item) => cleanJsonValue(item, field, depth + 1));
  }
  if (typeof value === "object") {
    const entries = Object.entries(value);
    if (entries.length > 80) throw new HttpError(413, `${field}TooLarge`);
    return Object.fromEntries(entries.map(([key, nested]) => {
      const cleanKey = cleanString(key, field, { required: true, max: 80 });
      return [cleanKey, cleanJsonValue(nested, cleanKey, depth + 1)];
    }));
  }
  throw new HttpError(400, `${field}Malformed`);
}

function sanitizeAuthPayload(payload) {
  ensurePlainObject(payload);
  return {
    email: payload.email === undefined ? "" : cleanEmail(payload.email, { required: false }),
    password: payload.password === undefined || payload.password === null ? "" : cleanPassword(payload.password),
    name: cleanString(payload.name, "name", { max: 80 }),
    targetEmail: payload.targetEmail === undefined ? "" : cleanEmail(payload.targetEmail, { required: false, field: "targetEmail" }),
    adminToken: cleanString(payload.adminToken, "adminToken", { max: 128 }),
    sessionToken: cleanString(payload.sessionToken, "sessionToken", { max: 128 }),
    onboardingProfile: payload.onboardingProfile === undefined ? null : cleanJsonValue(payload.onboardingProfile, "onboardingProfile"),
    profile: payload.profile === undefined ? null : cleanJsonValue(payload.profile, "profile"),
  };
}

function sanitizeAIPayload(payload) {
  ensurePlainObject(payload);
  return cleanJsonValue(payload, "payload");
}

function publicUser(record) {
  return {
    email: record.email,
    name: record.name,
    createdAt: record.createdAt,
    onboardingProfile: record.onboardingProfile || null,
    isAdmin: record.role === "admin",
  };
}

function adminUser(record) {
  return {
    ...publicUser(record),
    role: record.role || "user",
    lastLoginAt: record.lastLoginAt || null,
    updatedAt: record.updatedAt || null,
  };
}

// Sessions are stored under a hash of the token; plaintext-keyed legacy entries are discarded.
function dropLegacyTokens(sessions) {
  const kept = {};
  for (const [key, value] of Object.entries(sessions || {})) {
    if (key.startsWith(tokenKeyPrefix) && value && value.expiresAt > Date.now()) kept[key] = value;
  }
  return kept;
}

function tokenKey(token) {
  return tokenKeyPrefix + crypto.createHash("sha256").update(String(token)).digest("hex");
}

async function readUsers() {
  try {
    const raw = await fs.readFile(usersPath, "utf8");
    const db = JSON.parse(raw);
    if (!db.users) db.users = {};
    db.adminSessions = dropLegacyTokens(db.adminSessions);
    db.userSessions = dropLegacyTokens(db.userSessions);
    return db;
  } catch (error) {
    if (error.code === "ENOENT") return { users: {}, adminSessions: {}, userSessions: {} };
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

function ensureAdminUser(db) {
  if (!adminEmail && !adminPassword) return false;
  if (!adminEmail || !validatePassword(adminPassword)) {
    console.warn("[Mivo auth server] Admin seed skipped: set MIVO_ADMIN_EMAIL and a valid MIVO_ADMIN_PASSWORD.");
    return false;
  }
  const existing = db.users[adminEmail];
  const password = hashPassword(adminPassword, existing?.passwordSalt);
  const adminRecord = {
    ...(existing || {}),
    email: adminEmail,
    name: existing?.name || "Mivo Admin",
    createdAt: existing?.createdAt || new Date().toISOString(),
    passwordHash: password.hash,
    passwordSalt: password.salt,
    passwordIterations: password.iterations,
    onboardingProfile: existing?.onboardingProfile || null,
    role: "admin",
    updatedAt: new Date().toISOString(),
  };
  db.users[adminEmail] = adminRecord;
  return (
    !existing ||
    existing.role !== "admin" ||
    existing.passwordHash !== adminRecord.passwordHash ||
    existing.passwordIterations !== adminRecord.passwordIterations
  );
}

function issueAdminToken(db, email) {
  const token = crypto.randomBytes(32).toString("hex");
  db.adminSessions[tokenKey(token)] = { email, expiresAt: Date.now() + adminSessionTtlMs };
  return token;
}

function issueSessionToken(db, email) {
  const token = crypto.randomBytes(32).toString("hex");
  db.userSessions[tokenKey(token)] = { email, expiresAt: Date.now() + sessionTtlMs };
  return token;
}

function requireSession(db, payload, email) {
  const token = String(payload.sessionToken || "");
  if (!token || !email) return false;
  const key = tokenKey(token);
  const session = db.userSessions[key];
  if (!session || session.expiresAt < Date.now()) {
    delete db.userSessions[key];
    return false;
  }
  return session.email === email;
}

function requireAdmin(db, payload) {
  const token = String(payload.adminToken || "");
  const key = tokenKey(token);
  const session = token ? db.adminSessions[key] : null;
  if (!session || session.expiresAt < Date.now()) {
    if (token) delete db.adminSessions[key];
    return null;
  }
  const record = db.users[session.email];
  return record?.role === "admin" ? record : null;
}

function verifyPassword(password, record) {
  if (!record.passwordHash || !record.passwordSalt || !record.passwordIterations) return false;
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
  return typeof password === "string" && password.length >= 8 && password.length <= 256;
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

async function handleAI(req, res, routePath) {
  requireJsonPost(req);
  const payload = sanitizeAIPayload(await readJsonBody(req));

  if (routePath === "/api/ai/recommend-focus") {
    jsonResponse(res, 200, offlineRecommendFocus(payload));
    return;
  }
  if (routePath === "/api/ai/recommend-protected-apps") {
    jsonResponse(res, 200, offlineProtectedApps(payload));
    return;
  }
  if (routePath === "/api/ai/estimate-saved") {
    jsonResponse(res, 200, { estimatedSavedMinutes: estimateSavedMinutes(payload) });
    return;
  }
  if (routePath === "/api/ai/estimate-life-breakdown") {
    jsonResponse(res, 200, estimateLifeBreakdown(payload));
    return;
  }
  if (routePath === "/api/ai/screen-time-plan") {
    jsonResponse(res, 200, screenTimeReductionPlan(payload));
    return;
  }

  jsonResponse(res, 404, { error: "Not found" });
}

async function loadJwks(url) {
  const cached = jwksCache.get(url);
  if (cached && cached.expiresAt > Date.now()) return cached.keys;
  const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new HttpError(502, "socialProviderUnavailable");
  const { keys } = await response.json();
  jwksCache.set(url, { keys, expiresAt: Date.now() + 60 * 60 * 1000 });
  return keys;
}

async function verifyIdToken(idToken, { jwksUrl, issuers, audiences }) {
  if (typeof idToken !== "string" || idToken.length > 8192) throw new HttpError(401, "invalidSocialToken");
  const parts = idToken.split(".");
  if (parts.length !== 3) throw new HttpError(401, "invalidSocialToken");
  let header;
  let claims;
  try {
    header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
    claims = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  } catch {
    throw new HttpError(401, "invalidSocialToken");
  }
  if (header.alg !== "RS256") throw new HttpError(401, "invalidSocialToken");
  const jwk = (await loadJwks(jwksUrl)).find((key) => key.kid === header.kid);
  if (!jwk) throw new HttpError(401, "invalidSocialToken");
  const valid = crypto.verify(
    "RSA-SHA256",
    Buffer.from(`${parts[0]}.${parts[1]}`),
    crypto.createPublicKey({ key: jwk, format: "jwk" }),
    Buffer.from(parts[2], "base64url")
  );
  const now = Math.floor(Date.now() / 1000);
  if (!valid || !issuers.includes(claims.iss) || !audiences.includes(claims.aud) || !(claims.exp > now)) {
    throw new HttpError(401, "invalidSocialToken");
  }
  return claims;
}

async function handleSocialAuth(req, res) {
  requireJsonPost(req);
  const body = await readJsonBody(req);
  ensurePlainObject(body);
  const provider = cleanString(body.provider, "provider", { required: true, max: 16 });
  const idToken = cleanString(body.idToken, "idToken", { required: true, max: 8192 });
  const suppliedName = cleanString(body.name, "name", { max: 80 });

  let claims;
  if (provider === "google") {
    if (!googleClientIds.length) throw new HttpError(503, "socialNotConfigured");
    claims = await verifyIdToken(idToken, {
      jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
      issuers: ["https://accounts.google.com", "accounts.google.com"],
      audiences: googleClientIds,
    });
  } else if (provider === "apple") {
    claims = await verifyIdToken(idToken, {
      jwksUrl: "https://appleid.apple.com/auth/keys",
      issuers: ["https://appleid.apple.com"],
      audiences: appleClientIds,
    });
  } else {
    throw new HttpError(400, "providerUnsupported");
  }

  const email = normalizeEmail(claims.email);
  const emailVerified = claims.email_verified === true || claims.email_verified === "true";
  if (!email || !emailVerified) throw new HttpError(401, "emailNotVerified");

  const db = await readUsers();
  ensureAdminUser(db);
  let record = db.users[email];
  let created = false;
  if (!record) {
    created = true;
    record = {
      email,
      name: suppliedName || String(claims.name || "").trim().slice(0, 80) || email.split("@")[0],
      createdAt: new Date().toISOString(),
      onboardingProfile: null,
      role: "user",
    };
    db.users[email] = record;
  }
  record.lastLoginAt = new Date().toISOString();
  record.socialProviders = Array.from(new Set([...(record.socialProviders || []), provider]));
  const adminToken = record.role === "admin" ? issueAdminToken(db, record.email) : null;
  const sessionToken = issueSessionToken(db, record.email);
  await writeUsers(db);
  jsonResponse(res, created ? 201 : 200, { ok: true, user: publicUser(record), adminToken, sessionToken });
}

async function handleAuth(req, res, routePath) {
  requireJsonPost(req);
  const payload = sanitizeAuthPayload(await readJsonBody(req));
  const email = payload.email;
  const db = await readUsers();
  const adminSeeded = ensureAdminUser(db);
  const existing = db.users[email];

  const isAdminRoute = routePath.startsWith("/auth/admin/");

  if (!isAdminRoute && !email) {
    jsonResponse(res, 400, { error: "invalidEmail" });
    return;
  }

  if (routePath === "/auth/register") {
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
      role: "user",
    };
    db.users[email] = record;
    const sessionToken = issueSessionToken(db, email);
    await writeUsers(db);
    jsonResponse(res, 201, { ok: true, user: publicUser(record), sessionToken });
    return;
  }

  if (routePath === "/auth/login") {
    if (!existing || !validatePassword(payload.password) || !verifyPassword(payload.password, existing)) {
      jsonResponse(res, 401, { error: "invalidCredentials" });
      return;
    }
    existing.lastLoginAt = new Date().toISOString();
    const adminToken = existing.role === "admin" ? issueAdminToken(db, existing.email) : null;
    const sessionToken = issueSessionToken(db, existing.email);
    await writeUsers(db);
    jsonResponse(res, 200, { ok: true, user: publicUser(existing), adminToken, sessionToken });
    return;
  }

  if (routePath === "/auth/reset-password") {
    if (!allowUnverifiedPasswordReset) {
      jsonResponse(res, 403, { error: "passwordResetUnavailable" });
      return;
    }
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

  if (routePath === "/auth/profile") {
    if (!existing || !requireSession(db, payload, email)) {
      jsonResponse(res, 401, { error: "invalidSession" });
      return;
    }
    existing.onboardingProfile = payload.onboardingProfile || null;
    existing.updatedAt = new Date().toISOString();
    await writeUsers(db);
    jsonResponse(res, 200, { ok: true, user: publicUser(existing) });
    return;
  }

  if (routePath === "/auth/admin/users") {
    const admin = requireAdmin(db, payload);
    if (!admin) {
      await writeUsers(db);
      jsonResponse(res, 403, { error: "adminRequired" });
      return;
    }
    const users = Object.values(db.users)
      .map(adminUser)
      .sort((a, b) => a.email.localeCompare(b.email));
    if (adminSeeded) await writeUsers(db);
    jsonResponse(res, 200, { ok: true, users });
    return;
  }

  if (routePath === "/auth/admin/user") {
    const admin = requireAdmin(db, payload);
    if (!admin) {
      await writeUsers(db);
      jsonResponse(res, 403, { error: "adminRequired" });
      return;
    }
    const target = db.users[payload.targetEmail];
    if (!target) {
      if (adminSeeded) await writeUsers(db);
      jsonResponse(res, 404, { error: "noAccount" });
      return;
    }
    if (adminSeeded) await writeUsers(db);
    jsonResponse(res, 200, { ok: true, user: adminUser(target) });
    return;
  }

  if (routePath === "/auth/admin/delete-user") {
    const admin = requireAdmin(db, payload);
    if (!admin) {
      await writeUsers(db);
      jsonResponse(res, 403, { error: "adminRequired" });
      return;
    }
    const targetEmail = payload.targetEmail;
    if (targetEmail === admin.email || targetEmail === adminEmail) {
      jsonResponse(res, 400, { error: "cannotDeleteAdmin" });
      return;
    }
    if (!db.users[targetEmail]) {
      if (adminSeeded) await writeUsers(db);
      jsonResponse(res, 404, { error: "noAccount" });
      return;
    }
    delete db.users[targetEmail];
    await writeUsers(db);
    jsonResponse(res, 200, { ok: true });
    return;
  }

  if (adminSeeded) await writeUsers(db);
  jsonResponse(res, 404, { error: "Not found" });
}

async function readJsonBody(req) {
  const body = await readBody(req);
  if (!body.trim()) return {};
  try {
    return ensurePlainObject(JSON.parse(body));
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(400, "malformedJson");
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let received = 0;
    req.on("data", (chunk) => {
      received += chunk.length;
      if (received > maxBodyBytes) {
        reject(new HttpError(413, "payloadTooLarge"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function handleError(res, label, error) {
  if (error instanceof HttpError) {
    const [code, retryAfter] = String(error.code).split(":");
    const payload = retryAfter ? { error: code, retryAfter: Number(retryAfter) } : { error: code };
    jsonResponse(res, error.status, payload);
    return;
  }
  console.error(label, error.message);
  jsonResponse(res, 500, { error: "internalServerError" });
}

const server = http.createServer(async (req, res) => {
  try {
    const routePath = parseRoute(req);
    pruneRateLimits();

    if (req.method === "OPTIONS") {
      jsonResponse(res, 204, {});
      return;
    }

    enforceRateLimit(req, routePath);

    if (req.method === "GET" && routePath === "/health") {
      jsonResponse(res, 200, {
        ok: true,
        service: "mivo-backend",
        authDatabase: usersPath,
      });
      return;
    }

    if (req.method === "POST" && routePath === "/auth/social") {
      await handleSocialAuth(req, res);
      return;
    }

    if (req.method === "POST" && routePath.startsWith("/auth/")) {
      await handleAuth(req, res, routePath);
      return;
    }

    if (req.method === "POST" && routePath.startsWith("/api/ai/")) {
      await handleAI(req, res, routePath);
      return;
    }

    jsonResponse(res, 404, { error: "Not found" });
  } catch (error) {
    handleError(res, "[Mivo backend]", error);
  }
});

server.listen(port, () => {
  console.log(`Mivo backend listening on port ${port}`);
  console.log(`Health check: /health`);
  console.log(`Auth endpoints: /auth/register /auth/login /auth/reset-password /auth/profile`);
  console.log(`AI endpoints: /api/ai/recommend-focus /api/ai/recommend-protected-apps /api/ai/estimate-saved /api/ai/estimate-life-breakdown /api/ai/screen-time-plan`);
  console.log(`Auth database: ${usersPath}`);
});
