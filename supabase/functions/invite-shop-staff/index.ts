const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function responseBody(response) {
  return await response.json().catch(() => ({}));
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond(405, { error: "Method not allowed" });
  }

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !anonKey || !serviceRoleKey) {
    return respond(500, { error: "Supabase function secrets are not configured" });
  }

  const authorization = request.headers.get("Authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return respond(401, { error: "Sign in as the shop owner first" });

  let input;
  try {
    input = await request.json();
  } catch {
    return respond(400, { error: "Invalid request body" });
  }
  if (!input || typeof input !== "object") {
    return respond(400, { error: "Invalid request body" });
  }

  const shopId = input.shop_id?.trim();
  const email = input.email?.trim().toLowerCase();
  const displayName = input.display_name?.trim();
  if (!shopId || !/^[0-9a-f-]{36}$/i.test(shopId)) {
    return respond(400, { error: "Invalid shop" });
  }
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return respond(400, { error: "Enter a valid staff email address" });
  }
  if (!displayName || displayName.length > 100) {
    return respond(400, { error: "Enter a staff name of 1–100 characters" });
  }

  const baseUrl = projectUrl.replace(/\/$/, "");
  const userResponse = await fetch(`${baseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
  });
  if (!userResponse.ok) return respond(401, { error: "Your session expired. Sign in again." });
  const user = await responseBody(userResponse);

  const ownerQuery = new URLSearchParams({
    select: "user_id",
    shop_id: `eq.${shopId}`,
    user_id: `eq.${user.id}`,
    role: "eq.owner",
    limit: "1",
  });
  const ownerResponse = await fetch(`${baseUrl}/rest/v1/shop_members?${ownerQuery}`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
  });
  if (!ownerResponse.ok) return respond(403, { error: "Could not verify shop ownership" });
  const ownerRows = await responseBody(ownerResponse);
  if (!Array.isArray(ownerRows) || ownerRows.length === 0) {
    return respond(403, { error: "Only the shop owner can invite staff" });
  }

  const inviteResponse = await fetch(`${baseUrl}/auth/v1/invite`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, data: { display_name: displayName } }),
  });
  const inviteBody = await responseBody(inviteResponse);
  const alreadyRegistered = !inviteResponse.ok &&
    /already registered|already exists|email_exists/i.test(
      String(inviteBody.msg || inviteBody.message || inviteBody.code || ""),
    );
  if (!inviteResponse.ok && !alreadyRegistered) {
    return respond(inviteResponse.status, {
      error: inviteBody.msg || inviteBody.message || "Could not send staff invitation",
    });
  }

  const assignmentResponse = await fetch(`${baseUrl}/rest/v1/rpc/add_shop_staff`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_shop_id: shopId,
      p_email: email,
      p_display_name: displayName,
    }),
  });
  const assignmentBody = await responseBody(assignmentResponse);
  if (!assignmentResponse.ok) {
    return respond(inviteResponse.ok ? 502 : assignmentResponse.status, {
      error: inviteResponse.ok
        ? "Invitation sent, but shop access could not be assigned"
        : assignmentBody.message || assignmentBody.details || "Could not assign this account to the shop",
    });
  }

  return respond(200, { invited: inviteResponse.ok });
});
