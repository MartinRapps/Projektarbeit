# Themenfindung & Scope-Entwicklung – Projektarbeit (PA)

> **Status:** Phase 2 – Eliminierung abgeschlossen, Vertiefung auf 4 → 3 Favoriten
> 
> Aktualisiert am: 29.04.2026, 16:15 Uhr

---

## Zusammenfassung deiner Antworten

| Frage | Antwort |
|---|---|
| Ausgeschlossen | ❌ T3 Hitze-Gefahren-Karte, ❌ T4 Klimadashboard |
| Betreuer | Wilkening (bevorzugt) oder Müller (auch gut). Wenzel eher nicht. |
| Skyfall-GS Daten | Kein direkter Zugang, aber Dozent hat Daten & Kontakt zur Stadt. Überzeugungsarbeit nötig. |
| SENSOTO Daten | 20 Stationen, max. 5 Jahre. Evtl. auch Stadtdaten / Open Data. |
| PA-BA-Kopplung | ✅ Ja, definitiv gewünscht. Auch Kopplung mit Arbeitgeber möglich. |
| Hardware | Photogrammetrie-Labor (128GB RAM, vermutlich starke GPU). Sonst Server. |
| Zeitrahmen | Möglichst bald starten. Urlaub Mitte August. |
| Bearbeitung | Alleine (1 Bearbeiter → 15-25 Seiten) |

---

## Zeitplanung – Klärung der 3-Monate-Frage

> [!IMPORTANT]
> Die **3 Monate sind die maximale Brutto-Bearbeitungszeit**, nicht die Mindestdauer! Du kannst jederzeit **vorher abgeben**. Die Verteidigung wird dann ca. 3-4 Wochen nach Abgabe angesetzt.

### Szenario-Planung

| Szenario | Anmeldung | Abgabe | Verteidigung | Urlaub Mitte Aug |
|---|---|---|---|---|
| **A: Schnell** | Mitte Mai 2026 | Mitte Juli 2026 | Anfang/Mitte Aug | ✅ Kein Konflikt |
| **B: Komfortabel** | Anfang Juni 2026 | Anfang August 2026 | Ende Aug / Anfang Sep | ⚠️ Knapp |
| **C: Sicher** | Anfang Juni 2026 | Ende September 2026 | Oktober 2026 | ✅ Kein Konflikt |

> [!TIP]
> **Szenario A ist realistisch**, wenn du jetzt mit der Themenfindung und Vorarbeit startest (Literaturrecherche, Datenakquise) und die PA dann nach Anmeldung in ca. 6-8 Wochen abschließt. Du darfst vor Anmeldung schon Vorarbeiten leisten – du darfst es nur nicht als offizielle Bearbeitungszeit angeben.
>
> **Empfehlung:** Starte die Vorarbeit jetzt, melde offiziell Mitte/Ende Mai an, und ziele auf Abgabe **Mitte Juli**. Dann hast du Mitte August frei.

---

## Verbleibende 4 Themen – Aktualisierte Analyse

Nach Eliminierung von T3 und T4 bleiben:

| # | Thema | Betreuer-Fit | Daten-Situation |
|---|---|---|---|
| T1 | **15-Minuten-Stadt** (Valhalla + OSM) | 🟢 Wilkening (GIS, WebApp) | 🟢 Alles Open Source/Data |
| T2 | **Mikroklima Würzburg** (SENSOTO + Interpolation) | 🟡 Wilkening oder Müller | 🟡 20 Stationen vorhanden, Open Data ergänzbar |
| T5 | **Skyfall-GS** (Schrägluftaufnahmen 5cm) | 🟢 Müller (CV/Photogrammetrie) | 🟠 Überzeugungsarbeit nötig |
| T6 | **Gaussian Splatting vs. Punktwolke** | 🟢 Müller (CV/3D/ML) | 🟡 Eigene Daten + öffentliche Benchmarks |

### Detaillierte Neubewertung mit deinem Profil

#### T1 – 15-Minuten-Stadt `15MIN` → ⭐ Sehr solide Wahl

