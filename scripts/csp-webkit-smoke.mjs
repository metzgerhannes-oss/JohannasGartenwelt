import { webkit, devices } from "playwright";

const base = process.env.JGW_BASE || "http://127.0.0.1:4173";
const results = [];
let failed = false;

function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(JSON.stringify({ name, ok, detail }));
  if (!ok) failed = true;
}

async function limit(label, promise, ms = 8000) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("TIMEOUT " + label + " after " + ms + "ms")), ms);
      })
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function testMain(browser) {
  const iphone = devices["iPhone 13"];
  const context = await browser.newContext(iphone);
  const page = await context.newPage();
  page.setDefaultTimeout(6000);
  page.setDefaultNavigationTimeout(12000);

  const consoleErrors = [];
  const pageErrors = [];
  const failedRequests = [];

  page.on("console", msg => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));
  page.on("requestfailed", req => failedRequests.push(req.url() + " :: " + (req.failure()?.errorText || "failed")));

  let response;
  try {
    response = await limit("main navigation", page.goto(base + "/index.html", { waitUntil: "commit", timeout: 12000 }), 14000);
    record("main HTTP 200", !!response && response.ok(), response ? String(response.status()) : "no response");
  } catch (e) {
    record("main HTTP 200", false, String(e.message || e));
  }

  await new Promise(r => setTimeout(r, 1800));

  try {
    const shot = await limit("main screenshot", page.screenshot({ type: "png" }), 8000);
    record("main renders pixels", !!shot && shot.length > 10000, shot ? String(shot.length) : "0");
  } catch (e) {
    record("main renders pixels", false, String(e.message || e));
  }

  try {
    const html = await limit("main content", page.content(), 8000);
    record("main content contains Johanna", /Johanna/.test(html), "chars=" + html.length);
    record("main tabs in DOM", (html.match(/class=["'][^"']*\btab\b/g) || []).length >= 3);
    record("main settings UI in DOM", /settings/i.test(html));
  } catch (e) {
    record("main DOM readable", false, String(e.message || e));
  }

  const cspConsole = consoleErrors.filter(x => /Content Security Policy|Refused to (execute|apply)|violates the following Content Security Policy/i.test(x));
  const jsConsole = consoleErrors.filter(x => /Uncaught|SyntaxError|ReferenceError|TypeError/i.test(x));
  record("main no CSP console errors", cspConsole.length === 0, cspConsole.join(" | "));
  record("main no JS page errors", pageErrors.length === 0, pageErrors.join(" | "));
  record("main no fatal JS console errors", jsConsole.length === 0, jsConsole.join(" | "));

  const localFailed = failedRequests.filter(x => x.includes("127.0.0.1:4173"));
  record("main local assets load", localFailed.length === 0, localFailed.join(" | "));

  await context.close();
}

async function testSetup(browser) {
  const context = await browser.newContext(devices["iPhone 13"]);
  await context.addInitScript(() => {
    localStorage.setItem("giess_check_garten_v3", JSON.stringify({
      settings: { plantnetKey: "test-plantnet-key" }, plants: [], zones: []
    }));
    localStorage.setItem("johannas_gartenwelt_sync_v1", JSON.stringify({
      url: "https://example.supabase.co",
      key: "test-publishable-key-1234567890",
      gardenId: "garten01",
      secretHash: "a".repeat(64),
      enabled: true
    }));
  });

  const page = await context.newPage();
  page.setDefaultTimeout(6000);
  const consoleErrors = [];
  const pageErrors = [];
  page.on("console", msg => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));

  try {
    const response = await limit("setup navigation", page.goto(base + "/setup.html", { waitUntil: "domcontentloaded", timeout: 12000 }), 14000);
    record("setup HTTP 200", !!response && response.ok(), response ? String(response.status()) : "no response");
  } catch (e) {
    record("setup HTTP 200", false, String(e.message || e));
  }

  try {
    const visible = await limit("setup generator", page.locator("#generatorBox:not(.hidden)").count(), 6000);
    record("setup generator visible", visible === 1, String(visible));
    const qr = await limit("setup QR library", page.evaluate(() => typeof QRCode !== "undefined"), 6000);
    record("setup QR library loaded", !!qr);
  } catch (e) {
    record("setup functional", false, String(e.message || e));
  }

  const cspConsole = consoleErrors.filter(x => /Content Security Policy|Refused to (execute|apply)|violates the following Content Security Policy/i.test(x));
  record("setup no CSP console errors", cspConsole.length === 0, cspConsole.join(" | "));
  record("setup no JS page errors", pageErrors.length === 0, pageErrors.join(" | "));

  await context.close();
}

(async () => {
  const browser = await webkit.launch({ headless: true });
  await testMain(browser);
  await testSetup(browser);
  await browser.close();

  console.log("FINAL_WEBKIT " + JSON.stringify({ ok: !failed, results }));
  if (failed) process.exit(1);
})().catch(err => {
  console.error("FATAL_WEBKIT", err);
  process.exit(1);
});
