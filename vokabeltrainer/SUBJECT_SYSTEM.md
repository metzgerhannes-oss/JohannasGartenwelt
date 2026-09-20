# Vokabeltrainer – generisches Fachsystem

Stand: 20.09.2026 · App v0.9.15

Punkt 2 des Pre-v1-Fahrplans macht Fremdsprachen zu Konfiguration statt Sonderlogik.

## Grundsatz

Ein neues Fach wird in `SUBJECT_META` beschrieben. Datenmodell, Profile, Lehrwerke, Lernsets, Tests, Lernfortschritt und Navigation dürfen nicht auf feste Fachlisten wie `['english','latin']` angewiesen sein.

Konfiguriert werden pro Fach:

- sichtbarer Name und Kürzel
- Aliasnamen für CSV/Import
- BCP-47-Sprachcode für Sprachausgabe
- Tesseract-Sprachcode für OCR
- Import-/Lexemprofil
- optionale Capabilities, z. B. Latein-Grammatik
- Kampagnenbeschriftung und Ränge

## Aktueller Stand

**Englisch** und **Latein** bleiben produktiv aktiv.

**Französisch** ist vollständig im Fachmodell vorbereitet, aber noch `available:false`. Grund: Das lokale Offline-OCR-Paket enthält aktuell `eng.traineddata`, `deu.traineddata` und `lat.traineddata`, jedoch noch kein `fra.traineddata`. Die Oberfläche soll kein Fach freigeben, dessen Fotoimport nicht vollständig funktioniert.

Für Französisch sind bereits konfiguriert:

- `speechLang: fr-FR`
- `ocrLang: fra`
- moderne Importlogik statt Latein-Sonderbehandlung
- französische Funktionswörter für OCR-/Textheuristik
- normale Retrieval-/Spacing-/Mastery-Logik
- Lehrwerk/ISBN, Tests, Notenskala, Bibliothek und Lernstände über dasselbe generische Datenmodell

Nach Bereitstellung der OCR-Ressource darf die Freischaltung nur noch eine Konfigurationsänderung sein: `available:true`.

## Capabilities statt Fachabfragen

Sprachspezifische Funktionen werden als Fähigkeit modelliert:

- `hybridDictionary`: aktuell Englisch
- `latinGrammar`: Latein
- `extraIdentity`: Latein, wenn Zusatzformen ein Lexem disambiguieren

Dadurch muss z. B. Französisch nicht mit neuen `if (subject === 'french')`-Blöcken ergänzt werden.

## Pädagogische Leitplanke

Retrieval Practice bleibt fachübergreifend der Kern. Forschung zeigt den Nutzen von Retrieval auch beim Lernen französischer L3-Vokabeln; die Fachgenerik verändert daher nicht Mastery, Spacing oder die konservative Bewertung, sondern nur sprachspezifische Ein-/Ausgabe. Siehe u. a. die Studie zu Retrieval Practice bei französischen L3-Wörtern: https://doi.org/10.1016/j.system.2019.05.002

## Aktivierungs-Check für ein neues Fach

1. `SUBJECT_META` ergänzen.
2. Offline-OCR-Sprachdatei bereitstellen.
3. Sprachausgabe-Code verifizieren.
4. Import-Smoke-Test mit typischer Lehrwerksseite.
5. Fach aktivieren.
6. CI muss ohne neue fachnamenspezifische Verzweigungen bestehen.

Französisch bleibt bis Schritt 2/4 deaktiviert.
