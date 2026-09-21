import { chromium, webkit, devices } from "playwright";

const base = process.env.JGW_BASE || "http://127.0.0.1:4173";
const requestedBrowser = String(process.env.JGW_BROWSER || "webkit").toLowerCase();
const browserType = requestedBrowser === "chromium" ? chromium : webkit;
const browserName = requestedBrowser === "chromium" ? "Chromium" : "WebKit";
const results = [];
let failed = false;

function record(name, ok, detail = "", fatal = true) {
  results.push({ name, ok, detail, fatal });
  console.log(JSON.stringify({ browser: browserName, name, ok, detail, fatal }));
  if (!ok && fatal) failed = true;
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

function normalized(values) {
  return values.map(x => String(x || "").replace(/\s+/g, " ").trim()).filter(Boolean);
}

async function testMain(browser) {
  const context = await browser.newContext(devices["iPhone 13"]);
  const page = await context.newPage();
  page.setDefaultTimeout(7000);
  page.setDefaultNavigationTimeout(12000);

  const consoleErrors = [];
  const pageErrors = [];
  const failedRequests = [];
  const bootstrapTrace = [];

  page.on("console", msg => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));
  page.on("request", req => {
    if (req.url().includes("127.0.0.1:4173")) bootstrapTrace.push({ event: "request", type: req.resourceType(), url: req.url() });
  });
  page.on("response", res => {
    if (res.url().includes("127.0.0.1:4173")) bootstrapTrace.push({ event: "response", status: res.status(), url: res.url() });
  });
  page.on("requestfailed", req => {
    const detail = req.url() + " :: " + (req.failure()?.errorText || "failed");
    failedRequests.push(detail);
    if (req.url().includes("127.0.0.1:4173")) bootstrapTrace.push({ event: "failed", detail });
  });

  try {
    const response = await limit("main navigation", page.goto(base + "/index.html", { waitUntil: "commit", timeout: 12000 }), 14000);
    record("main HTTP 200", !!response && response.ok(), response ? String(response.status()) : "no response");
  } catch (e) {
    record("main HTTP 200", false, String(e.message || e));
  }

  await new Promise(r => setTimeout(r, 1800));
  console.log("BOOTSTRAP_TRACE " + browserName + " " + JSON.stringify(bootstrapTrace));

  try {
    const shot = await limit("main screenshot", page.screenshot({ type: "png" }), 8000);
    record("main renders pixels", !!shot && shot.length > 10000, shot ? String(shot.length) : "0", false);
  } catch (e) {
    record("main renders pixels", false, String(e.message || e), false);
  }

  try {
    const html = await limit("main content", page.content(), 8000);
    record("main content contains Johanna", /Johanna/.test(html), "chars=" + html.length);
    record("main settings UI in DOM", /settingsOverlay/.test(html));
  } catch (e) {
    record("main DOM readable", false, String(e.message || e));
  }

  try {
    const labels = normalized(await limit("main navigation labels", page.locator(".tabs .tab").allTextContents(), 7000));
    const expected = ["Heute", "Mein Garten", "Aufgaben", "Bibliothek", "Mehr"];
    record("main navigation labels", JSON.stringify(labels) === JSON.stringify(expected), labels.join(" | "));
    record("today view visible", await limit("today visible", page.locator("#view-today").isVisible(), 7000));
  } catch (e) {
    record("main navigation functional", false, String(e.message || e));
  }

  try {
    const fab = page.locator(".jgw-fab");
    record("add button visible", await limit("fab visible", fab.isVisible(), 7000));
    await limit("fab click", fab.click(), 7000);
    record("add sheet visible", await limit("add sheet visible", page.locator(".jgw-add-sheet").isVisible(), 7000));
    const options = normalized(await limit("add options", page.locator(".jgw-add-option b").allTextContents(), 7000));
    record("add options current", JSON.stringify(options) === JSON.stringify(["Pflanze", "Lebensraum", "Tierbeobachtung"]), options.join(" | "));

    await limit("open plant editor", page.locator('.jgw-add-option[data-kind="plants"]').click(), 7000);
    await limit("wait plant editor", page.locator("#plantEditor").waitFor({ state: "visible", timeout: 7000 }), 8000);
    record("plant editor opens", await page.locator("#plantEditor").isVisible());

    const pick = String(await page.locator("#plantEditor .jgw-pick").textContent() || "").trim();
    const camera = String(await page.locator("#plantEditor .jgw-camera").textContent() || "").trim();
    const capture = await page.locator("#plantPhoto").getAttribute("capture");
    record("photo picker separated from camera", pick === "Foto auswählen" && camera === "Kamera öffnen" && capture === null, [pick, camera, "capture=" + capture].join(" | "));

    await limit("close plant editor", page.locator("#closePlantEditor").click(), 7000);
  } catch (e) {
    record("add and plant editor flow", false, String(e.message || e));
  }

  try {
    await limit("open more", page.locator('.tabs .tab[data-view="more"]').click(), 7000);
    await limit("open settings", page.locator("#moreSettingsBtn").click(), 7000);
    await limit("wait settings", page.locator("#settingsOverlay").waitFor({ state: "visible", timeout: 7000 }), 8000);
    const groups = await page.locator("#settingsOverlay .jgw-settings-group").count();
    record("settings opens", await page.locator("#settingsOverlay").isVisible());
    record("settings groups current", groups === 4, String(groups));
  } catch (e) {
    record("settings flow", false, String(e.message || e));
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
  page.setDefaultTimeout(7000);
  const consoleErrors = [];
  const pageErrors = [];
  page.on("console", msg => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));

  try {
    const response = await limit("setup navigation", page.goto(base + "/setup.html", { waitUntil: "commit", timeout: 12000 }), 14000);
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
  const browser = await browserType.launch({ headless: true });
  await testMain(browser);
  await testSetup(browser);
  await browser.close();

  console.log("FINAL_BROWSER " + JSON.stringify({ browser: browserName, ok: !failed, results }));
  if (failed) process.exit(1);
})().catch(err => {
  console.error("FATAL_BROWSER", browserName, err);
  process.exit(1);
});
