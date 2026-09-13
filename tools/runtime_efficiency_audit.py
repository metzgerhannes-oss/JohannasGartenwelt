from __future__ import annotations

import json
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

OUT = Path("audit_runtime")
OUT.mkdir(exist_ok=True)
REPORT: list[dict[str, str]] = []


def record(name: str, status: str = "PASS", detail: str = "") -> None:
    REPORT.append({"name": name, "status": status, "detail": detail})
    print(f"[{status}] {name}: {detail}")


def server():
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Quiet)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, f"http://127.0.0.1:{httpd.server_port}/"


def browser():
    opts = webdriver.ChromeOptions()
    opts.page_load_strategy = "none"
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--lang=de-DE")
    opts.set_capability("goog:loggingPrefs", {"browser": "ALL"})
    d = webdriver.Chrome(options=opts)
    d.set_window_size(390, 844)
    d.set_page_load_timeout(25)
    d.execute_cdp_cmd("Network.enable", {})
    # Map assets must not be able to block the basic app shell. The map itself is
    # covered separately by source checks and the production smoke test.
    d.execute_cdp_cmd("Network.setBlockedURLs", {"urls": ["*cdn.jsdelivr.net/npm/leaflet*"]})
    return d


def wait(d, seconds=15):
    return WebDriverWait(d, seconds)


def visible(d, css, seconds=15):
    return wait(d, seconds).until(EC.visibility_of_element_located((By.CSS_SELECTOR, css)))


def click(d, css, seconds=15):
    node = wait(d, seconds).until(EC.element_to_be_clickable((By.CSS_SELECTOR, css)))
    d.execute_script("arguments[0].scrollIntoView({block:'center'});", node)
    try:
        node.click()
    except Exception:
        d.execute_script("arguments[0].click();", node)
    return node


def severe_errors(d):
    result = []
    for row in d.get_log("browser"):
        if row.get("level") != "SEVERE":
            continue
        msg = row.get("message", "")
        low = msg.lower()
        if any(x in low for x in ["leaflet", "favicon", "net::err_blocked_by_client"]):
            continue
        result.append(msg)
    return result


def static_efficiency_checks():
    idx = Path("index.html").read_text(encoding="utf-8")
    shell = Path("jgw-ux-shell.js").read_text(encoding="utf-8")
    photos = Path("jgw-photo-storage-v2.js").read_text(encoding="utf-8")

    blocking = sum(1 for s in [
        '<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"></script>',
        '<script src="https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.js"></script>',
    ] if s in idx)
    record("Blocking map dependencies", "WARN" if blocking else "PASS",
           f"{blocking} parser-blockierende Karten-Skripte" if blocking else "keine")

    legacy_photo = 'script id="jgw-photo-storage-direct"' in idx and 'var specs={' in idx[idx.find("jgw-library-nav.js"):]
    record("Fotospeicher-Codepfade", "WARN" if legacy_photo else "PASS",
           "Legacy-Fallback weiterhin im HTML; V2 verhindert Doppelarbeit" if legacy_photo else "nur ein aktiver Pfad")

    assert "API_TIMEOUT=12000" in photos
    assert "i+=4" in photos
    assert 'configured(cfg())?prepare(type,f):null' in photos
    assert "stopImmediatePropagation" in photos
    record("Fotospeicher-Effizienz", detail="Timeout · Batch-Signing · keine Doppelkompression ohne Cloud · Doppel-Click abgefangen")

    observers = shell.count("new MutationObserver") + idx.count("new MutationObserver")
    record("DOM-Beobachter", "WARN" if observers >= 5 else "PASS", f"{observers} MutationObserver im aktiven Code")


def run_runtime():
    httpd, base = server()
    d = browser()
    started = time.perf_counter()
    try:
        d.get(base + "?runtime-audit=" + str(int(time.time())))
        visible(d, "body", 10)
        wait(d, 20).until(lambda x: x.execute_script("return !!window.JGWCore && !!window.JGWUX && !!window.JGWLibraryV4"))
        boot_ms = round((time.perf_counter() - started) * 1000)
        record("App-Bootstrap ohne Karten-CDN", detail=f"{boot_ms} ms")

        labels = [x.text.strip() for x in d.find_elements(By.CSS_SELECTOR, ".tabs .tab")]
        assert labels == ["Heute", "Mein Garten", "Aufgaben", "Bibliothek", "Mehr"], labels
        assert visible(d, ".jgw-fab").is_displayed()
        record("Navigation & FAB", detail=" · ".join(labels))

        click(d, ".jgw-fab")
        click(d, '.jgw-add-option[data-kind="plants"]')
        visible(d, "#plantEditor")
        inp = d.find_element(By.ID, "plantPhoto")
        assert inp.get_attribute("capture") in (None, "")
        assert d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-pick").text == "Foto auswählen"
        assert d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-camera").text == "Kamera öffnen"
        record("Fotoauswahl", detail="Dateiauswahl ohne capture; Kamera separat")

        # The old inline onclick must not execute in addition to the V2 handler.
        d.execute_script("window.__directOptimizeCalls=0; if(window.JGWPhotoStorageDirect){window.JGWPhotoStorageDirect.optimize=function(){window.__directOptimizeCalls++}}")
        click(d, '.tabs .tab[data-view="more"]')
        click(d, "#moreSettingsBtn")
        visible(d, "#settingsOverlay")
        btn = d.find_element(By.ID, "optimizePhotoStorageBtn")
        d.execute_script("arguments[0].click();", btn)
        time.sleep(.2)
        direct_calls = d.execute_script("return window.__directOptimizeCalls")
        assert direct_calls == 0, direct_calls
        record("Fotospeicher-Handler", detail="ein Klick → nur V2-Pfad")

        groups = d.find_elements(By.CSS_SELECTOR, ".jgw-settings-group")
        assert len(groups) == 4, len(groups)
        record("Einstellungen", detail="4 Gruppen")

        errors = severe_errors(d)
        assert not errors, " | ".join(errors[:5])
        record("JavaScript-Laufzeit", detail="keine SEVERE-Fehler außerhalb bewusst blockierter Kartenassets")
        d.save_screenshot(str(OUT / "runtime_mobile.png"))
    finally:
        d.quit()
        httpd.shutdown()


def main():
    try:
        static_efficiency_checks()
        run_runtime()
    except Exception as exc:
        record("Audit-Ausführung", "FAIL", repr(exc))
    finally:
        (OUT / "report.json").write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding="utf-8")
    fails = [r for r in REPORT if r["status"] == "FAIL"]
    warns = [r for r in REPORT if r["status"] == "WARN"]
    print(f"RUNTIME AUDIT: {len(REPORT)-len(fails)-len(warns)} PASS, {len(warns)} WARN, {len(fails)} FAIL")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
