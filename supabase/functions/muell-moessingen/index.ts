const CUSTOMER = "tuebingen";
const BASE = "https://awido.cubefour.de";
const CAL_NAME = "Müllabfuhr Mössingen-Stadt";
const USER_AGENT = "Daely-Muellkalender/1.2";
const JSON_TIMEOUT_MS = 8_000;
const ICS_TIMEOUT_MS = 12_000;
const MAX_JSON_BYTES = 1_000_000;
const MAX_ICS_BYTES = 2_000_000;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

function norm(input: unknown): string {
  return String(input ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("de-DE")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function contentLengthTooLarge(response: Response, limit: number): boolean {
  const raw = response.headers.get("content-length");
  if (!raw) return false;
  const size = Number(raw);
  return Number.isFinite(size) && size > limit;
}

async function getJson(url: string): Promise<any[]> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), JSON_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": USER_AGENT },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`AWIDO JSON status ${response.status}`);
    if (contentLengthTooLarge(response, MAX_JSON_BYTES)) {
      throw new Error("AWIDO JSON response too large");
    }
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_JSON_BYTES) {
      throw new Error("AWIDO JSON response too large");
    }
    const data = JSON.parse(text);
    if (!Array.isArray(data)) throw new Error("AWIDO JSON response has unexpected shape");
    return data;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("AWIDO JSON request timed out");
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function choosePlace(places: any[]) {
  const preferred = ["Mössingen-Stadt", "Mössingen Stadt", "Mössingen"];
  for (const wanted of preferred) {
    const hit = places.find((place) => norm(place?.value) === norm(wanted));
    if (hit) return hit;
  }
  const partial = places.find((place) => norm(place?.value).includes("mossingen"));
  if (partial) return partial;
  throw new Error("Mössingen wurde in AWIDO nicht gefunden.");
}

async function resolveOid() {
  const places = await getJson(
    `${BASE}/WebServices/Awido.Service.svc/secure/getPlaces/client=${CUSTOMER}`,
  );
  const place = choosePlace(places);

  const groups = await getJson(
    `${BASE}/WebServices/Awido.Service.svc/secure/getGroupedStreets/${encodeURIComponent(place.key)}?client=${CUSTOMER}`,
  );

  if (groups.length === 0) {
    return {
      oid: String(place.key),
      place: String(place.value),
      group: null,
      places,
      groups: [],
    };
  }

  const exact = groups.find((group: any) => {
    const value = norm(group?.value);
    return value === norm("Mössingen-Stadt") ||
      value === norm("Mössingen Stadt") ||
      value === norm(place.value);
  });
  if (exact) {
    return {
      oid: String(exact.key),
      place: String(place.value),
      group: String(exact.value ?? ""),
      places,
      groups,
    };
  }

  if (groups.length === 1) {
    return {
      oid: String(groups[0].key),
      place: String(place.value),
      group: String(groups[0].value ?? ""),
      places,
      groups,
    };
  }

  const empty = groups.find((group: any) => norm(group?.value) === "");
  if (empty) {
    return {
      oid: String(empty.key),
      place: String(place.value),
      group: "",
      places,
      groups,
    };
  }

  throw new Error(
    `AWIDO liefert mehrere Unterteilungen für ${place.value}: ${groups.map((group: any) => group.value).join(", ")}`,
  );
}

async function fetchYear(oid: string, year: number): Promise<string> {
  const url = new URL(`${BASE}/Customer/${CUSTOMER}/KalenderICS.aspx`);
  url.searchParams.set("oid", oid);
  url.searchParams.set("jahr", String(year));
  url.searchParams.set("fraktionen", "");
  url.searchParams.set("reminder", "-1.17:00");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ICS_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": USER_AGENT },
      signal: controller.signal,
    });
    if (!response.ok) return "";
    if (contentLengthTooLarge(response, MAX_ICS_BYTES)) {
      throw new Error("AWIDO ICS response too large");
    }
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_ICS_BYTES) {
      throw new Error("AWIDO ICS response too large");
    }
    return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("AWIDO calendar request timed out");
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function eventBlocks(ics: string): string[] {
  return ics.match(/BEGIN:VEVENT\n[\s\S]*?\nEND:VEVENT/g) ?? [];
}

