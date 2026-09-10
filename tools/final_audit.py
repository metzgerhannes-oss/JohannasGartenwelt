from __future__ import annotations

import json
import os
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait

BASE = "https://metzgerhannes-oss.github.io/JohannasGartenwelt/"
OUT = Path("audit_artifacts")
OUT.mkdir(exist_ok=True)
DOWNLOADS = OUT / "downloads"
DOWNLOADS.mkdir(exist_ok=True)
REPORT = []
PROBES = {}


def record(name, status="PASS", detail=""):
    REPORT.append({"name": name, "status": status, "detail": detail})
    print(f"[{status}] {name}: {detail}")


def probe(name, url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Johannas-Gartenwelt-Audit/1.0"})
        with urllib.request.urlopen(req, timeout=12) as r:
            body = r.read(400)
            ok = 200 <= r.status < 300 and bool(body)
            PROBES[name] = ok
            record(f"Externer Dienst: {name}", "PASS" if ok else "WARN", f"HTTP {r.status}")
    except Exception as exc:
        PROBES[name] = False
        record(f"Externer Dienst: {name}", "WARN", repr(exc))


def chrome(mobile=True, standalone=False):
    opts = webdriver.ChromeOptions()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--lang=de-DE")
    opts.set_capability("goog:loggingPrefs", {"browser": "ALL"})
    opts.add_experimental_option(
        "prefs",
        {
            "download.default_directory": str(DOWNLOADS.resolve()),
            "download.prompt_for_download": False,
            "download.directory_upgrade": True,
            "safebrowsing.enabled": True,
        },
    )
    drv = webdriver.Chrome(options=opts)
    drv.set_window_size(390 if mobile else 1280, 844 if mobile else 900)
    if standalone:
        drv.execute_cdp_cmd(
            "Page.addScriptToEvaluateOnNewDocument",
            {"source": "Object.defineProperty(navigator,'standalone',{configurable:true,get:function(){return true;}});"},
        )
    return drv


def wait(drv, seconds=12):
    return WebDriverWait(drv, seconds)


def visible(drv, css, seconds=12):
    return wait(drv, seconds).until(EC.visibility_of_element_located((By.CSS_SELECTOR, css)))


def click(drv, css, seconds=12):
    node = wait(drv, seconds).until(EC.presence_of_element_located((By.CSS_SELECTOR, css)))
    drv.execute_script("arguments[0].scrollIntoView({block:'center'});", node)
    wait(drv, seconds).until(lambda d: node.is_displayed() and node.is_enabled())
    try:
        node.click()
    except Exception:
        drv.execute_script("arguments[0].click();", node)
    return node


def text(drv, css):
    return drv.find_element(By.CSS_SELECTOR, css).text


def screenshot(drv, filename):
    drv.save_screenshot(str(OUT / filename))


def local_json(drv, key):
    return drv.execute_script("return JSON.parse(localStorage.getItem(arguments[0]) || 'null');", key)


def wait_download(suffix, before, timeout=10):
    end = time.time() + timeout
    while time.time() < end:
        current = {p for p in DOWNLOADS.iterdir() if p.is_file() and p.suffix.lower() == suffix}
        new = current - before
        if new:
            return sorted(new, key=lambda p: p.stat().st_mtime)[-1]
        time.sleep(0.25)
    raise TimeoutException(f"download {suffix} not found")


def error_text(drv):
    parts = []
    for css in ["#globalError", "#locationStatus"]:
        try:
            node = drv.find_element(By.CSS_SELECTOR, css)
            if node.is_displayed() and node.text.strip():
                parts.append(node.text.strip())
        except Exception:
            pass
    return " | ".join(parts)


def browser_errors(drv):
    result = []
    try:
        logs = drv.get_log("browser")
    except Exception:
        return result
    for row in logs:
        if row.get("level") != "SEVERE":
            continue
        msg = row.get("message", "")
        low = msg.lower()
        if any(x in low for x in ["favicon", "tile", "wms_lgl", "net::err_blocked_by_client"]):
            continue
        result.append(msg)
    return result


def run_mobile_audit():
    drv = chrome(mobile=True)
    token_link = None
    plant_created = False
    calendar_ready = False
    try:
        drv.get(BASE + "?audit=" + str(int(time.time())))
        visible(drv, "body", 20)

        try:
            assert drv.title == "Johanna´s Gartenwelt"
            assert len(drv.find_elements(By.CSS_SELECTOR, ".tabs .tab")) == 5
            assert visible(drv, "#view-today")
            record("Startansicht und Hauptnavigation")
        except Exception as exc:
            record("Startansicht und Hauptnavigation", "FAIL", repr(exc))

        try:
            body_font = drv.execute_script("return getComputedStyle(document.body).fontFamily")
            h1_font = drv.execute_script("return getComputedStyle(document.querySelector('h1')).fontFamily")
            tab_h = drv.execute_script("return document.querySelector('.tabs .tab').getBoundingClientRect().height")
            assert tab_h >= 50
            assert any(x in body_font for x in ["Arial", "Segoe UI", "Roboto", "BlinkMacSystemFont", "SF Pro"])
            assert "Georgia" in h1_font
            record("Finale Typografie und Touch-Ziele", detail=f"Navigation {tab_h:.0f}px")
        except Exception as exc:
            record("Finale Typografie und Touch-Ziele", "FAIL", repr(exc))

        try:
            click(drv, "#settingsGear")
            assert visible(drv, "#settingsOverlay")
            screenshot(drv, "mobile_settings.png")
            click(drv, "#settingsClose")
            record("Einstellungen öffnen/schließen")
        except Exception as exc:
            record("Einstellungen öffnen/schließen", "FAIL", repr(exc))

        # Real production browser request to PLZ and weather service.
        try:
            click(drv, "#settingsGear")
            plz = visible(drv, "#plz")
            plz.clear(); plz.send_keys("72144")
            click(drv, "#locationForm button[type='submit']")
            wait(drv, 20).until(lambda d: "72144" in text(d, "#headerLocation"))
            click(drv, "#settingsClose")
            click(drv, ".tab[data-view='weather']")
            wait(drv, 20).until(lambda d: "mm" in text(d, "#wTotal") and text(d, "#wTotal") != "–")
            record("Standort, PLZ-Suche und Wetterabruf", detail=text(drv, "#wTotal"))
        except Exception as exc:
            detail = (error_text(drv) + " | " + repr(exc)).strip(" |");
            severity = "FAIL" if PROBES.get("Zippopotam") and PROBES.get("Open-Meteo") else "WARN"
            record("Standort, PLZ-Suche und Wetterabruf", severity, detail)
            try:
                if drv.find_element(By.ID, "settingsOverlay").is_displayed():
                    click(drv, "#settingsClose")
            except Exception:
                pass

        try:
            click(drv, ".tab[data-view='map']")
            wait(drv, 20).until(lambda d: "leaflet-container" in (d.find_element(By.ID, "map").get_attribute("class") or ""))
            assert drv.find_element(By.ID, "drawZoneBtn").is_enabled()
            if drv.find_element(By.ID, "saveMapViewBtn").is_displayed():
                click(drv, "#saveMapViewBtn")
            app = local_json(drv, "giess_check_garten_v3")
            assert app and app.get("settings", {}).get("mapView") and app.get("gardenCenter")
            screenshot(drv, "mobile_map.png")
            record("Gartenkarte, Ausschnitt und Wetterposition")
        except Exception as exc:
            record("Gartenkarte, Ausschnitt und Wetterposition", "FAIL", repr(exc))

        try:
            click(drv, ".tab[data-view='plants']")
            click(drv, "#newPlantBtn")
            assert visible(drv, "#plantEditor")
            assert drv.find_element(By.ID, "plantType").get_attribute("value") == "bed"
            advanced = drv.find_element(By.ID, "plantAdvanced")
            assert not advanced.get_property("open")
            drv.find_element(By.ID, "plantName").send_keys("Test-Hortensie")
            drv.find_element(By.ID, "plantArea").send_keys("Testbeet")
            drv.execute_script("arguments[0].open=true", advanced)
            fert = drv.find_elements(By.CSS_SELECTOR, "#fertMonths input[type='checkbox']")
            if fert:
                drv.execute_script("arguments[0].click();", fert[time.localtime().tm_mon - 1])
            click(drv, "#plantForm button[type='submit']")
            wait(drv).until(lambda d: "Test-Hortensie" in text(d, "#plantList"))
            screenshot(drv, "mobile_plants.png")
            plant_created = True
            calendar_ready = bool(fert)
            record("Pflanze anlegen und Standard Gartenboden")
        except Exception as exc:
            record("Pflanze anlegen und Standard Gartenboden", "FAIL", repr(exc))

        if plant_created:
            try:
                search = drv.find_element(By.ID, "plantSearch")
                search.send_keys("Test-Hort")
                assert "Test-Hortensie" in text(drv, "#plantList")
                search.clear(); search.send_keys("nichtvorhanden")
                wait(drv).until(lambda d: "Keine passende Pflanze" in text(d, "#plantList"))
                search.clear()
                record("Pflanzensuche")
            except Exception as exc:
                record("Pflanzensuche", "FAIL", repr(exc))

            try:
                click(drv, ".tab[data-view='today']")
                if len(drv.find_elements(By.CSS_SELECTOR, ".taskDone")):
                    btn = drv.find_elements(By.CSS_SELECTOR, ".taskDone")[-1]
                    drv.execute_script("arguments[0].click();", btn)
                    time.sleep(0.7)
                app = local_json(drv, "giess_check_garten_v3")
                assert any(p.get("name") == "Test-Hortensie" for p in app.get("plants", []))
                screenshot(drv, "mobile_today.png")
                record("Heute-Aufgaben und Pflanzenstatus")
            except Exception as exc:
                record("Heute-Aufgaben und Pflanzenstatus", "FAIL", repr(exc))

        try:
            click(drv, ".tab[data-view='calendar']")
            initial = len(drv.find_elements(By.CSS_SELECTOR, "#calendarGrid .calmonth"))
            assert initial <= 3
            click(drv, "#calendarToggle")
            expanded = len(drv.find_elements(By.CSS_SELECTOR, "#calendarGrid .calmonth"))
            assert expanded >= initial
            if calendar_ready:
                before = {p for p in DOWNLOADS.iterdir() if p.suffix.lower() == ".ics"}
                click(drv, "#exportCareYear")
                ics = wait_download(".ics", before)
                assert "BEGIN:VCALENDAR" in ics.read_text(encoding="utf-8-sig")
                record("Pflegekalender und ICS-Export", detail=f"{initial}→{expanded} Monate")
            else:
                record("Pflegekalender", detail=f"{initial}→{expanded} Monate; ICS ohne Pflegeeintrag nicht ausgelöst")
        except Exception as exc:
            record("Pflegekalender und ICS-Export", "FAIL", repr(exc))

        try:
            click(drv, "#settingsGear")
            before = {p for p in DOWNLOADS.iterdir() if p.suffix.lower() == ".json"}
            click(drv, "#exportBtn")
            backup = wait_download(".json", before)
            data = json.loads(backup.read_text(encoding="utf-8-sig"))
            assert isinstance(data.get("plants"), list) and "zones" in data
            inp = drv.find_element(By.ID, "importFile")
            inp.send_keys(str(backup.resolve()))
            try:
                wait(drv, 3).until(EC.alert_is_present()).accept()
            except TimeoutException:
                pass
            time.sleep(0.6)
            assert local_json(drv, "giess_check_garten_v3") is not None
            click(drv, "#settingsClose")
            record("Datensicherung Export/Import", detail=backup.name)
        except Exception as exc:
            record("Datensicherung Export/Import", "FAIL", repr(exc))
            try:
                if drv.find_element(By.ID, "settingsOverlay").is_displayed(): click(drv, "#settingsClose")
            except Exception: pass

        try:
            click(drv, "#settingsGear")
            Select(drv.find_element(By.ID, "seasonMode")).select_by_value("winter")
            time.sleep(0.2)
            assert drv.find_element(By.TAG_NAME, "body").get_attribute("data-season") == "winter"
            Select(drv.find_element(By.ID, "seasonMode")).select_by_value("auto")
            click(drv, "#settingsClose")
            record("Jahreszeiten-Design und Animationseinstellung")
        except Exception as exc:
            record("Jahreszeiten-Design und Animationseinstellung", "FAIL", repr(exc))

        try:
            click(drv, "#settingsGear")
            click(drv, "#generateGardenId")
            gid = drv.find_element(By.ID, "syncGardenId").get_attribute("value")
            assert gid.startswith("JOHANNA-") and len(gid) >= 10
            click(drv, "#settingsClose")
            record("Sync-Einrichtung und Garten-ID", detail=gid)
        except Exception as exc:
            record("Sync-Einrichtung und Garten-ID", "FAIL", repr(exc))

        if plant_created:
            try:
                click(drv, ".tab[data-view='plants']")
                cards = drv.find_elements(By.CSS_SELECTOR, ".plantcard")
                card = next(c for c in cards if "Test-Hortensie" in c.text)
                details = card.find_element(By.CSS_SELECTOR, "details.plant-more")
                drv.execute_script("arguments[0].open=true", details)
                drv.execute_script("arguments[0].click()", card.find_element(By.CSS_SELECTOR, ".deletePlant"))
                wait(drv, 3).until(EC.alert_is_present()).accept()
                assert visible(drv, "#undoToast")
                click(drv, "#undoDeleteBtn")
                wait(drv).until(lambda d: "Test-Hortensie" in text(d, "#plantList"))
                record("Löschen und Rückgängig")
            except Exception as exc:
                record("Löschen und Rückgängig", "FAIL", repr(exc))

        # QR generator and decrypt flow use only synthetic test credentials.
        try:
            drv.execute_script(
                """
                localStorage.setItem('giess_check_garten_v3', JSON.stringify({plz:'72144',loc:null,gardenCenter:null,plants:[],zones:[],settings:{plantnetKey:'TEST-PLANTNET-123456'}}));
                localStorage.setItem('johannas_gartenwelt_sync_v1', JSON.stringify({url:'https://example.supabase.co',key:'sb_publishable_TESTKEY_1234567890',gardenId:'johanna-test99',pin:'123456',enabled:true,revision:1,lastSync:'',lastPayloadHash:'',dirty:false}));
                """
            )
            drv.get(BASE + "setup.html?audit=" + str(int(time.time())))
            wait(drv, 20).until(lambda d: d.find_element(By.ID, "makeQr").is_enabled())
            click(drv, "#makeQr")
            wait(drv, 20).until(lambda d: len(d.find_elements(By.CSS_SELECTOR, "#qrCanvas img,#qrCanvas canvas")) > 0)
            token_link = text(drv, "#setupLink").strip()
            assert "#setup=" in token_link
            assert drv.find_element(By.CSS_SELECTOR, "link[rel='apple-touch-icon']").get_attribute("href").endswith("app-icon-180.png")
            assert drv.find_element(By.CSS_SELECTOR, "link[rel='icon']").get_attribute("href").endswith("app-icon.svg")
            screenshot(drv, "setup_qr.png")
            record("QR-Code erzeugen und Einrichtungsseite", detail=f"Token-Link {len(token_link)} Zeichen")
        except Exception as exc:
            record("QR-Code erzeugen und Einrichtungsseite", "FAIL", repr(exc))
            token_link = None

        if token_link:
            try:
                drv.get(token_link)
                assert visible(drv, "#installBox")
                click(drv, "#safariOnly")
                assert visible(drv, "#receiverBox")
                drv.find_element(By.ID, "setupPin").send_keys("123456")
                click(drv, "#unlockForm button[type='submit']")
                wait(drv, 10).until(lambda d: local_json(d, "johannas_gartenwelt_sync_v1") is not None)
                sync = local_json(drv, "johannas_gartenwelt_sync_v1")
                assert sync.get("gardenId") == "johanna-test99" and sync.get("enabled") is True
                record("QR-Empfang, Safari-Zwischenschritt und PIN-Entschlüsselung")
            except Exception as exc:
                record("QR-Empfang, Safari-Zwischenschritt und PIN-Entschlüsselung", "FAIL", repr(exc))

        errs = browser_errors(drv)
        if errs:
            record("JavaScript-Konsole", "WARN", " | ".join(errs[:4]))
        else:
            record("JavaScript-Konsole ohne Laufzeitfehler")

    finally:
        drv.quit()
    return token_link


def run_standalone_audit(token_link):
    if not token_link:
        record("Simulierter Home-Screen-Modus", "SKIP", "kein QR-Token aus vorherigem Test")
        return
    drv = chrome(mobile=True, standalone=True)
    try:
        drv.get(token_link)
        assert visible(drv, "#receiverBox")
        assert not drv.find_element(By.ID, "installBox").is_displayed()
        assert "Home-Screen-App" in text(drv, "#receiverMode")
        drv.find_element(By.ID, "setupPin").send_keys("123456")
        click(drv, "#unlockForm button[type='submit']")
        wait(drv, 10).until(lambda d: local_json(d, "johannas_gartenwelt_sync_v1") is not None)
        sync = local_json(drv, "johannas_gartenwelt_sync_v1")
        assert sync.get("gardenId") == "johanna-test99"
        record("Simulierter Home-Screen-Modus übernimmt QR-Zugang")
    except Exception as exc:
        record("Simulierter Home-Screen-Modus übernimmt QR-Zugang", "FAIL", repr(exc))
    finally:
        drv.quit()


def run_desktop_visual():
    drv = chrome(mobile=False)
    try:
        drv.get(BASE + "?desktop-audit=" + str(int(time.time())))
        visible(drv, "#view-today", 20)
        screenshot(drv, "desktop_today.png")
        click(drv, ".tab[data-view='plants']")
        screenshot(drv, "desktop_plants.png")
        record("Desktop-Darstellung")
    except Exception as exc:
        record("Desktop-Darstellung", "FAIL", repr(exc))
    finally:
        drv.quit()


def main():
    probe("Zippopotam", "https://api.zippopotam.us/de/72144")
    probe("Open-Meteo", "https://api.open-meteo.com/v1/forecast?latitude=48.42&longitude=9.05&daily=precipitation_sum,et0_fao_evapotranspiration,temperature_2m_min,temperature_2m_max&timezone=Europe%2FBerlin&past_days=2&forecast_days=2")
    probe("QR-CDN", "https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js")
    token = run_mobile_audit()
    run_standalone_audit(token)
    run_desktop_visual()

    (OUT / "audit_report.json").write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding="utf-8")
    failed = [r for r in REPORT if r["status"] == "FAIL"]
    warned = [r for r in REPORT if r["status"] == "WARN"]
    passed = [r for r in REPORT if r["status"] == "PASS"]
    print(f"AUDIT SUMMARY: {len(passed)} PASS, {len(warned)} WARN, {len(failed)} FAIL")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
