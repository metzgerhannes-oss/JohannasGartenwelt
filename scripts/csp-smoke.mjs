import { chromium, devices } from "playwright";
import fs from "node:fs";

const base = "http://127.0.0.1:4173";
const results = [];
let failed = false;

function record(scope, name, ok, detail = "") {
  results.push({ scope, name, ok, detail });
  if (!ok) failed = true;
}

async function inspectPage(browser, scope, url, contextOptions = {}) {
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  const consoleErrors = [];
  const pageErrors = [];
  const cspViolations = [];

  page.on("console", msg => {
    if (msg.type() === "error") consoleErrors.push(msg.text());
  });
  page.on("pageerror", err => pageErrors.push(String(err && err.message || err)));
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

  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  record(scope, "HTTP/Navigation", !!response && response.ok(), response ? String(response.status()) : "no response");

  await page.waitForTimeout(2500);
  try {
    const list = await page.evaluate(() => window.__cspViolations || []);
    cspViolations.push(...list);
  } catch {}

  return { context, page, consoleErrors, pageErrors, cspViolations };
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // Desktop main app
  {
    const { context, page, consoleErrors, pageErrors, cspViolations } =
      await inspectPage(browser, "main-desktop", base + "/index.html");

    record("main-desktop", "title", /Johanna/.test(await page.title()), await page.title());
    record("main-desktop", "body rendered", await page.locator("body").count() === 1);
    record("main-desktop", "tabs present", await page.locator(".tab").count() >= 3, String(await page.locator(".tab").count()));

    const tabs = page.locator(".tab");
    const tabCount = await tabs.count();
    let tabClicksOk = true;
    for (let i = 0; i < Math.min(tabCount, 6); i++) {
      try {
        await tabs.nth(i).click({ timeout: 3000 });
        await page.waitForTimeout(120);
      } catch (e) {
        tabClicksOk = false;
        break;
      }
    }
    record("main-desktop", "first tabs clickable", tabClicksOk, "tested " + Math.min(tabCount, 6));

    const settingsButton = page.locator("#settingsButton, .gearbtn").first();
    if (await settingsButton.count()) {
      try {
        await settingsButton.click();
        await page.waitForTimeout(150);
        const visible = await page.locator(".settings-overlay:not(.hidden)").count() > 0;
        record("main-desktop", "settings opens", visible);
      } catch (e) {
        record("main-desktop", "settings opens", false, String(e.message || e));
      }
    } else {
      record("main-desktop", "settings button found", false);
    }

    record("main-desktop", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    record("main-desktop", "no CSP violations", cspViolations.length === 0, JSON.stringify(cspViolations));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("main-desktop", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    await context.close();
  }

  // Mobile/iPhone-ish main app
  {
    const mobile = devices["iPhone 13"];
    const { context, page, consoleErrors, pageErrors, cspViolations } =
      await inspectPage(browser, "main-mobile", base + "/index.html", mobile);
    record("main-mobile", "renders", await page.locator("body").count() === 1);
    record("main-mobile", "tabs present", await page.locator(".tab").count() >= 3, String(await page.locator(".tab").count()));
    record("main-mobile", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    record("main-mobile", "no CSP violations", cspViolations.length === 0, JSON.stringify(cspViolations));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("main-mobile", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    await context.close();
  }

  // Setup page, seeded generator mode
  {
    const context = await browser.newContext();
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
    const consoleErrors = [];
    const pageErrors = [];
    page.on("console", m => { if (m.type() === "error") consoleErrors.push(m.text()); });
    page.on("pageerror", e => pageErrors.push(String(e.message || e)));
    await page.addInitScript(() => {
      window.__cspViolations = [];
      document.addEventListener("securitypolicyviolation", e => {
        window.__cspViolations.push({ directive:e.effectiveDirective, blockedURI:e.blockedURI });
      });
    });
    const resp = await page.goto(base + "/setup.html", { waitUntil:"domcontentloaded", timeout:30000 });
    await page.waitForTimeout(2500);
    record("setup", "HTTP/Navigation", !!resp && resp.ok(), resp ? String(resp.status()) : "no response");
    record("setup", "generator visible", await page.locator("#generatorBox:not(.hidden)").count() === 1);
    record("setup", "QR library loaded", await page.evaluate(() => typeof QRCode !== "undefined"));
    const csp = await page.evaluate(() => window.__cspViolations || []);
    record("setup", "no CSP violations", csp.length === 0, JSON.stringify(csp));
    record("setup", "no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    const relevantConsole = consoleErrors.filter(x => /Content Security Policy|Refused to|Uncaught|SyntaxError|ReferenceError/i.test(x));
    record("setup", "no relevant console errors", relevantConsole.length === 0, relevantConsole.join(" | "));
    await context.close();
  }

  await browser.close();

  console.log(JSON.stringify(results, null, 2));
  if (failed) process.exit(1);
})().catch(err => {
  console.error(err);
  process.exit(1);
});
