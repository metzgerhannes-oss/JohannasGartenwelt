import { chromium, devices } from "playwright";

const base = "http://127.0.0.1:4173";
const results = [];
let failed = false;

function record(scope, name, ok, detail = "") {
  results.push({ scope, name, ok, detail });
  console.log(JSON.stringify({ scope, name, ok, detail }));
  if (!ok) failed = true;
}

async function limited(label, promise, ms = 5000) {
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

async function inspectPage(browser, scope, url, contextOptions = {}) {
  console.log("START " + scope + " " + url);
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  page.setDefaultNavigationTimeout(10000);

  const consoleErrors = [];
  const pageErrors = [];
  const cspViolations = [];
  const navigations = [];

  page.on("console", msg => {
    if (msg.type() === "error") consoleErrors.push(msg.text());
  });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));
  page.on("framenavigated", frame => {
    if (frame === page.mainFrame()) {
      navigations.push(frame.url());
      console.log("NAV " + scope + " " + frame.url());
    }
  });

  await page.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener("securitypolicyviolation", e => {
      window.__cspViolations.push({
        directive: e.effectiveDirective,
        blockedURI: e.blockedURI,
        sourceFile: e.sourceFile,
        lineNumber: e.lineNumber
      });
    });
  });

  let response = null;
  try {
    response = await limited(scope + " goto", page.goto(url, { waitUntil: "commit", timeout: 10000 }), 12000);
    record(scope, "HTTP/Navigation", !!response && response.ok(), response ? String(response.status()) : "no response");
  } catch (e) {
    record(scope, "HTTP/Navigation", false, String(e.message || e));
  }

  try {
    await limited(scope + " body", page.waitForSelector("body", { state: "attached", timeout: 5000 }), 6000);
    record(scope, "body attached", true);
  } catch (e) {
    record(scope, "body attached", false, String(e.message || e));
  }

  await new Promise(r => setTimeout(r, 1200));

  try {
    const list = await limited(scope + " CSP read", page.evaluate(() => window.__cspViolations || []), 5000);
    cspViolations.push(...list);
  } catch (e) {
    record(scope, "CSP read", false, String(e.message || e));
  }

  return { context, page, consoleErrors, pageErrors, cspViolations, navigations };
}

async function safeClose(context, scope) {
  try { await limited(scope + " context.close", context.close(), 3000); } catch (e) {
    console.log("CLOSE_TIMEOUT " + scope + " " + String(e.message || e));
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  {
    const { context, page, consoleErrors, pageErrors, cspViolations, navigations } =
      await inspectPage(browser, "main-desktop", base + "/index.html");

    try {
      const title = await limited("desktop title", page.title(), 5000);
      record("main-desktop", "title", /Johanna/.test(title), title);
    } catch (e) {
      record("main-desktop", "title", false, String(e.message || e));
    }

    let tabCount = 0;
    try {
      tabCount = await limited("desktop tab count", page.locator(".tab").count(), 5000);
      record("main-desktop", "tabs present", tabCount >= 3, String(tabCount));
    } catch (e) {
      record("main-desktop", "tabs present", false, String(e.message || e));
    }

    let tabClicksOk = tabCount > 0;
    for (let i = 0; i < Math.min(tabCount, 6); i++) {
      try {
        await limited("tab click " + i, page.locator(".tab").nth(i).click({ timeout: 3000 }), 4500);
        await new Promise(r => setTimeout(r, 100));
      } catch (e) {
        tabClicksOk = false;
        record("main-desktop", "tab " + i + " clickable", false, String(e.message || e));
        break;
      }
    }
    if (tabCount > 0 && tabClicksOk) record("main-desktop", "first tabs clickable", true, "tested " + Math.min(tabCount, 6));

    try {
      const settingsButton = page.locator("#settingsButton, .gearbtn").first();
      const n = await limited("settings count", settingsButton.count(), 5000);
      if (n) {
        await limited("settings click", settingsButton.click({ timeout: 3000 }), 4500);
        const visible = await limited("settings visible", page.locator(".settings-overlay:not(.hidden)").count(), 5000);
        record("main-desktop", "settings opens", visible > 0, String(visible));
      } else {
        record("main-desktop", "settings button found", false);
      }
    } catch (e) {
      record("main-desktop", "settings opens", false, String(e.message || e));
    }

    record("main-desktop", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    record("main-desktop", "no CSP violations", cspViolations.length === 0, JSON.stringify(cspViolations));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("main-desktop", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    record("main-desktop", "navigation stable", navigations.length <= 3, JSON.stringify(navigations));
    await safeClose(context, "main-desktop");
  }

  {
    const mobile = devices["iPhone 13"];
    const { context, page, consoleErrors, pageErrors, cspViolations, navigations } =
      await inspectPage(browser, "main-mobile", base + "/index.html", mobile);

    try {
      const count = await limited("mobile tabs", page.locator(".tab").count(), 5000);
      record("main-mobile", "tabs present", count >= 3, String(count));
    } catch (e) {
      record("main-mobile", "tabs present", false, String(e.message || e));
    }

    record("main-mobile", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    record("main-mobile", "no CSP violations", cspViolations.length === 0, JSON.stringify(cspViolations));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("main-mobile", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    record("main-mobile", "navigation stable", navigations.length <= 3, JSON.stringify(navigations));
    await safeClose(context, "main-mobile");
  }

  {
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(5000);
    page.setDefaultNavigationTimeout(10000);
    const consoleErrors = [];
    const pageErrors = [];
    const cspViolations = [];
    page.on("console", m => { if (m.type() === "error") consoleErrors.push(m.text()); });
    page.on("pageerror", e => pageErrors.push(String(e.message || e)));
    await page.addInitScript(() => {
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
      window.__cspViolations = [];
      document.addEventListener("securitypolicyviolation", e => {
        window.__cspViolations.push({ directive:e.effectiveDirective, blockedURI:e.blockedURI });
      });
    });

    try {
      const resp = await limited("setup goto", page.goto(base + "/setup.html", { waitUntil:"commit", timeout:10000 }), 12000);
      record("setup", "HTTP/Navigation", !!resp && resp.ok(), resp ? String(resp.status()) : "no response");
    } catch (e) {
      record("setup", "HTTP/Navigation", false, String(e.message || e));
    }

    await new Promise(r => setTimeout(r, 1200));

    try {
      const visible = await limited("setup generator", page.locator("#generatorBox:not(.hidden)").count(), 5000);
      record("setup", "generator visible", visible === 1, String(visible));
    } catch (e) {
      record("setup", "generator visible", false, String(e.message || e));
    }

    try {
      const qr = await limited("setup QRCode", page.evaluate(() => typeof QRCode !== "undefined"), 5000);
      record("setup", "QR library loaded", !!qr);
    } catch (e) {
      record("setup", "QR library loaded", false, String(e.message || e));
    }

    try {
      const csp = await limited("setup CSP", page.evaluate(() => window.__cspViolations || []), 5000);
      cspViolations.push(...csp);
    } catch (e) {
      record("setup", "CSP read", false, String(e.message || e));
    }

    record("setup", "no CSP violations", cspViolations.length === 0, JSON.stringify(cspViolations));
    record("setup", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("setup", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    await safeClose(context, "setup");
  }

  try { await limited("browser.close", browser.close(), 3000); } catch {}

  console.log("FINAL_RESULTS " + JSON.stringify({ ok: !failed, results }));
  if (failed) process.exit(1);
})().catch(err => {
  console.error("FATAL", err);
  process.exit(1);
});
