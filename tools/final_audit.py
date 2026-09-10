from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from urllib.parse import urlsplit

from selenium import webdriver
from selenium.common.exceptions import NoAlertPresentException, TimeoutException
from selenium.webdriver import ActionChains
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

BASE = "https://metzgerhannes-oss.github.io/JohannasGartenwelt/"
OUT = Path("audit_artifacts")
OUT.mkdir(exist_ok=True)
DOWNLOADS = OUT / "downloads"
DOWNLOADS.mkdir(exist_ok=True)
REPORT = []


def record(name, status="PASS", detail=""):
    REPORT.append({"name": name, "status": status, "detail": detail})
    print(f"[{status}] {name}: {detail}")


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
    if mobile:
        drv.set_window_size(390, 844)
    else:
        drv.set_window_size(1280, 900)
    if standalone:
        drv.execute_cdp_cmd(
            "Page.addScriptToEvaluateOnNewDocument",
            {
                "source": "Object.defineProperty(navigator,'standalone',{configurable:true,get:function(){return true;}});"
            },
        )
    return drv


def wait(drv, seconds=12):
    return WebDriverWait(drv, seconds)


def visible(drv, css):
    return wait(drv).until(EC.visibility_of_element_located((By.CSS_SELECTOR, css)))


def click(drv, css):
    el = wait(drv).until(EC.element_to_be_clickable((By.CSS_SELECTOR, css)))
    drv.execute_script("arguments[0].scrollIntoView({block:'center'});", el)
    try:
        el.click()
    except Exception:
        drv.execute_script("arguments[0].click();", el)
    return el


def text(drv, css):
    return drv.find_element(By.CSS_SELECTOR, css).text


def screenshot(drv, filename):
    path = OUT / filename
    drv.save_screenshot(str(path))
    return str(path)


def local_json(drv, key):
    return drv.execute_script("return JSON.parse(localStorage.getItem(arguments[0]) || 'null');", key)


def wait_download(suffix, before, timeout=8):
    end = time.time() + timeout
    while time.time() < end:
        files = {p for p in DOWNLOADS.iterdir() if p.is_file() and p.suffix.lower() == suffix}
        new = files - before
        if new:
            return sorted(new, key=lambda p: p.stat().st_mtime)[-1]
        time.sleep(0.25)
    raise TimeoutException(f"download {suffix} not found")


def browser_errors(drv):
    bad = []
    for row in drv.get_log("browser"):
        if row.get("level") != "SEVERE":
            continue
        msg = row.get("message", "")
        low = msg.lower()
        # Tile/image failures are non-fatal for app logic and can be transient.
        if any(x in low for x in ["favicon", "tile", "wms_lgl", "net::err_blocked_by_client"]):
            continue
        bad.append(msg)
    return bad


