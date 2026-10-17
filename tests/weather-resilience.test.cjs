"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "jgw-app.js"), "utf8");

function extract(name) {
  const lines = source.split("\n");
  const start = lines.findIndex(line => line.startsWith("async function " + name + "(") || line.startsWith("function " + name + "("));
  assert.notEqual(start, -1, name + " must exist");
  let end = start + 1;
  while (end < lines.length && !/^(?:async )?function [A-Za-z_$]/.test(lines[end]) && !/^var [A-Za-z_$]/.test(lines[end])) end++;
  return lines.slice(start, end).join("\n");
}
function context(fns, overrides = {}) {
  const ctx = vm.createContext({ Promise, setTimeout: fn => fn(), ...overrides });
  for (const name of fns) vm.runInContext(extract(name), ctx);
  return ctx;
}
function weatherEnv(options = {}) {
  const elements = { locationStatus: { textContent: "" } };
  const notices = [], errors = [], shown = [];
  let renders = 0, saves = 0, lookups = 0;
  const state = {
    plz: options.plz ?? "72116",
    gardenCenter: options.center ?? { lat: 48.4, lon: 9.1 },
    loc: options.loc ?? { name: "Mössingen", plz: "72116", lat: 48.4, lon: 9.1 },
    weather: options.weather ?? null,
    mapReady: false,
  };
  const ctx = context(["refreshWeather"], {
    state, navigator: { onLine: true },
    el: id => elements[id] || (elements[id] = { textContent: "" }),
    getWeather: options.getWeather || (async () => ({ daily: { time: ["2026-10-17"] }, jgwFetchedAt: new Date().toISOString() })),
    lookupPLZ: async () => { lookups++; if (options.lookupError) throw options.lookupError; return { name: "Mössingen", plz: "72116", lat: 48.4, lon: 9.1 }; },
    save: () => { saves++; }, show: (...a) => shown.push(a),
    notice: message => notices.push(message),
    globalError: message => errors.push(message),
    renderWeatherViews: () => { renders++; },
    renderYesterdayRain: () => {},
    openSettings: () => {},
  });
  return { ctx, state, elements, notices, errors, shown, get renders() { return renders; }, get saves() { return saves; }, get lookups() { return lookups; } };
}

test("503 is retried once and then recovers", async () => {
  let attempts = 0, delays = 0;
  const ctx = context(["requestJSONResilient"], {
    setTimeout: callback => { delays++; callback(); },
    requestJSON: async () => { if (++attempts === 1) throw new Error("HTTP 503"); return { ok: true }; },
  });
  assert.equal((await ctx.requestJSONResilient("https://example.test", 1000)).ok, true);
  assert.equal(attempts, 2);
  assert.equal(delays, 1);
});
test("permanent HTTP 400 is not retried", async () => {
  let attempts = 0;
  const ctx = context(["requestJSONResilient"], {
    requestJSON: async () => { attempts++; throw new Error("HTTP 400"); },
  });
  await assert.rejects(ctx.requestJSONResilient("https://example.test", 1000), /HTTP 400/);
  assert.equal(attempts, 1);
});
test("cached postal coordinates avoid repeated PLZ requests", async () => {
  const t = weatherEnv({ center: null });
  await t.ctx.refreshWeather(false);
  assert.equal(t.lookups, 0);
  assert.equal(t.saves, 1);
  assert.equal(t.errors.length, 0);
});
test("saved garden location works even when postal API returns 503", async () => {
  const t = weatherEnv({ loc: null, lookupError: new Error("HTTP 503") });
  await t.ctx.refreshWeather(false);
  assert.equal(t.lookups, 1);
  assert.equal(t.saves, 1);
  assert.equal(t.errors.length, 0);
});
test("temporary failure does not overwrite or revalidate stale weather", async () => {
  const stale = { jgwFetchedAt: "2026-10-08T16:31:00Z", daily: { time: ["2026-10-08"] } };
  const t = weatherEnv({ weather: stale, getWeather: async () => { throw new Error("Wetterprognose (Open-Meteo): HTTP 503"); } });
  await t.ctx.refreshWeather(true);
  assert.equal(t.state.weather, stale);
  assert.equal(t.saves, 0);
  assert.equal(t.errors.length, 0);
  assert.ok(t.notices.some(message => message.includes("letzte Wetterstand")));
  assert.ok(t.shown.some(([id, visible]) => id === "globalError" && visible === false));
});
test("new users see a server error rather than misleading internet advice", async () => {
  const t = weatherEnv({ getWeather: async () => { throw new Error("Wetterprognose (Open-Meteo): HTTP 503"); } });
  await t.ctx.refreshWeather(true);
  assert.equal(t.errors.length, 1);
  assert.match(t.errors[0], /HTTP 503/);
  assert.doesNotMatch(t.errors[0], /Internetverbindung prüfen/);
});
