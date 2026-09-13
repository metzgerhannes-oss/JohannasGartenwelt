import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "jgw-photos";
const cors = {
  "Access-Control-Allow-Origin": "https://metzgerhannes-oss.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Vary": "Origin",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

function cleanGardenId(v: unknown) {
  return String(v ?? "").trim().toLowerCase();
}

function cleanRelativePath(v: unknown) {
  const p = String(v ?? "").trim().replace(/^\/+/, "");
  if (!p || p.includes("..") || !/^[a-zA-Z0-9_./-]+$/.test(p)) return "";
  return p;
}

function decodeBase64(data: string): Uint8Array {
  const raw = data.includes(",") ? data.slice(data.indexOf(",") + 1) : data;
  const binary = atob(raw);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });

  try {
    const body = await req.json();
    const action = String(body?.action ?? "");
    const gardenId = cleanGardenId(body?.garden_id);
    const secretHash = String(body?.secret_hash ?? "").trim();

    if (gardenId.length < 6 || gardenId.length > 80 || secretHash.length !== 64) {
      return reply(400, { ok: false, error: "invalid_credentials" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) return reply(500, { ok: false, error: "server_not_configured" });

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await admin.rpc("jgw_status_garden", {
      p_garden_id: gardenId,
      p_secret_hash: secretHash,
    });
    if (authError || !authData || authData.ok !== true) {
      return reply(403, { ok: false, error: "forbidden" });
    }

    if (action === "upload") {
      const rel = cleanRelativePath(body?.path);
      const mime = String(body?.mime_type ?? "image/jpeg").toLowerCase();
      const allowed = new Set(["image/jpeg", "image/webp", "image/png"]);
      if (!rel || !allowed.has(mime)) return reply(400, { ok: false, error: "invalid_upload" });
      const encoded = String(body?.data ?? "");
      if (!encoded) return reply(400, { ok: false, error: "missing_data" });
      const bytes = decodeBase64(encoded);
      if (bytes.byteLength > 5 * 1024 * 1024) return reply(413, { ok: false, error: "file_too_large" });

      const objectPath = `${gardenId}/${rel}`;
      const { error } = await admin.storage.from(BUCKET).upload(objectPath, bytes, {
        contentType: mime,
        cacheControl: "3600",
        upsert: true,
      });
      if (error) return reply(500, { ok: false, error: "upload_failed", detail: error.message });
      return reply(200, { ok: true, ref: `jgw-storage:${objectPath}` });
    }

    if (action === "sign") {
      const ref = String(body?.ref ?? "");
      const objectPath = ref.startsWith("jgw-storage:") ? ref.slice("jgw-storage:".length) : cleanRelativePath(ref);
      if (!objectPath || !objectPath.startsWith(`${gardenId}/`) || objectPath.includes("..")) {
        return reply(400, { ok: false, error: "invalid_ref" });
      }
      const { data, error } = await admin.storage.from(BUCKET).createSignedUrl(objectPath, 60 * 60 * 24 * 7);
      if (error || !data?.signedUrl) return reply(404, { ok: false, error: "not_found" });
      return reply(200, { ok: true, url: data.signedUrl, expires_in: 604800 });
    }

    if (action === "delete") {
      const ref = String(body?.ref ?? "");
      const objectPath = ref.startsWith("jgw-storage:") ? ref.slice("jgw-storage:".length) : cleanRelativePath(ref);
      if (!objectPath || !objectPath.startsWith(`${gardenId}/`) || objectPath.includes("..")) {
        return reply(400, { ok: false, error: "invalid_ref" });
      }
      const { error } = await admin.storage.from(BUCKET).remove([objectPath]);
      if (error) return reply(500, { ok: false, error: "delete_failed", detail: error.message });
      return reply(200, { ok: true });
    }

    return reply(400, { ok: false, error: "unknown_action" });
  } catch (error) {
    console.error(error);
    return reply(500, { ok: false, error: "unexpected_error" });
  }
});
