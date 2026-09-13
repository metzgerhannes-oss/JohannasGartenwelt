from __future__ import annotations

import json
import re
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
TMP = Path("_core_runtime_index.html")


def make_copy() -> None:
    html = Path("index.html").read_text(encoding="utf-8")
    html = re.sub(r'<link[^>]+href="https://cdn\.jsdelivr\.net/npm/leaflet(?:-draw)?@[^\"]+\.css"[^>]*>', '<!-- map css omitted in core smoke -->', html)
    html = re.sub(r'<script[^>]+src="https://cdn\.jsdelivr\.net/npm/leaflet(?:-draw)?@[^\"]+\.js"[^>]*></script>', '<!-- map js omitted in core smoke -->', html)
    TMP.write_text(html, encoding="utf-8")


def serve():
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), Quiet)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_port}/"


def chrome():
    o = webdriver.ChromeOptions()
    o.page_load_strategy = "none"
    for arg in ("--headless=new", "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu", "--lang=de-DE"):
        o.add_argument(arg)
    o.set_capability("goog:loggingPrefs", {"browser": "ALL"})
    d = webdriver.Chrome(options=o)
    d.set_window_size(390, 844)
    return d


def logs(d):
    try:
        return d.get_log("browser")
    except Exception:
        return []


def diag(d):
    try:
        flags = d.execute_script("return {ready:document.readyState,core:!!window.JGWCore,ux:!!window.JGWUX,lib:!!window.JGWLibraryV4,photo:!!window.JGWPhotoStorage};")
    except Exception as e:
        flags = {"error": repr(e)}
    severe = [x.get("message", "") for x in logs(d) if x.get("level") == "SEVERE"]
    return {"flags": flags, "severe": severe[:10]}


def click(d, css):
    w = WebDriverWait(d, 10)
    n = w.until(EC.element_to_be_clickable((By.CSS_SELECTOR, css)))
    d.execute_script("arguments[0].scrollIntoView({block:'center'});", n)
    d.execute_script("arguments[0].click();", n)
    return n


def main():
    report = {"ok": False, "checks": [], "diagnostics": {}}
    make_copy()
    server, base = serve()
    d = chrome()
    start = time.perf_counter()
    try:
        d.get(base + TMP.name + "?smoke=" + str(int(time.time())))
        w = WebDriverWait(d, 20)
        w.until(EC.presence_of_element_located((By.CSS_SELECTOR, "body")))
        for expr, name in [
            ("window.JGWCore", "JGWCore"),
            ("window.JGWUX", "JGWUX"),
            ("window.JGWLibraryV4", "JGWLibraryV4"),
            ("window.JGWPhotoStorage", "JGWPhotoStorage"),
        ]:
            w.until(lambda x, e=expr: x.execute_script(f"return !!({e})"))
            report["checks"].append(name)

        labels = [x.text.strip() for x in d.find_elements(By.CSS_SELECTOR, ".tabs .tab")]
        assert labels == ["Heute", "Mein Garten", "Aufgaben", "Bibliothek", "Mehr"], labels
        report["checks"].append("navigation")

        click(d, ".jgw-fab")
        click(d, '.jgw-add-option[data-kind="plants"]')
        w.until(EC.visibility_of_element_located((By.ID, "plantEditor")))
        inp = d.find_element(By.ID, "plantPhoto")
        assert inp.get_attribute("capture") in (None, "")
        assert d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-pick").text == "Foto auswählen"
        assert d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-camera").text == "Kamera öffnen"
        report["checks"].append("photo-picker")

        click(d, '.tabs .tab[data-view="more"]')
        click(d, "#moreSettingsBtn")
        w.until(EC.visibility_of_element_located((By.ID, "settingsOverlay")))
        assert len(d.find_elements(By.CSS_SELECTOR, ".jgw-settings-group")) == 4
        report["checks"].append("settings-groups")

        severe = []
        for row in logs(d):
            if row.get("level") != "SEVERE":
                continue
            m = row.get("message", "")
            low = m.lower()
            if "leaflet" in low or "l is not defined" in low or "favicon" in low:
                continue
            severe.append(m)
        assert not severe, " | ".join(severe[:5])
        report["checks"].append("console")
        report["bootstrap_ms"] = round((time.perf_counter() - start) * 1000)
        report["ok"] = True
        d.save_screenshot(str(OUT / "core_smoke.png"))
        print("CORE SMOKE PASS", report["bootstrap_ms"], "ms", ", ".join(report["checks"]))
    except Exception as e:
        report["error"] = repr(e)
        report["diagnostics"] = diag(d)
        print("CORE SMOKE FAIL", json.dumps(report, ensure_ascii=False))
        raise
    finally:
        (OUT / "core_smoke.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        d.quit()
        server.shutdown()
        TMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
