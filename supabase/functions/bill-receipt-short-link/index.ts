const bucket = "bill-receipts";
const linkLifetimeSeconds = 7 * 24 * 60 * 60;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function respond(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function responseBody(response: Response) {
  return await response.json().catch(() => null);
}

function objectPathUrl(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function signedUrl(baseUrl: string, value: string) {
  if (/^https?:\/\//i.test(value)) return value;
  return `${baseUrl}${value.startsWith("/storage/v1/") ? value : `/storage/v1${value.startsWith("/") ? value : `/${value}`}`}`;
}

function paymentPageUrl(paymentUri: string) {
  const appOrigin = Deno.env.get("BILLING_APP_ORIGIN");
  if (!appOrigin) throw new Error("Billing app origin is not configured");
  const appUrl = new URL(appOrigin);
  if (appUrl.protocol !== "https:" || appUrl.pathname !== "/" || appUrl.search || appUrl.hash) {
    throw new Error("Billing app origin must be an HTTPS origin");
  }
  const url = new URL("/upi-pay.html", appUrl.origin);
  url.searchParams.set("p", btoa(paymentUri).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, ""));
  return url.href;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "GET" && request.method !== "POST") {
    return respond(405, { error: "Method not allowed" });
  }

  const projectUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !anonKey || !serviceRoleKey) {
    return respond(500, { error: "Supabase function secrets are not configured" });
  }

  const adminHeaders = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };

  try {
    if (request.method === "GET") {
      const token = new URL(request.url).pathname.split("/").filter(Boolean).pop() || "";
      if (!uuidPattern.test(token)) return respond(404, { error: "Receipt link not found" });
      const query = new URLSearchParams({
        select: "link_type,object_path,payment_uri,expires_at",
        token: `eq.${token}`,
        expires_at: `gt.${new Date().toISOString()}`,
        limit: "1",
      });
      const linkResponse = await fetch(`${projectUrl}/rest/v1/bill_receipt_links?${query}`, {
        headers: adminHeaders,
      });
      const links = await responseBody(linkResponse);
      if (!linkResponse.ok) throw new Error("Could not verify the receipt link");
      if (!Array.isArray(links) || !links.length) {
        return respond(404, { error: "Receipt link expired or not found" });
      }

      const remainingSeconds = Math.floor((Date.parse(links[0].expires_at) - Date.now()) / 1000);
      if (remainingSeconds <= 0) return respond(404, { error: "Receipt link expired" });
      if (links[0].link_type === "payment") {
        if (typeof links[0].payment_uri !== "string") {
          throw new Error("Could not verify the payment link");
        }
        return new Response(null, {
          status: 302,
          headers: {
            Location: paymentPageUrl(links[0].payment_uri),
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
          },
        });
      }
      if (links[0].link_type !== "receipt" || typeof links[0].object_path !== "string") {
        return respond(404, { error: "Receipt link not found" });
      }
      const signResponse = await fetch(
        `${projectUrl}/storage/v1/object/sign/${bucket}/${objectPathUrl(links[0].object_path)}`,
        {
          method: "POST",
          headers: adminHeaders,
          body: JSON.stringify({ expiresIn: Math.min(linkLifetimeSeconds, remainingSeconds) }),
        },
      );
      const signBody = await responseBody(signResponse);
      if (!signResponse.ok) throw new Error("Could not open the receipt PDF");
      const target = signBody?.signedURL || signBody?.signedUrl;
      if (typeof target !== "string" || !target) throw new Error("Could not create a temporary receipt link");
      return new Response(null, {
        status: 302,
        headers: {
          Location: signedUrl(projectUrl, target),
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      });
    }

    const authorization = request.headers.get("Authorization");
    const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!accessToken) return respond(401, { error: "Sign in to share this receipt" });

    const input = await request.json().catch(() => null);
    if (!input || typeof input !== "object") return respond(400, { error: "Invalid request body" });
    const shopId = typeof input.shop_id === "string" ? input.shop_id.trim() : "";
    const billId = typeof input.bill_id === "string" ? input.bill_id.trim() : "";
    const objectPath = typeof input.object_path === "string" ? input.object_path.trim() : "";
    const kind = input.kind;
    const parts = objectPath.split("/");
    if (!uuidPattern.test(shopId) || !uuidPattern.test(billId) ||
      (kind !== "receipt" && kind !== "payment") ||
      (kind === "receipt" && (
        parts.length !== 3 || parts[0] !== shopId || parts[1] !== billId ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$/i.test(parts[2])
      ))) {
      return respond(400, { error: "Invalid bill receipt" });
    }

    const userResponse = await fetch(`${projectUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
    });
    if (!userResponse.ok) return respond(401, { error: "Your session expired. Sign in again." });
    const user = await responseBody(userResponse);

    const memberQuery = new URLSearchParams({
      select: "role",
      shop_id: `eq.${shopId}`,
      user_id: `eq.${user.id}`,
      limit: "1",
    });
    const [memberResponse, billResponse] = await Promise.all([
      fetch(`${projectUrl}/rest/v1/shop_members?${memberQuery}`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
      }),
      fetch(`${projectUrl}/rest/v1/bills?select=id,shop_id,created_by,bill_number,total,payment_method&id=eq.${billId}&shop_id=eq.${shopId}&limit=1`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
      }),
    ]);
    const [members, bills] = await Promise.all([responseBody(memberResponse), responseBody(billResponse)]);
    if (!memberResponse.ok || !billResponse.ok) {
      throw new Error("Could not verify bill access");
    }
    if (!user?.id || !Array.isArray(members) || !members.length || !Array.isArray(bills) || !bills.length ||
      (bills[0].created_by !== user.id && members[0].role !== "owner")) {
      return respond(403, { error: "Only the bill creator or shop owner can share this receipt" });
    }

    let paymentUri: string | null = null;
    if (kind === "receipt") {
      const objectResponse = await fetch(
        `${projectUrl}/storage/v1/object/info/${bucket}/${objectPathUrl(objectPath)}`,
        { headers: adminHeaders },
      );
      if (!objectResponse.ok) return respond(404, { error: "Receipt PDF not found" });
    } else {
      if (bills[0].payment_method !== "upi" || !Number.isFinite(Number(bills[0].total)) || Number(bills[0].total) <= 0) {
        return respond(400, { error: "This bill is not eligible for UPI payment" });
      }
      const shopResponse = await fetch(
        `${projectUrl}/rest/v1/shops?select=name,upi_id&id=eq.${shopId}&limit=1`,
        { headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` } },
      );
      const shops = await responseBody(shopResponse);
      if (!shopResponse.ok || !Array.isArray(shops)) throw new Error("Could not verify shop payment details");
      if (!shops.length || typeof shops[0].upi_id !== "string" || !shops[0].upi_id) {
        return respond(400, { error: "The shop does not have a UPI ID configured" });
      }
      if (!Deno.env.get("BILLING_APP_ORIGIN")) {
        throw new Error("Billing app origin is not configured");
      }
      paymentUri = `upi://pay?${new URLSearchParams({
        pa: shops[0].upi_id,
        pn: shops[0].name || "Kadhar Bhavan",
        am: Number(bills[0].total).toFixed(2),
        cu: "INR",
        tn: `Bill ${bills[0].bill_number}`,
      })}`;
      paymentPageUrl(paymentUri);
    }

    const expiresAt = new Date(Date.now() + linkLifetimeSeconds * 1000).toISOString();
    const linkResponse = await fetch(`${projectUrl}/rest/v1/bill_receipt_links?select=token,expires_at`, {
      method: "POST",
      headers: { ...adminHeaders, Prefer: "return=representation" },
      body: JSON.stringify({
        shop_id: shopId,
        bill_id: billId,
        link_type: kind,
        object_path: kind === "receipt" ? objectPath : null,
        payment_uri: paymentUri,
        created_by: user.id,
        expires_at: expiresAt,
      }),
    });
    const links = await responseBody(linkResponse);
    if (!linkResponse.ok || !Array.isArray(links) || !links.length) {
      throw new Error("Could not create a short receipt link");
    }

    return respond(200, {
      url: `${projectUrl}/functions/v1/bill-receipt-short-link/${links[0].token}`,
      expires_at: links[0].expires_at,
    });
  } catch (error) {
    console.error("Bill receipt short link failed", error);
    return respond(500, { error: "Could not create or open the receipt link" });
  }
});
