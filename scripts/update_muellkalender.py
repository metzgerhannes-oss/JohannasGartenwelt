from __future__ import annotations

import datetime as dt
import re
import unicodedata
from pathlib import Path

import requests

CUSTOMER = "tuebingen"
CITY = "Mössingen"
OUTPUT = Path("kalender/muell-moessingen.ics")
BASE = "https://awido.cubefour.de"


def norm(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).strip().casefold()
    return re.sub(r"\s+", " ", value)


def get_json(url: str, **params):
    r = requests.get(url, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def resolve_oid() -> tuple[str, str]:
    places = get_json(
        f"{BASE}/WebServices/Awido.Service.svc/secure/getPlaces/client={CUSTOMER}"
    )
    place_map = {norm(p["value"]): p for p in places}
    city = place_map.get(norm(CITY))
    if city is None:
        suggestions = [p["value"] for p in places if "möss" in norm(p["value"])]
        raise RuntimeError(f"Ort {CITY!r} nicht gefunden. Treffer: {suggestions}")

    groups = get_json(
        f"{BASE}/WebServices/Awido.Service.svc/secure/getGroupedStreets/{city['key']}",
        client=CUSTOMER,
    )
    if not groups:
        return str(city["key"]), CITY

    # AWIDO often returns exactly one collection district for a city. If there
    # are several, prefer an entry whose label is the city name itself.
    if len(groups) == 1:
        return str(groups[0]["key"]), str(groups[0].get("value") or CITY)

    exact = [g for g in groups if norm(str(g.get("value", ""))) == norm(CITY)]
    if len(exact) == 1:
        return str(exact[0]["key"]), str(exact[0].get("value") or CITY)

    # Some AWIDO clients use an empty group as the city-wide/default district.
    empty = [g for g in groups if not norm(str(g.get("value", "")))]
    if len(empty) == 1:
        return str(empty[0]["key"]), CITY

    labels = [str(g.get("value", "")) for g in groups]
    raise RuntimeError(
        "Mössingen hat mehrere Abfuhrbezirke und keiner ist eindeutig der "
        f"Stadt zuordenbar: {labels}"
    )


def download_year(oid: str, year: int) -> str:
    r = requests.get(
        f"{BASE}/Customer/{CUSTOMER}/KalenderICS.aspx",
        params={"oid": oid, "jahr": year, "fraktionen": "", "reminder": "-1.17:00"},
        timeout=30,
    )
    r.raise_for_status()
    return r.text.replace("\r\n", "\n").replace("\r", "\n")


def event_blocks(ics: str) -> list[str]:
    return re.findall(r"BEGIN:VEVENT\n.*?\nEND:VEVENT", ics, flags=re.S)


def main() -> None:
    oid, group = resolve_oid()
    today = dt.date.today()
    years = [today.year, today.year + 1]

    events: list[str] = []
    seen: set[str] = set()
    for year in years:
        for event in event_blocks(download_year(oid, year)):
            uid = re.search(r"^UID:(.+)$", event, flags=re.M)
            key = uid.group(1).strip() if uid else event
            if key not in seen:
                seen.add(key)
                events.append(event)

    if not events:
        raise RuntimeError("AWIDO hat keine Kalendertermine geliefert.")

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//JohannasGartenwelt//Muellkalender Moessingen//DE",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:Müllabfuhr Mössingen",
        "X-WR-TIMEZONE:Europe/Berlin",
        f"X-WR-CALDESC:Automatisch aktualisiert aus AWIDO Landkreis Tübingen; Bezirk: {group}; Stand: {stamp}",
        *events,
        "END:VCALENDAR",
        "",
    ]

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\r\n".join(lines), encoding="utf-8")
    print(f"Erstellt: {OUTPUT} | Bezirk: {group} | OID: {oid} | Termine: {len(events)}")


if __name__ == "__main__":
    main()