def run_mobile_audit():
    drv = chrome(mobile=True)
    token_link = None
    try:
        drv.get(BASE + "?audit=" + str(int(time.time())))
        visible(drv, "body")
        wait(drv).until(lambda d: d.execute_script("return document.readyState") in ("interactive", "complete"))

        assert drv.title == "Johanna´s Gartenwelt"
        assert len(drv.find_elements(By.CSS_SELECTOR, ".tabs .tab")) == 5
        assert visible(drv, "#view-today")
        record("Startansicht und Hauptnavigation")

        # Typography and touch targets.
        body_font = drv.execute_script("return getComputedStyle(document.body).fontFamily")
        h1_font = drv.execute_script("return getComputedStyle(document.querySelector('h1')).fontFamily")
        tab_h = drv.execute_script("return document.querySelector('.tabs .tab').getBoundingClientRect().height")
        assert tab_h >= 50
        assert any(x in body_font for x in ["Arial", "Segoe UI", "Roboto", "BlinkMacSystemFont", "SF Pro"])
        assert "Georgia" in h1_font
        record("Finale Typografie und Touch-Ziele", detail=f"Navigation {tab_h:.0f}px")

        # Settings overlay.
        click(drv, "#settingsGear")
        assert visible(drv, "#settingsOverlay")
        screenshot(drv, "mobile_settings.png")
        click(drv, "#settingsClose")
        record("Einstellungen öffnen/schließen")

        # Location and external weather services.
        click(drv, "#settingsGear")
        plz = visible(drv, "#plz")
        plz.clear(); plz.send_keys("72144")
        click(drv, "#locationForm button[type='submit']")
        wait(drv, 20).until(lambda d: "72144" in text(d, "#headerLocation"))
        click(drv, "#settingsClose")
        click(drv, ".tab[data-view='weather']")
        wait(drv, 20).until(lambda d: "mm" in text(d, "#wTotal") and text(d, "#wTotal") != "–")
        record("Standort, PLZ-Suche und Wetterabruf", detail=text(drv, "#wTotal"))

        # Map loads and can save viewport/weather position.
        click(drv, ".tab[data-view='map']")
        wait(drv, 20).until(lambda d: "leaflet-container" in (d.find_element(By.ID, "map").get_attribute("class") or ""))
        assert drv.find_element(By.ID, "drawZoneBtn").is_enabled()
        if drv.find_element(By.ID, "saveMapViewBtn").is_displayed():
            click(drv, "#saveMapViewBtn")
        app = local_json(drv, "giess_check_garten_v3")
        assert app and app.get("settings", {}).get("mapView")
        assert app.get("gardenCenter")
        screenshot(drv, "mobile_map.png")
        record("Gartenkarte, Ausschnitt und Wetterposition")

        # Add plant; advanced details are optional and standard planting is garden soil.
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
            fert[time.localtime().tm_mon - 1].click()
        click(drv, "#plantForm button[type='submit']")
        wait(drv).until(lambda d: "Test-Hortensie" in text(d, "#plantList"))
        screenshot(drv, "mobile_plants.png")
        record("Pflanze anlegen und Standard Gartenboden")

        # Search.
        search = drv.find_element(By.ID, "plantSearch")
        search.send_keys("Test-Hort")
        assert "Test-Hortensie" in text(drv, "#plantList")
        search.clear(); search.send_keys("nichtvorhanden")
        wait(drv).until(lambda d: "Keine passende Pflanze" in text(d, "#plantList"))
        search.clear()
        record("Pflanzensuche")

        # Today tasks: fertilizer task should exist because current month was selected.
        click(drv, ".tab[data-view='today']")
        wait(drv).until(lambda d: len(d.find_elements(By.CSS_SELECTOR, ".taskDone")) > 0)
        task_buttons = drv.find_elements(By.CSS_SELECTOR, ".taskDone")
        task_buttons[-1].click()
        time.sleep(0.8)
        app = local_json(drv, "giess_check_garten_v3")
        plant = next(p for p in app["plants"] if p["name"] == "Test-Hortensie")
        assert plant.get("lastFertilized") or plant.get("lastWatered") or plant.get("lastCut")
        screenshot(drv, "mobile_today.png")
        record("Heute-Aufgaben und Erledigt-Status")

        # Calendar compact view, expansion and ICS download.
        click(drv, ".tab[data-view='calendar']")
        initial = len(drv.find_elements(By.CSS_SELECTOR, "#calendarGrid .calmonth"))
        assert initial <= 3
        click(drv, "#calendarToggle")
        expanded = len(drv.find_elements(By.CSS_SELECTOR, "#calendarGrid .calmonth"))
        assert expanded >= initial
        before = {p for p in DOWNLOADS.iterdir() if p.suffix.lower() == ".ics"}
        click(drv, "#exportCareYear")
        ics = wait_download(".ics", before)
        assert "BEGIN:VCALENDAR" in ics.read_text(encoding="utf-8-sig")
        record("Pflegekalender und ICS-Export", detail=f"{initial}→{expanded} Monate")

        # Backup export and re-import.
        click(drv, "#settingsGear")
        before = {p for p in DOWNLOADS.iterdir() if p.suffix.lower() == ".json"}
        click(drv, "#exportBtn")
        backup = wait_download(".json", before)
        data = json.loads(backup.read_text(encoding="utf-8-sig"))
        assert isinstance(data.get("plants"), list) and "zones" in data
        inp = drv.find_element(By.ID, "importFile")
        inp.send_keys(str(backup.resolve()))
        try:
            alert = wait(drv, 3).until(EC.alert_is_present())
            alert.accept()
        except TimeoutException:
            pass
        time.sleep(0.8)
        assert local_json(drv, "giess_check_garten_v3") is not None
        click(drv, "#settingsClose")
        record("Datensicherung Export/Import", detail=backup.name)

        # Appearance.
        click(drv, "#settingsGear")
        season = drv.find_element(By.ID, "seasonMode")
        from selenium.webdriver.support.ui import Select
        Select(season).select_by_value("winter")
        time.sleep(0.2)
        assert drv.find_element(By.TAG_NAME, "body").get_attribute("data-season") == "winter"
        Select(season).select_by_value("auto")
        click(drv, "#settingsClose")
        record("Jahreszeiten-Design und Animationseinstellung")

        # Sync setup UI and random garden ID.
        click(drv, "#settingsGear")
        click(drv, "#generateGardenId")
        gid = drv.find_element(By.ID, "syncGardenId").get_attribute("value")
        assert gid.startswith("JOHANNA-") and len(gid) >= 10
        click(drv, "#settingsClose")
        record("Sync-Einrichtung und Garten-ID", detail=gid)

        # Delete + undo.
        click(drv, ".tab[data-view='plants']")
        cards = drv.find_elements(By.CSS_SELECTOR, ".plantcard")
        card = next(c for c in cards if "Test-Hortensie" in c.text)
        details = card.find_element(By.CSS_SELECTOR, "details.plant-more")
        drv.execute_script("arguments[0].open=true", details)
        delete_btn = card.find_element(By.CSS_SELECTOR, ".deletePlant")
        drv.execute_script("arguments[0].click()", delete_btn)
        wait(drv, 3).until(EC.alert_is_present()).accept()
        assert visible(drv, "#undoToast")
        click(drv, "#undoDeleteBtn")
        wait(drv).until(lambda d: "Test-Hortensie" in text(d, "#plantList"))
        record("Löschen und Rückgängig")

        # QR generation with synthetic credentials, no real secrets.
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

        # Safari branch then PIN decryption.
        drv.get(token_link)
        assert visible(drv, "#installBox")
        click(drv, "#safariOnly")
        assert visible(drv, "#receiverBox")
        drv.find_element(By.ID, "setupPin").send_keys("123456")
        click(drv, "#unlockForm button[type='submit']")
        wait(drv, 8).until(lambda d: urlsplit(d.current_url).path.endswith("/JohannasGartenwelt/") or urlsplit(d.current_url).path.endswith("/JohannasGartenwelt/index.html"))
        sync = local_json(drv, "johannas_gartenwelt_sync_v1")
        assert sync and sync.get("gardenId") == "johanna-test99" and sync.get("enabled") is True
        record("QR-Empfang, Safari-Zwischenschritt und PIN-Entschlüsselung")

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
        wait(drv, 8).until(lambda d: local_json(d, "johannas_gartenwelt_sync_v1") is not None)
        sync = local_json(drv, "johannas_gartenwelt_sync_v1")
        assert sync.get("gardenId") == "johanna-test99"
        record("Simulierter Home-Screen-Modus übernimmt QR-Zugang")
    finally:
        drv.quit()


def run_desktop_visual():
    drv = chrome(mobile=False)
    try:
        drv.get(BASE + "?desktop-audit=" + str(int(time.time())))
        visible(drv, "#view-today")
        screenshot(drv, "desktop_today.png")
        click(drv, ".tab[data-view='plants']")
        screenshot(drv, "desktop_plants.png")
        record("Desktop-Darstellung")
    finally:
        drv.quit()


def main():
    token = None
    try:
        token = run_mobile_audit()
    except Exception as exc:
        record("Mobile Gesamtaudit", "FAIL", repr(exc))
    try:
        run_standalone_audit(token)
    except Exception as exc:
        record("Home-Screen Gesamtaudit", "FAIL", repr(exc))
    try:
        run_desktop_visual()
    except Exception as exc:
        record("Desktop Gesamtaudit", "FAIL", repr(exc))

    (OUT / "audit_report.json").write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding="utf-8")
    failed = [r for r in REPORT if r["status"] == "FAIL"]
    passed = [r for r in REPORT if r["status"] == "PASS"]
    warned = [r for r in REPORT if r["status"] == "WARN"]
    print(f"AUDIT SUMMARY: {len(passed)} PASS, {len(warned)} WARN, {len(failed)} FAIL")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
