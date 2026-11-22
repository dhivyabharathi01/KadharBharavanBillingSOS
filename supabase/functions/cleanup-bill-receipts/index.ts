const bucket = "bill-receipts";
const pageSize = 1000;

function respond(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return respond(405, { error: "Method not allowed" });
  }

  const projectUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cleanupSecret = Deno.env.get("BILL_RECEIPT_CLEANUP_SECRET");
  const suppliedSecret = request.headers.get("x-cleanup-secret") || "";
  if (!projectUrl || !serviceRoleKey || !cleanupSecret) {
    return respond(500, { error: "Cleanup function secrets are not configured" });
  }
  if (!constantTimeEqual(suppliedSecret, cleanupSecret)) {
    return respond(401, { error: "Unauthorized" });
  }

  const headers = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };
  const listPage = async (prefix: string, offset: number) => {
    const response = await fetch(`${projectUrl}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        prefix,
        limit: pageSize,
        offset,
        sortBy: { column: "updated_at", order: "asc" },
      }),
    });
    const data = await response.json().catch(() => null);
    if (!response.ok || !Array.isArray(data)) {
      throw new Error(data?.message || "Could not list bill receipt files");
    }
    return data as Array<{ id: string | null; name: string; updated_at?: string | null }>;
  };

  try {
    const cutoff = Date.now() - 14 * 24 * 60 * 60 * 1000;
    const folders: string[] = [];
    for (let offset = 0;; offset += pageSize) {
      const entries = await listPage("", offset);
      folders.push(...entries.filter((entry) => entry.id === null).map((entry) => entry.name));
      if (entries.length < pageSize) break;
    }

    const expired: string[] = [];
    for (const folder of folders) {
      for (let offset = 0;; offset += pageSize) {
        const entries = await listPage(folder, offset);
        for (const entry of entries) {
          if (entry.id && entry.updated_at && Date.parse(entry.updated_at) < cutoff) {
            expired.push(`${folder}/${entry.name}`);
          }
        }
        if (entries.length < pageSize) break;
      }
    }

    let deleted = 0;
    for (let index = 0; index < expired.length; index += 1000) {
      const response = await fetch(`${projectUrl}/storage/v1/object/${bucket}`, {
        method: "DELETE",
        headers,
        body: JSON.stringify({ prefixes: expired.slice(index, index + 1000) }),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok) throw new Error(data?.message || "Could not delete expired bill receipts");
      deleted += Math.min(1000, expired.length - index);
    }

    return respond(200, { deleted, cutoff: new Date(cutoff).toISOString() });
  } catch (error) {
    console.error("Bill receipt cleanup failed", error);
    return respond(500, { error: "Bill receipt cleanup failed" });
  }
});