**Warum es passt:**
- Du kannst sofort starten – **keine Datenabhängigkeit** (OSM + Valhalla = 100% FOSS)
- Perfekter PA-BA-Split: PA = Methodik + Konzept + PoC, BA = Full-Stack-Tool
- Wilkening ist idealer Betreuer (WebGIS, Geodatenquellen-Vergleich)
- **Kopplung mit Arbeitgeber** denkbar? (Planungstool für Kommunen = kommerzielles Potenzial)
- Gesellschaftlich hochrelevant, gut publizierbar

**PA-Scope konkret (4 Wochen):**
1. Literaturreview: 15-Minuten-Stadt-Konzept, bestehende Tools, Erreichbarkeitsanalysen
2. Methodischer Entwurf: Rasterbasierte Erreichbarkeitsberechnung mit Valhalla-Isochrone-API
3. Datenmodell: OSM-POI-Kategorisierung (Supermarkt, Apotheke, Schule, etc.)
4. Bewertungsschema: Ampelsystem (10/15/20 min) + Windrose-Konzept
5. Proof-of-Concept: Eine Beispielberechnung für einen Stadtteil Würzburgs
6. UX/UI-Konzept: Mockups der Web-Applikation

**Risiko:** Eher geringe wissenschaftliche Tiefe im Vergleich zu T5/T6. Könnte als "nur eine Web-App" wahrgenommen werden → muss durch saubere Methodik aufgewertet werden.

---

#### T2 – Mikroklima Würzburg `MIKRO` → ⭐ Solide, aber Daten-Risiko

**Warum es passt:**
- Lokaler Bezug zu Würzburg = hohe Praxisrelevanz
- 20 Stationen sind ein guter Ausgangspunkt
- Interpolation + Visualisierung = GIS-Kernkompetenz
- Wilkening oder Müller als Betreuer möglich

**PA-Scope konkret (4 Wochen):**
1. Literaturreview: Urban Heat Island-Effekt, Interpolationsverfahren (Kriging, IDW, Co-Kriging mit Landnutzung)
2. Datenanalyse: Explorative Analyse der 20 SENSOTO-Stationen
3. Methodischer Entwurf: Welches Interpolationsverfahren passt zu dieser Stationsdichte?
4. Konzept: Integration von Zusatzvariablen (Landnutzung, Versiegelungsgrad, Gebäudehöhe)
5. Proof-of-Concept: Interpolierte Karte für einen Zeitpunkt/Tag
6. Konzept für Web-Dashboard

**Risiko:** 
- 20 Stationen könnten für manche Interpolationsverfahren **zu wenig** sein
- Datenlücken/-qualität unklar
- Abgrenzung zum bestehenden SENSOTO-Dashboard?

> [!WARNING]
> Bevor du T2 wählst, solltest du **prüfen**: Wie sieht die Datenqualität der 20 Stationen aus? Gibt es systematische Lücken? 20 Punkte in einer Stadt wie Würzburg könnten für eine flächendeckende Interpolation grenzwertig sein.

---

#### T5 – Skyfall-GS `SKYFALL` → ⭐⭐ Starke Wahl, aber Daten-Unsicherheit

**Warum es passt:**
- Hochauflösend (5cm DOP!) = einzigartiger Datensatz
- Photogrammetrie-Labor ist perfekt dafür
- Müller ist idealer Betreuer
- PA-BA-Kopplung exzellent

**PA-Scope konkret (4 Wochen):**
1. Literaturreview: Schrägluftaufnahmen in der Stadtmodellierung, Skyfall-GS-Methodik
2. Datenaufbereitung: Analyse der verfügbaren Bilddaten, Kameramodell, Georeferenzierung
3. Verfahrensvergleich (Konzept): Structure-from-Motion, Dense Matching, Mesh-Generierung
4. Qualitätskriterien: Geometrische Genauigkeit, Vollständigkeit, Level of Detail
5. Pilotversuch: 3D-Rekonstruktion eines kleinen Testgebiets
6. Versuchsdesign für die BA

**Risiko:**
- ⚠️ **Datenzugang ist nicht gesichert!** Wenn der Dozent die Daten nicht freigibt, fällt das Thema komplett weg.
- Überzeugungsarbeit = Unsicherheit im Zeitplan

---

#### T6 – Gaussian Splatting vs. Punktwolke `GAUSS` → ⭐⭐⭐ Stärkste Wahl

