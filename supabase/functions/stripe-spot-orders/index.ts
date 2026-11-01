import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Stripe webhook for Mivo Spots orders. Stripe calls this when a Payment Link checkout is paid
// (or refunded); the order is saved to `spot_orders` so it shows up on usemivo.app/account.
//
// Stripe signs every request. Nothing is saved unless the signature matches STRIPE_WEBHOOK_SECRET,
// and each checkout session is stored once, so Stripe's retries are harmless.

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const encoder = new TextEncoder();

// The two live Payment Links, from usemivo-website/data/shop.ts. A link this list doesn't know
// falls back to the price, then to "other".
const PAYMENT_LINKS: Record<string, { item: "single" | "pack"; spots: number }> = {
  plink_1UV9w5RZs3vYxTPLWqRotPAT: { item: "single", spots: 1 },
  plink_1UV9wtRZs3vYxTPLV4DqYjLt: { item: "pack", spots: 3 },
  plink_1UVin2RZs3vYxTPLdNvZefTW: { item: "pack", spots: 5 },
  plink_1UVipmRZs3vYxTPLeDI27kNb: { item: "pack", spots: 10 },
};
const PRICE_TO_ITEM: Record<number, { item: "single" | "pack"; spots: number }> = {
  1499: { item: "single", spots: 1 },
  3499: { item: "pack", spots: 3 },
  5499: { item: "pack", spots: 5 },
  9999: { item: "pack", spots: 10 },
};

const TOLERANCE_SECONDS = 300;

// Where the buyer said each Spot is going. The website's Buy button sends it in the Payment Link's
// client_reference_id (usemivo-website/lib/spot-picks.ts): "[<account id>_]p_<place>_<place>...",
// or just the account id on older links. Keep PLACES in step with data/spot-places.ts there.
const BLANK = "blank";
const PLACES: Record<string, string> = {
  [BLANK]: "Not sure yet",
  desk: "Desk",
  bedside: "Bedside",
  couch: "Couch",
  car: "Car",
  bathroom: "Bathroom",
  kitchen: "Kitchen",
  gym: "Gym",
  office: "Office",
};
const REFERENCE = /^(?:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_?)?(?:p((?:_[a-z]+)+))?$/i;

