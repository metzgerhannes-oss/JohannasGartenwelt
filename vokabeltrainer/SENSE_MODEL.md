# Vokabeltrainer – Sense-/Bedeutungsmodell

Stand: 20.09.2026 · Modellversion 1 · App v0.9.13

Dieses Dokument konkretisiert Prinzip 10 der `PRODUCT_DNA.md`. Es ist die verbindliche fachliche und technische Definition für Lexem, Bedeutung, Schulbuchform und Lernstand.

## 1. Datenmodell

Ein **Lexem** wird pro Fremdsprache global einmal gespeichert. Ein Lexem besitzt eine oder mehrere **Senses/Bedeutungen**.

- `vocabulary`: globales Lexem, z. B. `bank`
- `vocabulary.senses[]`: fachlich getrennte Bedeutungen, z. B. `Bank` und `Ufer`
- `sense.translation`: kanonische deutsche Hauptbedeutung
- `sense.translations[]`: globale Synonyme/Formulierungsvarianten derselben Bedeutung
- `sense.partOfSpeech`: optionale Wortart als disambiguierendes Merkmal
- `sense.examples[]`: Kontextbeispiele dieser Bedeutung
- `setVocabulary.senseId`: welche Bedeutung in einem Lernset gemeint ist
- `setVocabulary.translationOverride`: verlangte Schulbuchformulierung
- `setVocabulary.acceptedTranslationOverrides[]`: nur für dieses Lernset zusätzlich akzeptierte Antworten
- `learnerVocabulary.senseId`: persönlicher Lernstand genau dieser Bedeutung

## 2. Invarianten

1. **Sense ist nicht Synonym.** `nett` und `freundlich` können Formulierungsvarianten derselben Bedeutung sein. Sie erzeugen keinen zweiten Lernstand.
2. **Neue Bedeutung = neuer Lernstand.** `bank = Bank` und `bank = Ufer` haben getrennte Progress-Objekte, Intervalle und Mastery.
3. **Kein Mastery-Transfer zwischen Senses.** Ein gemeisterter Sense macht einen neu hinzugefügten Sense nicht automatisch stabil oder gemeistert.
4. **Schulbuchform bleibt lokal.** Eine abweichende Formulierung eines Lehrwerks wird als Override am Lernset/Lehrwerk gespeichert und verändert nicht automatisch die globale Sense-Definition.
5. **Globale Synonyme sind bewusst.** Nur als echte Synonyme bestätigte Varianten werden in `sense.translations[]` übernommen.
6. **Mehrdeutiger Abruf braucht einen Cue.** Wenn das Fremdwort mehrere Senses besitzt, zählt Fremdsprache → Bedeutung im adaptiven Lernen nur mit disambiguierendem Kontext/Wortart. Fehlt ein Cue, wechselt die App auf die eindeutige Richtung Bedeutung → Fremdwort.
7. **Sense-Identität erhält Diakritika.** Die interne Bedeutungsnormalisierung entfernt keine Umlaute/Akzente; `schön` und `schon` sind nicht identisch.
8. **ISBN/Unit referenzieren dieselben Senses.** Lehrwerke kopieren keine fachlichen Bedeutungen, sondern verknüpfen sie mit Buchabschnitt, Reihenfolge und Overrides.

## 3. Importregeln

### Foto/OCR

Wenn ein Lexem bereits existiert, die erkannte deutsche Formulierung aber keinem bekannten Sense exakt entspricht, muss vor dem Import gewählt werden:

- **Gleiche Bedeutung wie …** → vorhandene `senseId`; die erkannte Formulierung wird Schulbuch-Override.
- **Neue Bedeutung** → neuer Sense und eigener Lernstand.

Die App entscheidet diesen fachlichen Unterschied nicht stillschweigend.

### CSV

CSV v0.9.13 trennt:

- `translation`: Schulbuch-/Setform
- `senseTranslation`: kanonische Bedeutung
- `senseAliases`: globale Synonyme
- `acceptedTranslations`: set-spezifische akzeptierte Antworten
- `partOfSpeech`: optionale Wortart

Dadurch bleibt Export → Import semantisch stabil.

## 4. Migration

Alte `translation + translations[]`-Daten werden als **eine** Bedeutung mit Synonymen migriert, nicht als mehrere Senses.

Der frühe v0.9.12-Stand konnte unbenutzte Synonyme irrtümlich in getrennte Senses aufteilen. v0.9.13 führt eine konservative Reparatur aus: Nur unmittelbar gemeinsam erzeugte, noch untrainierte und metadatenfreie Senses werden wieder als Aliase zusammengeführt. Bereits fachlich bearbeitete/gelernte Bedeutungen werden nicht destruktiv automatisch verschmolzen.

## 5. Pädagogische Begründung

González-Fernández & Webb (2024) fanden, dass das Lernen einer weiteren Bedeutung eines bereits bekannten L2-Wortes ähnlich anspruchsvoll sein kann wie das Lernen der Primärbedeutung eines unbekannten Wortes. Das stützt getrennte Lernstände pro Sense.

Yang, Liang & Chen (2023) zeigten einen Einfluss der Wortart auf das Lernen mehrdeutiger L2-Wörter. Deshalb ist Wortart optionale Sense-Metadaten und kann als Disambiguierungs-Cue dienen.

Li et al. (2026) fanden, dass Flashcards und kontextualisierte Übungen unterschiedliche Vorteile im Lernprozess haben, ohne einen stabilen Langzeitvorteil einer Methode über eine Woche zu zeigen. Deshalb bleibt Retrieval der Kern; Kontext dient bei Mehrdeutigkeit als fachlicher Cue, nicht als Ersatz für Abruf.

Quellen:
- https://doi.org/10.1017/S0272263124000317
- https://doi.org/10.1016/j.jneuroling.2023.101157
- https://doi.org/10.1016/j.actpsy.2026.107736

## 6. Abnahmekriterien

Der CI-Smoke-Test `scripts/vokabeltrainer-sense-smoke.mjs` prüft mindestens:

- Legacy-Synonyme werden zu einem Sense migriert.
- Zwei echte Bedeutungen desselben Lexems erzeugen zwei getrennte Lernstände.
- Eine explizit einem bestehenden Sense zugeordnete Schulbuchform erzeugt keinen neuen Sense.
- Sense-Identität unterscheidet Umlaute.
- Mehrdeutiger Bedeutungsabruf ohne Cue wird erkannt.
- Kontext kann einen mehrdeutigen Sense disambiguieren.
- v0.9.12-Alias-Splits werden nur im konservativen Reparaturfall zusammengeführt.

## 7. Bewusste Nicht-Features in v1

Keine Pflichtklassifikation `Polysemie vs. Homonymie`. Die aktuelle Evidenz rechtfertigt nicht die zusätzliche Eingabelast für Kinder/Eltern. Falls spätere Forschung oder Lehrkraftanforderungen einen konkreten Lernnutzen zeigen, kann dies als Sense-Metadatum ergänzt werden.
