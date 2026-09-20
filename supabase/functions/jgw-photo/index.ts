import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "jgw-photos";
const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
const MAX_BASE64_CHARS = Math.ceil(MAX_UPLOAD_BYTES / 3) * 4 + 128;
const MAX_REQUEST_BYTES = MAX_BASE64_CHARS + 64 * 1024;
const cors = {
  "Access-Control-Allow-Origin": "https://metzgerhannes-oss.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Vary": "Origin",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

function cleanGardenId(v: unknown) {
  const id = String(v ?? "").trim().toLowerCase();
  return id.length >= 6 && id.length <= 80 && /^[a-z0-9_-]+$/.test(id) ? id : "";
}

function cleanRelativePath(v: unknown) {
  const p = String(v ?? "").trim().replace(/^\/+/, "");
  if (!p || p.includes("..") || !/^[a-zA-Z0-9_./-]+$/.test(p)) return "";
  return p;
}

function base64Payload(data: string) {
  return data.includes(",") ? data.slice(data.indexOf(",") + 1) : data;
}

function decodeBase64(data: string): Uint8Array {
  const raw = base64Payload(data);
  const binary = atob(raw);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function isJpeg(bytes: Uint8Array) {
  return bytes.byteLength >= 4
    && bytes[0] === 0xff
    && bytes[1] === 0xd8
    && bytes[2] === 0xff;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });

  const contentLength = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) {
    return reply(413, { ok: false, error: "request_too_large" });
  }

  try {
    const body = await req.json();
    const action = String(body?.action ?? "");
    const gardenId = cleanGardenId(body?.garden_id);
    const secretHash = String(body?.secret_hash ?? "").trim();

    if (!gardenId || !/^[a-f0-9]{64}$/i.test(secretHash)) {
      return reply(400, { ok: false, error: "invalid_credentials" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    let serviceKey = "";
    let anonKey = "";
    try { serviceKey = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch (_) {}
    try { anonKey = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}").default || ""; } catch (_) {}
    serviceKey ||= Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    anonKey ||= Deno.env.get("SUPABASE_ANON_KEY") || "";
    if (!supabaseUrl || !serviceKey || !anonKey) return reply(500, { ok: false, error: "server_not_configured" });

    const authResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/jgw_status_garden`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_garden_id: gardenId,
        p_secret_hash: secretHash,
      }),
      signal: AbortSignal.timeout(8000),
    });
    let authData: any = null;
    try { authData = await authResponse.json(); } catch (_) {}
    if (Array.isArray(authData) && authData.length === 1) authData = authData[0];
    if (!authResponse.ok || !authData || authData.ok !== true) {
      return reply(403, { ok: false, error: "forbidden" });
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === "upload") {
      const rel = cleanRelativePath(body?.path);
      const mime = String(body?.mime_type ?? "image/jpeg").toLowerCase();
      if (!rel || !rel.toLowerCase().endsWith(".jpg") || mime !== "image/jpeg") {
        return reply(400, { ok: false, error: "invalid_upload" });
      }
      const encoded = String(body?.data ?? "");
      if (!encoded) return reply(400, { ok: false, error: "missing_data" });
      const raw = base64Payload(encoded);
      if (raw.length > MAX_BASE64_CHARS) return reply(413, { ok: false, error: "file_too_large" });
      let bytes: Uint8Array;
      try {
        bytes = decodeBase64(raw);
      } catch {
        return reply(400, { ok: false, error: "invalid_image_data" });
      }
      if (bytes.byteLength > MAX_UPLOAD_BYTES) return reply(413, { ok: false, error: "file_too_large" });
      if (!isJpeg(bytes)) return reply(400, { ok: false, error: "invalid_image_data" });

      const objectPath = `${gardenId}/${rel}`;
      const { error } = await admin.storage.from(BUCKET).upload(objectPath, bytes, {
        contentType: mime,
        cacheControl: "3600",
        upsert: true,
      });
      if (error) {
        console.error("jgw-photo upload failed", error.message);
        return reply(500, { ok: false, error: "upload_failed" });
      }
      return reply(200, { ok: true, ref: `jgw-storage:${objectPath}` });
    }

    if (action === "sign") {
      const ref = String(body?.ref ?? "");
      const rawPath = ref.startsWith("jgw-storage:") ? ref.slice("jgw-storage:".length) : ref;
      const objectPath = cleanRelativePath(rawPath);
      if (!objectPath || !objectPath.startsWith(`${gardenId}/`)) {
        return reply(400, { ok: false, error: "invalid_ref" });
      }
      const { data, error } = await admin.storage.from(BUCKET).createSignedUrl(objectPath, 60 * 60 * 24 * 7);
      if (error || !data?.signedUrl) return reply(404, { ok: false, error: "not_found" });
      return reply(200, { ok: true, url: data.signedUrl, expires_in: 604800 });
    }

    if (action === "delete") {
      const ref = String(body?.ref ?? "");
      const rawPath = ref.startsWith("jgw-storage:") ? ref.slice("jgw-storage:".length) : ref;
      const objectPath = cleanRelativePath(rawPath);
      if (!objectPath || !objectPath.startsWith(`${gardenId}/`)) {
        return reply(400, { ok: false, error: "invalid_ref" });
      }
      const { error } = await admin.storage.from(BUCKET).remove([objectPath]);
      if (error) {
        console.error("jgw-photo delete failed", error.message);
        return reply(500, { ok: false, error: "delete_failed" });
      }
      return reply(200, { ok: true });
    }

    return reply(400, { ok: false, error: "unknown_action" });
  } catch (error) {
    console.error(error);
    return reply(500, { ok: false, error: "unexpected_error" });
  }
});