function eventKey(event: string): string {
  const uid = event.match(/^UID:(.+)$/m)?.[1]?.trim();
  if (uid) return `uid:${uid}`;
  const start = event.match(/^DTSTART[^:]*:(.+)$/m)?.[1]?.trim() ?? "";
  const summary = event.match(/^SUMMARY:(.+)$/m)?.[1]?.trim() ?? "";
  return `${start}|${summary}`;
}

function isExcludedContainerEvent(event: string): boolean {
  const summary = norm(event.match(/^SUMMARY:(.+)$/m)?.[1]?.trim() ?? "");
  return summary === "c1" ||
    summary === "c2" ||
    summary.includes("rm container") ||
    summary.includes("restmull container") ||
    summary.includes("restmuell container") ||
    summary.includes("4 rad restmull") ||
    summary.includes("4 rad restmuell");
}

function jsonResponse(body: unknown, status: number, cacheControl: string): Response {
  return Response.json(body, {
    status,
    headers: {
      ...CORS_HEADERS,
      "Cache-Control": cacheControl,
      "X-Content-Type-Options": "nosniff",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...CORS_HEADERS,
        "Cache-Control": "no-store",
      },
    });
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response(null, {
      status: 405,
      headers: {
        ...CORS_HEADERS,
        "Allow": "GET, HEAD, OPTIONS",
        "Cache-Control": "no-store",
      },
    });
  }

  try {
    const requestUrl = new URL(req.url);
    const resolved = await resolveOid();

    if (requestUrl.searchParams.get("debug") === "1") {
      const debugBody = {
        place: resolved.place,
        group: resolved.group,
        oid: resolved.oid,
        placeCandidates: resolved.places
          .filter((place: any) => norm(place?.value).includes("mossingen"))
          .map((place: any) => ({ key: place.key, value: place.value })),
        groupCandidates: resolved.groups.map((group: any) => ({
          key: group.key,
          value: group.value,
        })),
      };
      if (req.method === "HEAD") {
        return new Response(null, {
          status: 200,
          headers: {
            ...CORS_HEADERS,
            "Cache-Control": "no-store",
            "Content-Type": "application/json; charset=utf-8",
            "X-Content-Type-Options": "nosniff",
          },
        });
      }
      return jsonResponse(debugBody, 200, "no-store");
    }

    const now = new Date();
    const years = [now.getUTCFullYear(), now.getUTCFullYear() + 1];
    const chunks = await Promise.all(years.map((year) => fetchYear(resolved.oid, year)));

    const seen = new Set<string>();
    const events: string[] = [];
    for (const chunk of chunks) {
      for (const event of eventBlocks(chunk)) {
        if (isExcludedContainerEvent(event)) continue;
        const key = eventKey(event);
        if (!seen.has(key)) {
          seen.add(key);
          events.push(event);
        }
      }
    }

    if (events.length === 0) throw new Error("AWIDO hat keine Abfuhrtermine geliefert.");

    const body = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Daely Proxy//AWIDO Tuebingen//DE",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      `X-WR-CALNAME:${CAL_NAME}`,
      "X-WR-TIMEZONE:Europe/Berlin",
      `X-WR-CALDESC:Live aus AWIDO Landkreis Tübingen – ${resolved.place}${resolved.group ? ` / ${resolved.group}` : ""}`,
      ...events,
      "END:VCALENDAR",
      "",
    ].join("\r\n");

    const headers = {
      ...CORS_HEADERS,
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="muell-moessingen-stadt.ics"',
      "Cache-Control": "public, max-age=21600, s-maxage=21600",
      "X-Content-Type-Options": "nosniff",
    };

    return new Response(req.method === "HEAD" ? null : body, {
      status: 200,
      headers,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[muell-moessingen]", message);
    return jsonResponse(
      { error: "Kalenderdienst vorübergehend nicht verfügbar." },
      502,
      "no-store",
    );
  }
});
