const CAL_NAME = "Johanna´s Gartenwelt – Pflege";

type Plant = {
  id?: string;
  name?: string;
  scientific?: string;
  family?: string;
  type?: string;
  quantity?: number;
  area?: string;
  plantedSince?: string;
  transplanted?: string;
  fertMonths?: number[];
  cutMonths?: number[];
};

type Candidate = {
  kind: string;
  title: string;
  group: string;
  icon: string;
  start: number;
  end: number;
  plants: Plant[];
  note: string;
  key: string;
};

function norm(v: unknown): string {
  return String(v ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function monthName(m: number): string {
  return ["Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember"][m - 1] ?? "";
}

function monthWindow(start: number, end: number): string {
  return start === end ? monthName(start) : monthName(start) + "–" + monthName(end);
}

function consecutiveRanges(input: unknown): Array<{start:number,end:number}> {
  const months = Array.from(new Set((Array.isArray(input) ? input : []).map(Number).filter((m) => m >= 1 && m <= 12))).sort((a,b)=>a-b);
  if (!months.length) return [];
  const out: Array<{start:number,end:number}> = [];
  let start = months[0], prev = months[0];
  for (let i = 1; i < months.length; i++) {
    const m = months[i];
    if (m === prev + 1) { prev = m; continue; }
    out.push({start, end: prev});
    start = prev = m;
  }
  out.push({start, end: prev});
  return out;
}

function textOf(p: Plant): string {
  return norm((p.name || "") + " " + (p.scientific || "") + " " + (p.family || ""));
}

function isFruitTree(p: Plant): boolean {
  const s = norm(p.scientific);
  const n = norm(p.name);
  return [
    "malus domestica","pyrus communis","cydonia oblonga","prunus avium",
    "prunus cerasus","prunus domestica","prunus armeniaca","prunus persica"
  ].some((x)=>s === x || s.startsWith(x + " "))
    || /\b(apfel|birne|zwetschge|pflaume|susskirsche|sauerkirsche|quitte|aprikose|pfirsich)\b/.test(n);
}

function isBerry(p: Plant): boolean {
  const s = norm(p.scientific), n = norm(p.name);
  return /^(ribes|rubus|vaccinium)\b/.test(s) || /\b(johannisbeere|stachelbeere|himbeere|brombeere|heidelbeere)\b/.test(n);
}

function isHydrangea(p: Plant): boolean {
  return /\bhydrangea\b|\bhortensie\b/.test(textOf(p));
}

function isRose(p: Plant): boolean {
  const s = norm(p.scientific), n = norm(p.name);
  return /^rosa\b/.test(s) || /\brose\b|\brosen\b/.test(n);
}

function isGrass(p: Plant): boolean {
  const s = norm(p.scientific), n = norm(p.name);
  return /^(miscanthus|pennisetum|panicum|calamagrostis|cortaderia|imperata|leymus|molinia|stipa)\b/.test(s)
    || /\b(pampasgras|chinaschilf|federborstengras|rutenhirse|reitgras|blutgras|strandroggen)\b/.test(n);
}

function isClimber(p: Plant): boolean {
  const s = norm(p.scientific), n = norm(p.name);
  return /^(clematis|wisteria|parthenocissus|akebia|campsis|vitis)\b/.test(s)
    || /\b(waldrebe|wisteria|blauregen|jungfernrebe|akebie|klettertrompete|wein)\b/.test(n);
}

function isTender(p: Plant): boolean {
  const s = norm(p.scientific), n = norm(p.name);
  return [
    "ficus carica","eucalyptus gunnii","photinia fraseri","cortaderia selloana",
    "salvia rosmarinus","poliomintha bustamanta","albizia"
  ].some((x)=>s === x || s.startsWith(x + " "))
    || /\b(feige|eukalyptus|glanzmispel|pampasgras|rosmarin|seidenbaum)\b/.test(n);
}

function groupFor(p: Plant, kind: string): {key:string,label:string} {
  if (isFruitTree(p)) return {key:"obstbaeume",label:kind === "fert" ? "Obstgehölze" : "Obstbäume"};
  if (isBerry(p)) return {key:"beeren",label:"Beerenobst"};
  if (isRose(p)) return {key:"rosen",label:"Rosen"};
  if (isHydrangea(p)) return {key:"hortensien",label:"Hortensien"};
  if (isGrass(p)) return {key:"ziergraeser",label:"Ziergräser"};
  if (isClimber(p)) return {key:"kletterpflanzen",label:"Kletterpflanzen"};
  const name = String(p.name || p.scientific || "Pflanzen").trim();
  return {key:"plant-" + norm(p.scientific || p.name).replace(/\s+/g,"-"),label:name};
}

function qtyLabel(p: Plant): string {
  const q = Math.max(1, Number(p.quantity || 1));
  const name = String(p.name || p.scientific || "Pflanze");
  return name + (q > 1 ? " ×" + q : "") + (p.area ? " (" + p.area + ")" : "");
}

function addCandidate(map: Map<string,Candidate>, c: Candidate) {
  const old = map.get(c.key);
  if (old) {
    const ids = new Set(old.plants.map((p)=>String(p.id || p.name || p.scientific)));
    for (const p of c.plants) {
      const id = String(p.id || p.name || p.scientific);
      if (!ids.has(id)) { ids.add(id); old.plants.push(p); }
    }
    return;
  }
  map.set(c.key, c);
}

function buildTasks(plants: Plant[], ecology: any): Candidate[] {
  const map = new Map<string,Candidate>();
  const addCare = (p: Plant, kind: "fert"|"cut", months: unknown) => {
    const g = groupFor(p, kind);
    const action = kind === "fert" ? "düngen" : "schneiden";
    const icon = kind === "fert" ? "🌱" : "✂️";
    for (const r of consecutiveRanges(months)) {
      const key = [kind,g.key,r.start,r.end].join("|");
      addCandidate(map,{
        kind,
        title:g.label + " " + action,
        group:g.label,
        icon,
        start:r.start,
        end:r.end,
        plants:[p],
        note:kind === "fert"
          ? "Düngung an Pflanzenzustand, Boden und Witterung anpassen; lieber bedarfsgerecht als schematisch."
          : "Nur bei geeigneter Witterung schneiden. Vor jedem Schnitt auf belegte Nester und Tiere prüfen.",
        key
      });
    }
  };

  for (const p of plants) {
    addCare(p,"fert",p.fertMonths);
    addCare(p,"cut",p.cutMonths);

    if (isGrass(p) && consecutiveRanges(p.cutMonths).length === 0) {
      const g = groupFor(p,"cut");
      addCandidate(map,{
        kind:"spring",
        title:g.label + " zurückschneiden",
        group:g.label,
        icon:"🌾",
        start:3,end:3,plants:[p],
        note:"Vertrocknete Halme erst gegen Ende des Winters bzw. vor dem Neuaustrieb zurücknehmen.",
        key:"spring-grass|"+g.key+"|3|3"
      });
    }

    if (norm(p.scientific).startsWith("cortaderia selloana") || norm(p.name).includes("pampasgras")) {
      addCandidate(map,{
        kind:"winter",
        title:"Pampasgras winterfest machen",
        group:"Pampasgras",
        icon:"❄️",
        start:11,end:11,plants:[p],
        note:"Blattschopf locker zusammenbinden und das Herz besonders vor Winternässe schützen.",
        key:"winter|pampas|11|11"
      });
    }

    if (p.type === "pot" || p.type === "balcony") {
      addCandidate(map,{
        kind:"winter",
        title:"Kübelpflanzen winterfest machen",
        group:"Kübelpflanzen",
        icon:"🪴",
        start:10,end:10,plants:[p],
        note:"Gefäße gegen Durchfrieren schützen, empfindliche Arten rechtzeitig an einen passenden Überwinterungsplatz bringen.",
        key:"winter|containers|10|10"
      });
    } else if (isTender(p)) {
      addCandidate(map,{
        kind:"winter",
        title:"Empfindliche Pflanzen auf Winterschutz prüfen",
        group:"Empfindliche Pflanzen",
        icon:"❄️",
        start:10,end:10,plants:[p],
        note:"Standort, Sorte und aktuelle Wetterprognose beachten. Bei Bedarf Wurzelbereich schützen oder Pflanze einpacken.",
        key:"winter|tender|10|10"
      });
    }

    if (isClimber(p)) {
      addCandidate(map,{
        kind:"support",
        title:"Kletterpflanzen: Bindungen und Kletterhilfen prüfen",
        group:"Kletterpflanzen",
        icon:"🪢",
        start:3,end:3,plants:[p],
        note:"Lose, einschneidende oder beschädigte Bindungen ersetzen und Kletterhilfen vor dem starken Austrieb kontrollieren.",
        key:"support|climbers|3|3"
      });
    }

    const recent = [p.plantedSince,p.transplanted].filter(Boolean).sort().slice(-1)[0];
    if (recent) {
      const d = new Date(recent + "T12:00:00Z");
      const ageDays = (Date.now() - d.getTime()) / 86400000;
      if (Number.isFinite(ageDays) && ageDays >= 0 && ageDays <= 400) {
        addCandidate(map,{
          kind:"winter",
          title:"Jungpflanzen: Wurzelbereich vor Winter schützen",
          group:"Jungpflanzen",
          icon:"🍂",
          start:10,end:11,plants:[p],
          note:"Bei jungen bzw. frisch umgesetzten Pflanzen den Wurzelbereich vor starken Frösten schützen; Staunässe vermeiden.",
          key:"winter|young|10|11"
        });
      }
    }
  }

  if (ecology?.leaveStemsInWinter) {
    addCandidate(map,{
      kind:"nature",
      title:"Überwinterte Staudenstängel behutsam zurücknehmen",
      group:"Naturgarten",
      icon:"🐝",
      start:3,end:4,plants:[],
      note:"Nicht alles auf einmal räumen. Markhaltige Stängel und überwinternde Insekten möglichst schonend behandeln.",
      key:"nature|stems|3|4"
    });
  }
  if (ecology?.leavesPartlyRemain) {
    addCandidate(map,{
      kind:"nature",
      title:"Laub als Winterschutz teilweise liegen lassen",
      group:"Naturgarten",
      icon:"🍂",
      start:10,end:11,plants:[],
      note:"Laub in geeigneten Beet- und Rückzugsbereichen belassen; Rasen und empfindliche immergrüne Polster frei halten.",
      key:"nature|leaves|10|11"
    });
  }

  return Array.from(map.values()).sort((a,b)=>a.start-b.start || a.title.localeCompare(b.title,"de"));
}

function escIcs(v: unknown): string {
  return String(v ?? "")
    .replace(/\\/g,"\\\\")
    .replace(/\r?\n/g,"\\n")
    .replace(/,/g,"\\,")
    .replace(/;/g,"\\;");
}

function dt(y:number,m:number,d=1): string {
  return String(y)+String(m).padStart(2,"0")+String(d).padStart(2,"0");
}

function stamp(): string {
  return new Date().toISOString().replace(/[-:]/g,"").replace(/\.\d{3}Z$/,"Z");
}

function calendarEvent(task: Candidate, year: number): string[] {
  const summary = task.icon + " " + task.title;
  const affected = task.plants.length
    ? task.plants.map(qtyLabel).sort((a,b)=>a.localeCompare(b,"de")).join("; ")
    : "gesamter Garten";
  const description = [
    "Zeitfenster: " + monthWindow(task.start,task.end),
    "Betrifft: " + affected,
    "",
    task.note,
    "",
    "Automatisch aus Johanna´s Gartenwelt. Änderungen im Garten werden beim nächsten Kalender-Abruf übernommen."
  ].join("\n");
  const uidKey = task.key.replace(/[^a-z0-9|-]+/gi,"-").toLowerCase();
  return [
    "BEGIN:VEVENT",
    "UID:"+escIcs("jgw-"+year+"-"+uidKey+"@johannas-gartenwelt"),
    "DTSTAMP:"+stamp(),
    "DTSTART;VALUE=DATE:"+dt(year,task.start,1),
    "DTEND;VALUE=DATE:"+dt(year,task.start,2),
    "SUMMARY:"+escIcs(summary),
    "DESCRIPTION:"+escIcs(description),
    "CATEGORIES:"+escIcs("Gartenpflege,"+task.group),
    "TRANSP:TRANSPARENT",
    "STATUS:CONFIRMED",
    "BEGIN:VALARM",
    "TRIGGER:-P1D",
    "ACTION:DISPLAY",
    "DESCRIPTION:"+escIcs(task.title),
    "END:VALARM",
    "END:VEVENT"
  ];
}

async function calendarPayload(token: string): Promise<any> {
  const base = Deno.env.get("SUPABASE_URL")!;
  let apiKey = "";
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    apiKey = keys.default || "";
  } catch (_) {}
  apiKey ||= Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!base || !apiKey) throw new Error("Supabase-Serverkonfiguration fehlt.");

  const r = await fetch(base + "/rest/v1/rpc/jgw_calendar_payload",{
    method:"POST",
    headers:{"Content-Type":"application/json","apikey":apiKey},
    body:JSON.stringify({p_calendar_token:token})
  });
  const txt = await r.text();
  let data:any = null;
  try { data = txt ? JSON.parse(txt) : null; } catch (_) { data = txt; }
  if (!r.ok) throw new Error((data && data.message) || "Kalenderdaten konnten nicht geladen werden.");
  if (Array.isArray(data) && data.length === 1) data = data[0];
  if (!data || data.ok !== true) throw new Error("Kalender nicht gefunden.");
  return data;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response(null,{headers:{
        "Access-Control-Allow-Origin":"*",
        "Access-Control-Allow-Methods":"GET,OPTIONS",
        "Access-Control-Allow-Headers":"content-type"
      }});
    }
    const u = new URL(req.url);
    const token = String(u.searchParams.get("token") || "").trim().toLowerCase();
    if (!/^[a-f0-9]{64}$/.test(token)) {
      return new Response("Kalender-Link ungültig.",{status:404});
    }

    const data = await calendarPayload(token);
    const tasks = buildTasks(Array.isArray(data.plants) ? data.plants : [], data.ecology || {});
    const now = new Date();
    const years = [now.getUTCFullYear(),now.getUTCFullYear()+1];

    const lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Johannas Gartenwelt//Automatischer Pflegekalender//DE",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "X-WR-CALNAME:"+escIcs(CAL_NAME),
      "X-WR-TIMEZONE:Europe/Berlin",
      "X-WR-CALDESC:"+escIcs("Automatischer, gruppierter Pflegekalender für den gespeicherten Garten."),
      "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
      "X-PUBLISHED-TTL:PT6H"
    ];
    for (const y of years) {
      for (const task of tasks) lines.push(...calendarEvent(task,y));
    }
    lines.push("END:VCALENDAR","");

    return new Response(lines.join("\r\n"),{
      status:200,
      headers:{
        "Content-Type":"text/calendar; charset=utf-8",
        "Content-Disposition":'inline; filename="johannas-gartenwelt-pflege.ics"',
        "Cache-Control":"public, max-age=3600, s-maxage=3600",
        "Access-Control-Allow-Origin":"*"
      }
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return Response.json({error:message},{status:404,headers:{
      "Cache-Control":"no-store",
      "Access-Control-Allow-Origin":"*"
    }});
  }
});