**Warum es passt:**
- **Deckt alle 5 Interessen ab** (Geo, KI, CV, FE, AppDev)
- Höchste wissenschaftliche Tiefe und Aktualität
- Gaussian Splatting ist **2024/2025 das Trendthema** in 3D-Rekonstruktion
- Photogrammetrie-Labor mit starker GPU ist perfekte Infrastruktur
- Müller ist idealer Betreuer (passt zu seinen angebotenen Themen)
- PA-BA-Kopplung ist naturgegeben: Konzept → Evaluation
- **Unabhängig von Skyfall-Daten durchführbar** (öffentliche Benchmark-Datensätze oder eigene Aufnahmen)

**PA-Scope konkret (4 Wochen):**
1. **Literaturreview:** 3DGS (Kerbl et al. 2023), NeRF, SfM/MVS-Pipelines, Mesh-Rekonstruktion
2. **Kriterienkatalog** entwickeln:
   - Geometrische Genauigkeit (RMSE, Hausdorff-Distanz)
   - Visuelle Qualität (PSNR, SSIM, LPIPS)
   - Objekterkennbarkeit (manuell + automatisiert/ML)
   - Einsatzbereiche (Stadtplanung, BIM, Gaming, Kulturerbe)
   - Symbiotische Nutzung (Kombination beider Verfahren)
3. **Versuchsdesign:** Testdatensatz definieren, Pipeline-Architektur, Ablaufplan
4. **Pilot:** Kleiner Testlauf mit öffentlichem Datensatz → Proof-of-Concept
5. **Konzept BA:** Vollständiges Evaluationsdesign

**Risiko:**
- Rechenzeit für Gaussian Splatting kann hoch sein → Lab-Zugang muss gesichert sein
- Vergleich muss fair und methodisch sauber aufgebaut werden

> [!TIP]
> **T6 kann T5 einschließen, aber nicht umgekehrt.** Wenn du T6 wählst, kannst du in der BA die Skyfall-GS-Daten als einen von mehreren Testdatensätzen verwenden – falls du bis dahin Zugang hast. Falls nicht, nutzt du andere Daten. Das macht T6 **risikoresistenter** als T5.

---

## Empfehlung: Auf 3 Favoriten filtern

Basierend auf deinem Profil schlage ich vor, **T2 (Mikroklima) als dritte Elimination** in Betracht zu ziehen, aber das hängt von dir ab:

### Option A: Eher Richtung 3D/CV/KI

| Rang | Thema | Begründung |
|---|---|---|
| 🥇 | T6 – Gaussian Splatting | Maximale Interessenabdeckung, risikoresistent, Trendthema |
| 🥈 | T5 – Skyfall-GS | Einzigartiger Datensatz, aber Datenrisiko |
| 🥉 | T1 – 15-Min-Stadt | Solides Backup, sofort startbar, Wilkening als Betreuer |

→ Eliminiert: T2 (Datenrisiko, geringere Interessenabdeckung)

### Option B: Eher Richtung GIS/Anwendung/Klima

| Rang | Thema | Begründung |
|---|---|---|
| 🥇 | T1 – 15-Min-Stadt | Sofort startbar, Wilkening, gesellschaftlich relevant |
| 🥈 | T2 – Mikroklima | Lokaler Bezug, Daten vorhanden |
| 🥉 | T6 – Gaussian Splatting | Als Backup aus dem CV-Bereich |

→ Eliminiert: T5 (zu hohes Datenrisiko als Standalone)

---

## Dein nächster Schritt (heute/morgen)

> [!IMPORTANT]
> **Bitte beantworte diese 3 Fragen**, damit wir morgen die Tiefenrecherche starten können:

1. **Option A oder B?** Tendierst du eher Richtung 3D/CV/KI oder GIS/Anwendung?
2. **Arbeitgeber-Kopplung:** Was macht dein Arbeitgeber? Welches Thema hat dort Anknüpfungspunkte?
3. **Skyfall-Daten:** Könntest du deinen Dozenten **diese Woche** fragen, ob die Daten für eine PA/BA nutzbar wären? Das würde die Entscheidung deutlich vereinfachen.
