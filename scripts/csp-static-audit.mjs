import fs from "node:fs";
import path from "node:path";

const failures = [];
const checks = [];
function check(name, ok, detail = "") {
  checks.push({ name, ok, detail });
  console.log(JSON.stringify({ name, ok, detail }));
  if (!ok) failures.push(name + (detail ? ": " + detail : ""));
}
function read(p){ return fs.readFileSync(p, "utf8"); }

const index = read("index.html");
const setup = read("setup.html");

function metaCsp(html){
  const tags = html.match(/<meta\b[^>]*>/gi) || [];
  for (const tag of tags) {
    if (!/http-equiv\s*=\s*(["'])Content-Security-Policy\1/i.test(tag)) continue;
    const m = tag.match(/content\s*=\s*(["'])([\s\S]*?)\1/i);
    if (m) return m[2];
  }
  return "";
}
function inlineScripts(html){
  return (html.match(/<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?<\/script>/gi) || []).length;
}
function inlineStyles(html){
  return (html.match(/<style\b[^>]*>[\s\S]*?<\/style>/gi) || []).length;
}
function inlineHandlers(html){
  return (html.match(/\son[a-z]+\s*=\s*["']/gi) || []).length;
}

const indexCsp = metaCsp(index);
const setupCsp = metaCsp(setup);
check("index CSP present", !!indexCsp, indexCsp);
check("setup CSP present", !!setupCsp, setupCsp);
check("index no inline scripts", inlineScripts(index) === 0, String(inlineScripts(index)));
check("setup no inline scripts", inlineScripts(setup) === 0, String(inlineScripts(setup)));
check("index no inline style blocks", inlineStyles(index) === 0, String(inlineStyles(index)));
check("setup no inline style blocks", inlineStyles(setup) === 0, String(inlineStyles(setup)));
check("index no inline event handlers", inlineHandlers(index) === 0, String(inlineHandlers(index)));
check("setup no inline event handlers", inlineHandlers(setup) === 0, String(inlineHandlers(setup)));
check("index script unsafe-inline removed", !/script-src[^;]*'unsafe-inline'/.test(indexCsp), indexCsp);
check("setup script unsafe-inline removed", !/script-src[^;]*'unsafe-inline'/.test(setupCsp), setupCsp);
check("index script-src-attr none", /script-src-attr\s+'none'/.test(indexCsp), indexCsp);
check("setup script-src-attr none", /script-src-attr\s+'none'/.test(setupCsp), setupCsp);
check("index style elements hardened", /style-src-elem/.test(indexCsp) && !/style-src-elem[^;]*'unsafe-inline'/.test(indexCsp), indexCsp);
check("setup style elements hardened", /style-src-elem/.test(setupCsp) && !/style-src-elem[^;]*'unsafe-inline'/.test(setupCsp), setupCsp);

const jsFiles = fs.readdirSync(".").filter(x => x.endsWith(".js"));
let dynamicStyleCount = 0;
for (const f of jsFiles) {
  const s = read(f);
  dynamicStyleCount += (s.match(/document\.createElement\(["']style["']\)/g) || []).length;
}
check("no dynamic style element injection", dynamicStyleCount === 0, String(dynamicStyleCount));

const localRefs = [];
for (const html of [index, setup]) {
  for (const m of html.matchAll(/(?:src|href)=["']\.\/([^"'?#]+)[^"']*["']/g)) {
    localRefs.push(m[1]);
  }
}
const missing = [...new Set(localRefs)].filter(p => !fs.existsSync(path.normalize(p)));
check("all local HTML assets exist", missing.length === 0, missing.join(", "));

const sw = read("sw.js");
check("runtime stylesheet linked", index.includes("jgw-runtime-styles.css"));
check("runtime stylesheet cached", sw.includes('"./jgw-runtime-styles.css"'));
check("service worker cache bumped", /jgw-shell-v4/.test(sw));

console.log("FINAL_STATIC " + JSON.stringify({ ok: failures.length === 0, checks, failures }));
if (failures.length) process.exit(1);
