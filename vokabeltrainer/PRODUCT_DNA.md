# Vokabeltrainer – Product DNA

Stand: 20.09.2026

Diese Prinzipien sind die verbindliche Leitlinie für Produktentscheidungen vor und nach v1.
Neue Features werden gegen diese DNA geprüft. Wenn ein Wunsch davon abweicht, soll der
Konflikt transparent benannt und – soweit sinnvoll – mit aktueller Lern-, UX- oder
Barrierefreiheitsforschung gegengeprüft werden.

## Die 12 Prinzipien

1. **Lernwirkung vor Featuremenge**
   Jede Funktion muss dem Lernen, der Orientierung oder der Motivation dienen. Kein Feature
   nur um seiner selbst willen.

2. **Aktiver Abruf ist der Kern**
   Retrieval Practice ist der wichtigste Lernmechanismus. Wiedererkennen, Zuhören,
   Vokabeldusche und Wortblitz sind Unterstützung, aber kein Beweis für Beherrschung.

3. **Verteiltes Lernen statt kurzfristigem Pauken**
   Spacing und Successive Relearning bestimmen Wiederholungen. Ein Wort gilt erst nach
   erfolgreichen Abrufen über mehrere Tage als nachhaltig gemeistert.

4. **Feedback direkt nach dem Abruf**
   Fehler werden konkret rückgemeldet und später erneut abgefragt. Falsche Antworten führen
   zu neuer Lerngelegenheit, nicht zu Bestrafung.

5. **Mastery bleibt fachlich und konservativ**
   XP, Legion/Kampagne und Belohnungen sind strikt vom fachlichen Fortschritt getrennt.
   100 % bedeutet: nach den Kriterien der App nachhaltig gemeistert, nicht objektiv
   'für immer gelernt'.

6. **Tagesziel beantwortet: Was muss ich heute lernen?**
   Testdatum, Testumfang, fällige Wiederholungen und schwache Wörter steuern das Tagespensum.
   Kurze, realistische Einheiten haben Vorrang vor langen Sessions.

7. **Neue Wörter im Kontext, Wiederholung gemischt**
   Erstaneignung respektiert soweit sinnvoll Buch-/Unit-Reihenfolge und Zusammenhang.
   Wiederholung mischt bewusst, damit kein reines Reihenfolgenlernen entsteht.

8. **LRS und Barrierefreiheit sind Teil des Grunddesigns**
   Ruhige Oberfläche, gut lesbare Sans-Serif-Schrift, ausreichende Größe/Abstände,
   reduzierte Ablenkung, kurze Einheiten, Audio und multisensorische Optionen.
   Keine unbewiesenen 'Wunderschriften' oder Zeitdruck als Lernprinzip.

9. **Lernen fokussiert, Motivation außen herum**
   Während des Abrufs: möglichst wenig Ablenkung.
   Abenteuer, Legion/Kampagne, XP und Belohnungen: vor oder nach der Lernsequenz.
   Gamification darf Aufmerksamkeit nicht vom Lerninhalt wegziehen.

10. **Globale Wissensbasis, getrennte Bedeutungen**
    Ein Lexem wird global gespeichert, Bedeutungen/Senses werden getrennt geführt.
    Lernfortschritt hängt an der Bedeutung und am Lernenden, nicht nur an der Zeichenfolge.
    Schulbuchform und akzeptierte Antworten bleiben set-/sense-spezifisch.

11. **Sprachen sind fachlich eigenständige Module**
    Englisch, Latein und später Französisch teilen technische Grundlagen, aber
    sprachspezifische Lernanforderungen werden explizit modelliert. Lateinische Formen,
    französische Akzente usw. werden nicht in ein Englisch-Schema gezwängt.

12. **Evidenz vor Gewohnheit**
    Größere Produktentscheidungen werden regelmäßig gegen aktuelle Lernforschung,
    UX-/Cognitive-Load-Forschung und Barrierefreiheitsstandards geprüft.
    Wenn Produktwunsch und Evidenz kollidieren, wird der Zielkonflikt offengelegt.

---

## Rollenmodell

### Kind
Ziel: lernen, nicht administrieren.

- Heute: eine klare Hauptaufgabe
- Lernmodus: fokussierter Abruf
- Fortschritt: verständlich und motivierend
- Kampagne/Belohnung: ergänzend
- nur aktive Fremdsprachen sichtbar
- keine unnötigen Verwaltungsfunktionen

### Eltern
Ziel: Orientierung, Unterstützung und Organisation – keine Überwachung.

Dashboard soll insbesondere beantworten:

- Ist das Kind für den nächsten Test auf Kurs?
- Was ist noch offen?
- Welche Vokabeln/Bedeutungen sind instabil?
- Wo liegen Fehlerarten: Abruf, Schreibung, Hören, Kontext, Grammatik?
- Welche Lernsets/Units sind aktiv?
- Wie entwickelt sich nachhaltige Mastery?
- Welche Testchecks wurden durchgeführt?
- Welche Schulnoten wurden manuell hinterlegt?
- Welche Lehrwerke/ISBNs sind zugeordnet?
- LRS- und Profileinstellungen
- Import/Backup/Lehrwerkverwaltung

Darstellung bevorzugt aggregiert und handlungsorientiert, nicht als minutengenaue
Verhaltensüberwachung.

### Lehrkraft
Ziel: fachlich relevante Information zu Lektionen und Lernstoff.

Lehrkraftbereich soll perspektivisch liefern:

- Lehrwerk / ISBN / Ausgabe
- Unit / Theme / Lektion
- Vokabelliste und Reihenfolge
- erwartete Schulbuchform
- akzeptierte Bedeutungsvarianten
- ggf. Grammatik-/Forminformationen
- Umfang eines Tests oder einer Lektion
- anonymisierte bzw. freigegebene Lernschwierigkeiten auf Wort-/Lektionenebene

Persönliche Lerndaten, LRS-Status oder individuelle Leistungsdaten werden einer Lehrkraft
nicht automatisch zugänglich gemacht. Solche Daten benötigen eine bewusste Freigabe.

---

## Architekturprinzip für Rollen

Keine drei getrennten Datenwelten.

Eine gemeinsame Datenbasis:
- Lexem
- Sense/Bedeutung
- Lehrwerk/ISBN
- Unit/Lektion
- Lernset
- persönlicher Lernstand

Darauf drei unterschiedliche Views:
- Kind-View
- Eltern-View
- Lehrkraft-View

So bleiben Daten konsistent und die Oberfläche kann je Rolle radikal vereinfacht werden.

## Prüffrage für jedes neue Feature

1. Verbessert es nachweislich Lernen, Orientierung oder Motivation?
2. Erhöht es kognitive Last während des Abrufs?
3. Verfälscht es Mastery oder Lernfortschritt?
4. Ist es mit LRS/Barrierefreiheit vereinbar?
5. Gehört es in Kind-, Eltern- oder Lehrkraftbereich?
6. Ist die Datenstruktur global wiederverwendbar?
7. Gibt es aktuelle Forschung, die unsere Annahme bestätigt oder widerspricht?
