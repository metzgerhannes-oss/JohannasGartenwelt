# Vokabeltrainer – Cache-Strategie

Stand: 20.09.2026 · App v0.9.17

Punkt 3 des Pre-v1-Fahrplans trennt kurzlebige App-Dateien von großen, langlebigen Lernressourcen.

## Problem des bisherigen Stands

Bis v0.9.16 nutzte der Vokabeltrainer einen einzigen versionsgebundenen Cache. Beim Aktivieren eines neuen Service Workers wurde dieser Cache ersetzt. Dadurch mussten bereits verwendete OCR- und Wörterbuchdateien nach App-Updates erneut geladen werden.

Zusätzlich war die bisherige Löschlogik zu breit: Sie konnte CacheStorage-Einträge derselben Origin löschen, die nicht zum Vokabeltrainer gehören. CacheStorage ist originweit, auch wenn Service-Worker-Scope und App-Pfad enger sind.

## Neue Trennung

### Shell-Cache

`vokabeltrainer-shell-v0.9.17`

Enthält HTML, CSS, JavaScript, Manifest und Icons. Dieser Cache ist an die App-Version gekoppelt und darf bei einem Release ersetzt werden.

### Ressourcen-Cache

`vokabeltrainer-resources-v1`

Enthält nur on-demand geladene Ressourcen unter:

- `vokabeltrainer/ocr/`
- `vokabeltrainer/dict/wikidict/`

Die Ressourcenrevision ist absichtlich unabhängig von der App-Version. Ein Update von v0.9.17 auf eine spätere App-Version behält diesen Cache, solange sich die eigentlichen OCR-/Wörterbuchdaten nicht ändern.

Wenn OCR-Engine, Sprachmodelle oder Wikidict-Daten inkompatibel aktualisiert werden, muss `RESOURCE_REVISION` bewusst erhöht werden.

## Migration

Beim ersten Aktivieren der neuen Cache-Strategie werden passende OCR-/Wörterbuchantworten aus alten `vokabeltrainer-v...`-Caches in den persistenten Ressourcen-Cache kopiert. Erst danach werden die alten Vokabeltrainer-Caches gelöscht.

Caches anderer Apps oder anderer Präfixe werden nie gelöscht.

## Abrufstrategie

- Navigation: network-first mit Shell-Fallback.
- App-Shell: cache-first innerhalb des aktuellen Shell-Caches.
- OCR/Wikidict: cache-first innerhalb des langlebigen Ressourcen-Caches.
- Neue große Ressourcen werden beim ersten Abruf mit `cache: reload` geladen und anschließend persistiert.
- Teilantworten werden nicht als vollständige Ressource gecacht; nur HTTP 200 wird übernommen.

Tesseract.js besitzt zusätzlich einen eigenen IndexedDB-Cache für `.traineddata`. Dieser bleibt bestehen und ergänzt den Service-Worker-Cache.

## Grenzen

„Versionsübergreifend“ bedeutet: Ein normales App-Update verwirft die Ressourcen nicht. Browser oder Betriebssystem dürfen Website-Speicher bei Speicherdruck trotzdem löschen. Die App bleibt dann funktionsfähig und lädt die benötigte Ressource beim nächsten Online-Zugriff erneut.

## CI-Schutz

`scripts/vokabeltrainer-cache-smoke.mjs` prüft:

1. Gartenwelt- und fremde Origin-Caches bleiben unangetastet.
2. alte OCR-/Wörterbuchressourcen werden migriert.
3. gecachte OCR-Dateien funktionieren ohne Netzwerk.
4. ein neu geladenes Wörterbuch-Shard wird beim zweiten Zugriff aus dem langlebigen Cache bedient.
5. die frühere globale Cache-Löschlogik darf nicht zurückkehren.

Zusätzlich prüft `scripts/vokabeltrainer-webkit-smoke.mjs` im echten WebKit/iPhone-Kontext, dass der verschachtelte Vokabeltrainer-Service-Worker aktiv wird, einen Wikidict-Shard offline wieder ausliefert und einen fremden `jgw-*`-Cache unangetastet lässt.