// Anything that does not parse, and any place this function does not know, is ignored or blank:
// the reference comes from a URL the buyer could edit, so it only ever labels an order.
function parseReference(reference: string, spots: number): { userId: string | null; picks: string[] } {
  const match = REFERENCE.exec(reference);
  if (!match) return { userId: null, picks: [] };
  const picks = (match[2] ?? "")
    .split("_")
    .slice(1, spots + 1)
    .map((key) => (Object.hasOwn(PLACES, key.toLowerCase()) ? key.toLowerCase() : BLANK));
  if (picks.every((key) => key === BLANK)) return { userId: match[1] ?? null, picks: [] };
  while (picks.length < spots) picks.push(BLANK);
  return { userId: match[1] ?? null, picks };
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function sameString(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function validSignature(body: string, header: string, secret: string): Promise<boolean> {
  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const [key, value] = part.split("=", 2);
    if (key === "t") timestamp = value ?? "";
    if (key === "v1" && value) signatures.push(value);
  }
  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!timestamp || !Number.isFinite(age) || age > TOLERANCE_SECONDS || signatures.length === 0) return false;

  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${body}`)));
  return signatures.some((signature) => sameString(signature, expected));
}

type Address = { line1?: string; line2?: string; city?: string; state?: string; postal_code?: string; country?: string };

function formatAddress(address?: Address | null): string | null {
  if (!address) return null;
  const cityLine = [address.city, [address.state, address.postal_code].filter(Boolean).join(" ")].filter(Boolean).join(", ");
  const lines = [address.line1, address.line2, cityLine, address.country].filter(Boolean);
  return lines.length ? lines.join("\n") : null;
}

const money = (cents: number) => `$${(cents / 100).toFixed(2)}`;

function itemName(item: unknown, spots: unknown): string {
  if (item === "single") return "1 × Mivo Spot";
  if (item === "pack") return `1 × Mivo Spot ${spots}-Pack (${spots} Spots)`;
  return "An item this function does not recognize (open the Stripe payment to see it)";
}

// What the buyer actually bought, straight from Stripe, so a product added later is named correctly.
// Needs STRIPE_SECRET_KEY (a restricted key that can read Checkout Sessions); without it the alert
// falls back to the names above.
async function stripeLineItems(sessionId: string): Promise<string[] | null> {
  const key = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (!key) return null;
  try {
    const response = await fetch(`https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(sessionId)}/line_items?limit=20`, {
      headers: { authorization: `Bearer ${key}` },
    });
    if (!response.ok) return null;
    const { data } = await response.json();
    const lines = (data ?? []).map((line: { description?: string; quantity?: number; amount_total?: number }) =>
      `${line.quantity ?? 1} × ${line.description ?? "Item"} (${money(Number(line.amount_total ?? 0))})`
    );
    return lines.length ? lines : null;
  } catch {
    return null;
  }
}

// Order alerts are sent through Gmail's SMTP server on port 465 (implicit TLS): Supabase Edge
// Functions block outgoing ports 25 and 587. GMAIL_APP_PASSWORD is an app password for GMAIL_USER
// (Google Account > Security > App passwords, which needs 2-step verification), never the account's
// own password.
const SMTP_TIMEOUT_MS = 12_000;

// Emails the owner about a paid order. `saved` is false when the order could not be written to
// spot_orders, so the email says so; the order is still in Stripe.
async function notifyNewOrder(order: Record<string, unknown>, saved: boolean) {
  const user = Deno.env.get("GMAIL_USER") ?? "info.mivoapp@gmail.com";
  // Google shows an app password in four groups of four letters; spaces are not part of it.
  const password = (Deno.env.get("GMAIL_APP_PASSWORD") ?? "").replace(/\s+/g, "");
  const to = Deno.env.get("MIVO_ORDER_ALERT_TO") ?? "pranshuraithatha@gmail.com";
  if (!password) {
    console.error("order_alert_not_sent: GMAIL_APP_PASSWORD is not set");
    return;
  }

  const bought = (await stripeLineItems(String(order.stripe_session_id))) ?? [itemName(order.item, order.spots)];
  const picks = Array.isArray(order.spot_picks) ? (order.spot_picks as string[]) : [];
  const total = money(Number(order.amount_total));
  const text = [
    `New Mivo order: ${total} paid.`,
    ...(saved ? [] : ["", "WARNING: this order could NOT be saved to the orders table, so it will not show on usemivo.app/account. It is in Stripe."]),
    "",
    "Bought:",
    ...bought.map((line) => `- ${line}`),
    `Items ${money(Number(order.amount_subtotal))} + shipping ${money(Number(order.amount_shipping))} = ${total}`,
    "",
    ...(picks.length
      ? ["Where each Spot goes (write it on the card):", ...picks.map((key, index) => `Spot ${index + 1}: ${PLACES[key] ?? PLACES[BLANK]}`)]
      : ["No places picked: leave the card blank."]),
    "",
    "Ship to:",
    String(order.ship_name ?? order.customer_name ?? ""),
    String(order.ship_address ?? "(no address on the order)"),
    "",
    `Customer: ${order.customer_name ?? "unknown"} <${order.email ?? "no email"}>`,
    ...(saved ? [`Order number: ${String(order.id).slice(0, 8).toUpperCase()}`] : []),
    ...(order.stripe_payment_intent ? [`Stripe: https://dashboard.stripe.com/payments/${order.stripe_payment_intent}`] : []),
    ...(saved ? ["", "Mail it, then mark it mailed in the Admin Center (or with admin_update_spot_order)."] : []),
  ].join("\n");

  const client = new SMTPClient({
    connection: { hostname: "smtp.gmail.com", port: 465, tls: true, auth: { username: user, password } },
  });
  let timer: number | undefined;
  try {
    await Promise.race([
      client.send({ from: `Mivo Orders <${user}>`, to, subject: `New Mivo order: ${bought.join(", ")}, ${total}`, content: text }),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("smtp_timeout")), SMTP_TIMEOUT_MS);
      }),
    ]);
  } catch (error) {
    // A failed alert email must not make Stripe retry an order that is already saved.
    console.error("order_alert_failed", error);
  } finally {
    clearTimeout(timer);
    try {
      await client.close();
    } catch {
      // The connection never opened or is already closed.
    }
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  if (!secret) return json(500, { error: "not_configured" });

  const body = await request.text();
  if (!(await validSignature(body, request.headers.get("stripe-signature") ?? "", secret))) {
    return json(400, { error: "bad_signature" });
  }

  // deno-lint-ignore no-explicit-any
  let event: any;
  try {
    event = JSON.parse(body);
  } catch {
    return json(400, { error: "bad_json" });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
    auth: { persistSession: false },
  });

  if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
    const session = event.data.object;
    if (session.payment_status !== "paid") return json(200, { ignored: "not_paid_yet" });

    const subtotal = Number(session.amount_subtotal ?? session.amount_total ?? 0);
    const known = PAYMENT_LINKS[String(session.payment_link ?? "")] ?? PRICE_TO_ITEM[subtotal] ?? { item: "other", spots: 1 };
    const shipping = session.shipping_details ?? session.collected_information?.shipping_details ?? null;
    const details = session.customer_details ?? {};

    const reference = parseReference(String(session.client_reference_id ?? ""), known.spots);
    let userId: string | null = null;
    if (reference.userId) {
      const { data } = await supabase.auth.admin.getUserById(reference.userId);
      userId = data?.user?.id ?? null;
    }

    const row = {
      stripe_session_id: session.id,
      stripe_payment_intent: session.payment_intent ?? null,
      user_id: userId,
      email: details.email ? String(details.email).toLowerCase() : null,
      customer_name: details.name ?? null,
      item: known.item,
      spots: known.spots,
      spot_picks: reference.picks,
      amount_subtotal: subtotal,
      amount_shipping: Number(session.total_details?.amount_shipping ?? 0),
      amount_total: Number(session.amount_total ?? subtotal),
      currency: session.currency ?? "usd",
      ship_name: shipping?.name ?? details.name ?? null,
      ship_address: formatAddress(shipping?.address ?? details.address),
    };

    const { data, error } = await supabase
      .from("spot_orders")
      .upsert(row, { onConflict: "stripe_session_id", ignoreDuplicates: true })
      .select("id")
      .maybeSingle();
    if (error) {
      // Tell the owner anyway; Stripe will retry the save, and each retry repeats this email until it works.
      await notifyNewOrder(row, false);
      return json(500, { error: "save_failed" });
    }
    // `data` is null when Stripe is re-sending an order that was already saved.
    if (data) await notifyNewOrder({ ...row, id: data.id }, true);
    return json(200, { saved: true });
  }

  if (event.type === "charge.refunded") {
    const charge = event.data.object;
    if (charge.refunded === true && charge.payment_intent) {
      const { error } = await supabase.from("spot_orders").update({ status: "refunded" }).eq("stripe_payment_intent", charge.payment_intent);
      if (error) return json(500, { error: "save_failed" });
    }
    return json(200, { saved: true });
  }

  return json(200, { ignored: event.type });
});
