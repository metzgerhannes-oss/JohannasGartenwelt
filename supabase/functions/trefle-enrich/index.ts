import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ALLOWED_ORIGINS = new Set([
  "https://metzgerhannes-oss.github.io",
]);

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowOrigin = ALLOWED_ORIGINS.has(origin)
    ? origin
    : "https://metzgerhannes-oss.github.io";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function cleanScientificName(value: unknown) {
  return String(value || "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 180);
}

function validScientificName(value: string) {
  return value.length >= 3 && /^[\p{L}0-9 .×'’()\-]+$/u.test(value);
}

function normalizeStatusResult(value: unknown): any {
  if (Array.isArray(value) && value.length === 1) return value[0];
  return value;
}

async function gardenAuthorized(gardenId: string, secretHash: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!supabaseUrl || !anonKey) return false;

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/jgw_status_garden`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_garden_id: gardenId,
      p_secret_hash: secretHash,
    }),
  });

  if (!response.ok) return false;
  const data = normalizeStatusResult(await response.json());
  return !!(data && data.ok === true);
}

function safeTrefleDetail(data: any) {
  if (!data || typeof data !== "object") return null;
  return {
    id: data.id ?? null,
    slug: data.slug ?? null,
    scientific_name: data.scientific_name ?? null,
    common_name: data.common_name ?? null,
    family: data.family ?? null,
    family_common_name: data.family_common_name ?? null,
    genus: data.genus ?? null,
    status: data.status ?? null,
    rank: data.rank ?? null,
    duration: Array.isArray(data.duration) ? data.duration : [],
    observations: data.observations ?? null,
    distribution: data.distribution ?? null,
    distributions: data.distributions ?? data.distribution ?? null,
    growth: data.growth ?? null,
    specifications: data.specifications ?? null,
    sources: Array.isArray(data.sources) ? data.sources : [],
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== "POST") {
    return json(req, { ok: false, error: "method_not_allowed" }, 405);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(req, { ok: false, error: "invalid_json" }, 400);
  }

  const scientificName = cleanScientificName(body?.scientific_name);
  const gardenId = String(body?.garden_id || "").trim().toLowerCase();
  const secretHash = String(body?.secret_hash || "").trim().toLowerCase();

  if (!validScientificName(scientificName)) {
    return json(req, { ok: false, error: "invalid_scientific_name" }, 400);
  }
  if (gardenId.length < 6 || gardenId.length > 80 || !/^[a-z0-9_-]+$/i.test(gardenId)) {
    return json(req, { ok: false, error: "invalid_garden_id" }, 400);
  }
  if (!/^[a-f0-9]{64}$/.test(secretHash)) {
    return json(req, { ok: false, error: "invalid_garden_secret" }, 400);
  }

  if (!(await gardenAuthorized(gardenId, secretHash))) {
    return json(req, { ok: false, error: "unauthorized_garden" }, 401);
  }

  const token = Deno.env.get("TREFLE_TOKEN") || "";
  if (!token) {
    return json(req, { ok: false, error: "trefle_not_configured" }, 503);
  }

  try {
    const searchUrl = new URL("https://trefle.io/api/v1/species/search");
    searchUrl.searchParams.set("token", token);
    searchUrl.searchParams.set("q", scientificName);
    searchUrl.searchParams.set("limit", "5");

    const searchResponse = await fetch(searchUrl, {
      headers: { Accept: "application/json" },
    });
    if (!searchResponse.ok) {
      return json(req, {
        ok: false,
        error: "trefle_search_failed",
        upstream_status: searchResponse.status,
      }, 502);
    }

    const searchPayload = await searchResponse.json();
    const results = Array.isArray(searchPayload?.data) ? searchPayload.data : [];
    if (!results.length) {
      return json(req, { ok: true, found: false, data: null });
    }

    const wanted = scientificName.toLocaleLowerCase("en");
    const hit = results.find((item: any) =>
      String(item?.scientific_name || "").toLocaleLowerCase("en") === wanted
    ) || results[0];

    const selfLink = String(hit?.links?.self || "");
    if (!selfLink) {
      return json(req, { ok: true, found: false, data: null });
    }

    const detailUrl = new URL(selfLink, "https://trefle.io");
    if (detailUrl.hostname !== "trefle.io" || !detailUrl.pathname.startsWith("/api/v1/")) {
      return json(req, { ok: false, error: "invalid_trefle_detail_url" }, 502);
    }
    detailUrl.searchParams.set("token", token);

    const detailResponse = await fetch(detailUrl, {
      headers: { Accept: "application/json" },
    });
    if (!detailResponse.ok) {
      return json(req, {
        ok: false,
        error: "trefle_detail_failed",
        upstream_status: detailResponse.status,
      }, 502);
    }

    const detailPayload = await detailResponse.json();
    return json(req, {
      ok: true,
      found: true,
      data: safeTrefleDetail(detailPayload?.data),
    });
  } catch (error) {
    console.error("trefle-enrich failed", error instanceof Error ? error.message : String(error));
    return json(req, { ok: false, error: "trefle_proxy_failed" }, 502);
  }
});
