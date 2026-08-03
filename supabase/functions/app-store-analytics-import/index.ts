import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json" },
});

async function appleJWT(): Promise<string> {
  const issuer = Deno.env.get("ASC_ISSUER_ID") ?? "";
  const keyID = Deno.env.get("ASC_KEY_ID") ?? "";
  const rawKey = (Deno.env.get("ASC_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  if (!issuer || !keyID || !rawKey) throw new Error("app_store_credentials_missing");
  const key = await importPKCS8(rawKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID, typ: "JWT" })
    .setIssuer(issuer).setAudience("appstoreconnect-v1").setIssuedAt().setExpirationTime("15m").sign(key);
}

async function apple(path: string, token: string, init: RequestInit = {}) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    ...init, headers: { authorization: `Bearer ${token}`, "content-type": "application/json", ...(init.headers ?? {}) },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`apple_${response.status}_${body?.errors?.[0]?.code ?? "request_failed"}`);
  return body;
}

function parseTSV(text: string): Record<string, string>[] {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean);
  if (lines.length < 2) return [];
  const headers = lines[0].split("\t");
  return lines.slice(1).map((line) => Object.fromEntries(line.split("\t").map((value, index) => [headers[index], value])));
}

function first(row: Record<string, string>, names: string[]): string | undefined {
  const normalized = new Map(Object.entries(row).map(([key, value]) => [key.toLowerCase().replaceAll(/[^a-z0-9]/g, ""), value]));
  for (const name of names) {
    const value = normalized.get(name.toLowerCase().replaceAll(/[^a-z0-9]/g, ""));
    if (value !== undefined && value !== "") return value;
  }
  return undefined;
}

async function segmentText(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`segment_${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    return await new Response(stream).text();
  }
  return new TextDecoder().decode(bytes);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const cronSecret = Deno.env.get("MIVO_ANALYTICS_CRON_SECRET") ?? "";
  if (!supabaseURL || !serviceKey) return json(500, { error: "service_not_configured" });
  const service = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  const isCron = Boolean(cronSecret) && request.headers.get("x-mivo-cron-secret") === cronSecret;
  if (!isCron) {
    const authorization = request.headers.get("authorization") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const userClient = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: userData } = await userClient.auth.getUser();
    if (!userData.user) return json(401, { error: "authentication_required" });
    const { data: access } = await service.from("app_admins").select("role").eq("user_id", userData.user.id).eq("role", "super_admin").maybeSingle();
    if (!access) return json(403, { error: "super_admin_required" });
  }

  const appID = Deno.env.get("ASC_APP_ID") ?? "";
  if (!appID) return json(503, { error: "app_store_app_id_missing" });
  try {
    const token = await appleJWT();
    let requests = await apple(`/v1/analyticsReportRequests?filter[app]=${encodeURIComponent(appID)}`, token);
    let requestID = requests.data?.find((item: any) => item.attributes?.accessType === "ONGOING")?.id;
    if (!requestID) {
      const created = await apple("/v1/analyticsReportRequests", token, {
        method: "POST",
        body: JSON.stringify({ data: { type: "analyticsReportRequests", attributes: { accessType: "ONGOING" }, relationships: { app: { data: { type: "apps", id: appID } } } } }),
      });
      requestID = created.data?.id;
      return json(202, { ok: true, state: "requested", request_id: requestID, message: "Apple normally generates the first report in 1-2 days." });
    }

    const reports = await apple(`/v1/analyticsReportRequests/${requestID}/reports?limit=200`, token);
    const rowsByKey = new Map<string, Record<string, unknown>>();
    let downloadedSegments = 0;
    for (const report of reports.data ?? []) {
      const name = String(report.attributes?.name ?? "").toLowerCase();
      if (!["usage", "engagement", "commerce", "performance", "download", "installation", "crash"].some((part) => name.includes(part))) continue;
      const instances = await apple(`/v1/analyticsReports/${report.id}/instances?limit=200`, token);
      for (const instance of instances.data ?? []) {
        const segments = await apple(`/v1/analyticsReportInstances/${instance.id}/segments?limit=200`, token);
        for (const segment of segments.data ?? []) {
          const url = segment.attributes?.url;
          if (!url) continue;
          downloadedSegments += 1;
          for (const source of parseTSV(await segmentText(url))) {
            const date = first(source, ["Date", "Day", "Report Date"]);
            if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
            const version = first(source, ["App Version", "Version"]) ?? "";
            const key = `${date}|${version}`;
            const target = rowsByKey.get(key) ?? { metric_date: date, app_version: version || null, reporting_status: "available" };
            const mappings: [string, string[]][] = [
              ["downloads", ["Downloads", "Total Downloads", "App Units"]],
              ["installations", ["Installations", "Total Installations"]],
              ["deletions", ["Deletions", "Uninstalls"]],
              ["sessions", ["Sessions", "Total Sessions"]],
              ["crashes", ["Crashes", "Total Crashes"]],
            ];
            for (const [field, names] of mappings) {
              const value = first(source, names);
              if (value !== undefined && Number.isFinite(Number(value))) target[field] = Number(target[field] ?? 0) + Number(value);
            }
            rowsByKey.set(key, target);
          }
        }
      }
    }

    const importID = `asc-${requestID}-${new Date().toISOString().slice(0, 10)}`;
    const rows = [...rowsByKey.values()];
    if (!rows.length) rows.push({ metric_date: new Date().toISOString().slice(0, 10), app_version: null, reporting_status: downloadedSegments ? "suppressed" : "delayed" });
    const { data: imported, error } = await service.rpc("import_app_store_daily_metrics", { input_rows: rows, input_import_id: importID });
    if (error) throw error;
    return json(200, { ok: true, request_id: requestID, reports: reports.data?.length ?? 0, segments: downloadedSegments, imported_rows: imported });
  } catch (error) {
    return json(502, { error: error instanceof Error ? error.message : String(error) });
  }
});
