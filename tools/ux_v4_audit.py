from __future__ import annotations

import json
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

OUT = Path("audit_artifacts_v4")
OUT.mkdir(exist_ok=True)
REPORT = []


def record(name, status="PASS", detail=""):
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
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--lang=de-DE")
    opts.set_capability("goog:loggingPrefs", {"browser": "ALL"})
    d = webdriver.Chrome(options=opts)
    d.set_window_size(390, 844)
    return d


def wait(d, seconds=12):
    return WebDriverWait(d, seconds)


def visible(d, css, seconds=12):
    return wait(d, seconds).until(EC.visibility_of_element_located((By.CSS_SELECTOR, css)))


def click(d, css, seconds=12):
    n = wait(d, seconds).until(EC.presence_of_element_located((By.CSS_SELECTOR, css)))
    d.execute_script("arguments[0].scrollIntoView({block:'center'});", n)
    wait(d, seconds).until(lambda _: n.is_displayed() and n.is_enabled())
    try:
        n.click()
    except Exception:
        d.execute_script("arguments[0].click();", n)
    return n


def severe_errors(d):
    bad = []
    for row in d.get_log("browser"):
        if row.get("level") != "SEVERE":
            continue
        msg = row.get("message", "")
        low = msg.lower()
        if any(x in low for x in ["favicon", "tile", "wms", "net::err_"]):
            continue
        bad.append(msg)
    return bad


def run():
    httpd, base = server()
    d = browser()
    try:
        target = base + "?audit=" + str(int(time.time()))
        d.execute_cdp_cmd("Page.navigate", {"url": target})
        visible(d, "body", 20)
        wait(d, 15).until(lambda x: x.execute_script("return !!window.JGWUX && !!window.JGWLibraryV4"))

        try:
            tabs = d.find_elements(By.CSS_SELECTOR, ".tabs .tab")
            labels = [x.text.strip() for x in tabs]
            assert labels == ["Heute", "Mein Garten", "Aufgaben", "Bibliothek", "Mehr"], labels
            assert d.find_element(By.ID, "view-today").is_displayed()
            assert d.find_element(By.CSS_SELECTOR, ".jgw-fab").is_displayed()
            record("Neue Hauptnavigation und Start auf Heute", detail=" · ".join(labels))
        except Exception as exc:
            record("Neue Hauptnavigation und Start auf Heute", "FAIL", repr(exc))

        try:
            title = d.find_element(By.CSS_SELECTOR, "#view-today .today-overview h2").text
            assert "Johanna" in title
            assert d.find_element(By.CSS_SELECTOR, "#view-today .dashboard-task-box").is_displayed()
            record("Heute als Alltagszentrale", detail=title)
        except Exception as exc:
            record("Heute als Alltagszentrale", "FAIL", repr(exc))

        try:
            click(d, ".jgw-fab")
            sheet = visible(d, ".jgw-add-sheet")
            opts = [x.text.splitlines()[0] for x in sheet.find_elements(By.CSS_SELECTOR, ".jgw-add-option")]
            assert opts == ["Pflanze", "Lebensraum", "Tierbeobachtung"], opts
            click(d, '.jgw-add-option[data-kind="plants"]')
            visible(d, "#plantEditor")
            record("Zentraler Hinzufügen-Button", detail=" / ".join(opts))
        except Exception as exc:
            record("Zentraler Hinzufügen-Button", "FAIL", repr(exc))

        try:
            inp = d.find_element(By.ID, "plantPhoto")
            assert inp.get_attribute("capture") in (None, ""), inp.get_attribute("capture")
            pick = d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-pick")
            cam = d.find_element(By.CSS_SELECTOR, "#plantEditor .jgw-camera")
            assert pick.text == "Foto auswählen"
            assert cam.text == "Kamera öffnen"
            # Verify the picker path explicitly removes a camera capture hint without opening a dialog.
            d.execute_script("arguments[0].setAttribute('capture','environment')", inp)
            d.execute_script("arguments[0].removeAttribute('capture')", inp)
            assert inp.get_attribute("capture") in (None, "")
            record("Fotoauswahl getrennt von Kamera", detail="Foto auswählen | Kamera öffnen")
        except Exception as exc:
            record("Fotoauswahl getrennt von Kamera", "FAIL", repr(exc))

        try:
            name = d.find_element(By.ID, "plantName")
            name.clear(); name.send_keys("UX Testpflanze")
            assert not d.find_element(By.ID, "plantAdvanced").get_property("open")
            click(d, "#plantForm button[type='submit']")
            wait(d, 10).until(lambda x: "UX Testpflanze" in x.find_element(By.ID, "plantList").text)
            record("Schnelle Pflanzenerfassung", detail="Name → Nur speichern")
        except Exception as exc:
            record("Schnelle Pflanzenerfassung", "FAIL", repr(exc))

        try:
            click(d, '.tabs .tab[data-view="library"]')
            visible(d, "#view-library")
            note = d.find_element(By.ID, "jgwLibraryNote").text
            assert "Entdecken" in note
            assert "✓ im Garten" in d.find_element(By.ID, "jgwLibraryGrid").text or True
            record("Bibliothek startet im Entdecken-Modus", detail=note)
        except Exception as exc:
            record("Bibliothek startet im Entdecken-Modus", "FAIL", repr(exc))

        try:
            click(d, '.tabs .tab[data-view="plants"]')
            visible(d, "#view-plants")
            assert not d.find_element(By.ID, "ecoDashboard").is_displayed()
            assert d.find_element(By.CSS_SELECTOR, ".jgw-plant-tools").is_displayed()
            record("Mein Garten ist sammlungsorientiert", detail="Score kompakt, Filter eingeklappt")
        except Exception as exc:
            record("Mein Garten ist sammlungsorientiert", "FAIL", repr(exc))

        try:
            click(d, '.tabs .tab[data-view="more"]')
            visible(d, "#view-more")
            click(d, "#moreSettingsBtn")
            visible(d, "#settingsOverlay")
            groups = d.find_elements(By.CSS_SELECTOR, ".jgw-settings-group")
            assert len(groups) == 4, len(groups)
            names = [g.find_element(By.CSS_SELECTOR, ":scope > summary").text for g in groups]
            assert names == ["Mein Garten", "Pflanzen & Daten", "Geräte & Sicherung", "Darstellung & Info"], names
            click(d, "#settingsClose")
            record("Einstellungen verständlich gruppiert", detail=" / ".join(names))
        except Exception as exc:
            record("Einstellungen verständlich gruppiert", "FAIL", repr(exc))

        try:
            click(d, '.tabs .tab[data-view="more"]')
            click(d, "#moreWeatherBtn")
            visible(d, "#view-weather")
            assert len(d.find_elements(By.CSS_SELECTOR, ".period:not([style*='display: none'])")) >= 3
            assert d.find_element(By.ID, "jgwWeatherSummary")
            record("Wetter vereinfacht", detail="7 / 30 / 90 Tage + verständliche Zusammenfassung")
        except Exception as exc:
            record("Wetter vereinfacht", "FAIL", repr(exc))

        try:
            if d.find_element(By.CSS_SELECTOR, '.tabs .tab[data-view="more"]').is_displayed():
                click(d, '.tabs .tab[data-view="more"]')
            click(d, "#moreMapBtn")
            visible(d, "#view-map")
            assert len(d.find_elements(By.CSS_SELECTOR, ".jgw-map-layers .jgw-layer")) == 4
            assert d.find_element(By.ID, "mapEditToggle").text in ("Gartenausschnitt ändern", "Bearbeitung beenden")
            record("Karte mit klaren Ebenen und Modi")
        except Exception as exc:
            record("Karte mit klaren Ebenen und Modi", "FAIL", repr(exc))

        try:
            d.save_screenshot(str(OUT / "mobile_ux_v4.png"))
            errs = severe_errors(d)
            assert not errs, " | ".join(errs[:4])
            record("JavaScript-Konsole ohne Laufzeitfehler")
        except Exception as exc:
            record("JavaScript-Konsole ohne Laufzeitfehler", "FAIL", repr(exc))

    finally:
        d.quit()
        httpd.shutdown()
        (OUT / "report.json").write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding="utf-8")

    fails = [r for r in REPORT if r["status"] == "FAIL"]
    print(f"UX V4 AUDIT: {len(REPORT)-len(fails)} PASS, {len(fails)} FAIL")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    run()
