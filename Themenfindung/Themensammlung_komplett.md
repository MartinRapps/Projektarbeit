# Themensammlung Projektarbeit – Konsolidierte Übersicht

> Konsolidiert aus implementation_plan v1–v4 + Themen T7, T8
>
> Stand: 04.05.2026

---

## Persönliche Interessen

- Geoinformatik
- Künstliche Intelligenz
- Computer Vision
- Fernerkundung
- Anwendungsentwicklung

## Rahmenbedingungen PA

| Parameter | Wert |
|---|---|
| Netto-Bearbeitungszeit | 4 Wochen (Vollzeit) |
| Brutto-Bearbeitungszeitraum | max. 3 Monate |
| Seitenumfang (1 Bearbeiter) | ca. 15–25 Seiten (reiner Text) |
| PA-BA-Kopplung | Empfohlen (PA = Konzept, BA = Realisierung) |
| Bewertung | Inhalt, Wissenschaftlichkeit, Selbstständigkeit, Kreativität, Darstellung |
| Betreuer-Präferenz | Müller (Erstprüfer) + Wilkening (Zweitprüfer) |
| Zeitwunsch | Möglichst bald starten, Urlaub Mitte August → Abgabe idealerweise Mitte Juli |

---

## Gesamtübersicht aller 7 Themen

| # | Thema | Kürzel | Status |
|---|---|---|---|
| T1 | 15-Minuten-Stadt – Planungstool (Valhalla + OSM) | `15MIN` | ✅ Backup-Thema |
| T2 | Mikroklima-Karte Würzburg (SENSOTO-Daten) | `MIKRO` | 🟡 Offen |
| T3 | Hitze-Gefahren-Karte DE (Wetbulb etc.) | `HITZE` | ❌ Eliminiert (Scope-Explosion) |
| T4 | Klimadashboard (à la klimadashboard.de) | `KLIMA` | ❌ Eliminiert (geringe Eigenleistung) |
| T5 | Skyfall-GS – Schrägluftaufnahmen 3DGS | `SKYFALL` | ✅ **Hauptthema (kombiniert mit T6)** |
| T6 | Gaussian Splatting vs. Punktwolke – Vergleich | `GAUSS` | ✅ **Hauptthema (kombiniert mit T5)** |
| T7 | Historische Luftbilder + SAM3 Segmentierung | `HISTSAM` | 🆕 Neu – zu bewerten |
| T8 | Bundesweite Geodaten-Plattform | `GEOPORT` | 🆕 Neu – bewertet (⚠️) |

### Bewertungsmatrix (alle 7 Themen)

| Kriterium | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Interessenabdeckung** (Geo, KI, CV, FE, AppDev) | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Datenverfügbarkeit** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Scope-Kontrollierbarkeit** (4 Wochen PA) | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **PA-BA-Kopplung** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Wissenschaftliche Tiefe** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Gesellschaftliche Relevanz** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## T1 – 15-Minuten-Stadt `15MIN`

**Idee:** Automatisiertes Planungstool für Städte und Kommunen, das in einem 25m × 25m Raster die Versorgungssicherheit alltäglicher Dienste bewertet.

**Technologie:**
- FOSSGIS Valhalla für Routing (Isochronen-API)
- OpenStreetMap für POIs (Supermärkte, Apotheken, Schulen, etc.)
- Ampelsystem: rot (>20 min) → gelb (15 min) → grün (≤10 min)
- Windrose-Visualisierung mit den einzelnen Versorgungsbereichen

**PA-Scope (4 Wochen):**
1. Literaturreview: 15-Minuten-Stadt-Konzept, bestehende Tools, Erreichbarkeitsanalysen
2. Methodischer Entwurf: Rasterbasierte Erreichbarkeitsberechnung mit Valhalla-Isochrone-API
3. Datenmodell: OSM-POI-Kategorisierung
4. Bewertungsschema: Ampelsystem + Windrose-Konzept
5. Proof-of-Concept: Beispielberechnung für einen Stadtteil Würzburgs
6. UX/UI-Konzept: Mockups der Web-Applikation

**BA-Scope:** Vollständige Implementierung, Skalierung, Validierung mit Kommunen

**Stärken:**
- Exzellente Datenverfügbarkeit (OSM + Valhalla = 100% FOSS)
- Sofort startbar, keine Datenabhängigkeit
- Hohe gesellschaftliche Relevanz
- Wilkening ist idealer Betreuer (GIS, WebApp)

**Risiken:**
- Eher geringe wissenschaftliche Tiefe → könnte als "nur eine Web-App" wahrgenommen werden
- Routing-Berechnungen auf 25m-Raster können rechenintensiv werden

**Betreuer-Fit:** 🟢 Wilkening (GIS, WebApp)

**Status:** ✅ Backup-Thema (sofort startbar, falls Hauptthema nicht klappt)

---

## T2 – Mikroklima-Karte Würzburg `MIKRO`

**Idee:** Berechnung und Interpolation von Temperaturunterschieden in Würzburg basierend auf SENSOTO-Sensorstationen. Erstellung einer Mikroklima-Karte und ggf. Web-Dashboard.

**Datengrundlage:**
- 20 SENSOTO-Stationen (max. 5 Jahre Daten, oft kürzer)
- Ggf. Daten der Stadt Würzburg oder Open Data
- Referenz: Klimadashboard der Stadt Würzburg

**PA-Scope (4 Wochen):**
1. Literaturreview: Urban Heat Island-Effekt, Interpolationsverfahren (Kriging, IDW, Co-Kriging)
2. Datenanalyse: Explorative Analyse der 20 Stationen
3. Methodischer Entwurf: Passendes Interpolationsverfahren für diese Stationsdichte
4. Konzept: Integration von Zusatzvariablen (Landnutzung, Versiegelungsgrad, Gebäudehöhe)
5. Proof-of-Concept: Interpolierte Karte für einen Zeitpunkt
6. Konzept für Web-Dashboard

**BA-Scope:** Implementierung der Interpolation, Web-Karte, Validierung

**Stärken:**
- Lokaler Bezug zu Würzburg = hohe Praxisrelevanz
- Klimarelevanz, gesellschaftlich wichtig
- Kombination aus Sensorik und GIS

**Risiken:**
- 20 Stationen könnten für flächendeckende Interpolation **zu wenig** sein
- Datenlücken/-qualität unklar
- Abgrenzung zum bestehenden SENSOTO-Dashboard?

**Betreuer-Fit:** 🟡 Wilkening oder Müller

**Status:** 🟡 Offen – nicht eliminiert, aber nicht favorisiert

---

## T3 – Hitze-Gefahren-Karte Deutschland `HITZE` ❌

**Idee:** Erstellung einer Hitze-Gefahren-Karte von Deutschland basierend auf Wetbulb-Temperature, Trinkstationen, medizinischer Versorgung, öffentlichen Parks (Orte mit relativ niedriger Temperatur), Naherholungsgebieten.

**PA-Scope-Idee:** Konzept + Fokus auf 1-2 Indikatoren für eine Pilotregion

**BA-Scope-Idee:** Erweiterung auf alle Indikatoren + größeren Raum

**Stärken:**
- Topaktuell (Klimawandel), hohe gesellschaftliche Relevanz
- Multi-variater Ansatz

**Risiken:**
- **Scope-Explosion!** Zu viele Dimensionen für eine PA
- Schwierige bundesweite Datenlage
- Wetbulb-Temp + Trinkstationen + med. Versorgung + Parks + Naherholung = nicht handhabbar

**Status:** ❌ **Eliminiert** – Scope-Explosion, nicht kontrollierbar in 4 Wochen

---

## T4 – Klimadashboard `KLIMA` ❌

**Idee:** Regionales Klimadashboard nach Vorbild von klimadashboard.de. Visualisierung von Emissionsdaten und Klimaindikatoren für eine Region.

**Referenz:** https://klimadashboard.de/regions/69ccaeec-0ddb-4faf-b846-4a0a03e57b1e#emissions

**PA-Scope-Idee:** Anforderungsanalyse, Konzept, Datenmodell, Prototyp-Mockups

**BA-Scope-Idee:** Implementierung des Dashboards

**Stärken:**
- Orientierung an existierendem Produkt, klare Zielgruppe

**Risiken:**
- Abgrenzung zu existierenden Dashboards unklar
- Wissenschaftliche Eigenleistung fraglich
- Geringe Interessenabdeckung (nur AppDev + Geo)

**Status:** ❌ **Eliminiert** – zu geringe wissenschaftliche Eigenleistung, schwache Interessenabdeckung

---

## T5 – Skyfall-GS Schrägluftaufnahmen `SKYFALL`

**Idee:** Nutzung der Skyfall-GS Pipeline (frei verfügbar auf HuggingFace + GitHub) zur Verarbeitung von Schrägluftbildern. Skyfall-GS ist optimiert für Schrägluft- und Satellitenbilder und fokussiert auf die Verbesserung der Datenqualität und Erstellung optisch ansprechender Splats.

**Datengrundlage:**
- Schrägluftbilder der Stadt Würzburg (5cm DOP, über Dozenten anfragbar)
- Öffentliche Benchmark-Datensätze
- Eigene Drohnenaufnahmen (Uni-Drohne/Campus)

**PA-Scope (4 Wochen) – als Teil von T5+T6 kombiniert:**
1. Literaturreview: Schrägluftaufnahmen in der Stadtmodellierung, Skyfall-GS-Methodik
2. Datenaufbereitung: Analyse der Bilddaten, Kameramodell, Georeferenzierung
3. Verfahrensvergleich (Konzept): SfM, Dense Matching, Mesh-Generierung
4. Qualitätskriterien: Geometrische Genauigkeit, Vollständigkeit, LoD
5. Pilotversuch: 3D-Rekonstruktion eines kleinen Testgebiets
6. Versuchsdesign für die BA

**BA-Scope:** Durchführung der vollständigen Rekonstruktion, quantitative Auswertung

**Stärken:**
- Hochauflösend (5cm DOP) = einzigartiger Datensatz
- Pipeline frei verfügbar (HuggingFace/GitHub)
- Photogrammetrie-Labor ist perfekt dafür (128GB RAM, starke GPU)
- Müller ist idealer Betreuer
- PA-BA-Kopplung exzellent

**Risiken:**
- Zugang zu den Würzburger Schrägluftbildern muss über Dozent geklärt werden
- LoD / Aufnahmeentfernung muss noch entschieden werden (Stadtübersicht >200m vs. Gebäudeebene 50-200m vs. Objektebene <50m)

**Betreuer-Fit:** 🟢 Müller (CV/Photogrammetrie)

**Status:** ✅ **Hauptthema (kombiniert mit T6)**

---

## T6 – Gaussian Splatting vs. Punktwolke `GAUSS`

**Idee:** Vergleichende Evaluation von 3D Gaussian Splatting mit klassischer photogrammetrischer 3D-Rekonstruktion (SfM → MVS → Mesh) anhand eines systematischen Kriterienkatalogs.

**Die 5 Evaluationsdimensionen:**

| Dimension | Kriterien | Messmethode |
|---|---|---|
| **D1: Geometrische Genauigkeit** | RMSE, Hausdorff-Distanz, Maßstabstreue, Georeferenzierung | Vergleich mit Referenzdaten (Passpunkte, GNSS) |
| **D2: Visuelle Qualität** | PSNR, SSIM, LPIPS, subjektive Bewertung | Novel View Synthesis Metriken |
| **D3: Objekterkennbarkeit** | Manuelle Identifizierbarkeit von Objekten | Nutzerstudie / Experteneinschätzung |
| **D4: ML-Objekterkennung** | Erkennungsrate trainierter Modelle auf 3D-Daten | YOLOv8 / Mask R-CNN auf gerenderten Views |
| **D5: Praxistauglichkeit** | Rechenzeit, Speicher, Skalierbarkeit, GIS-Import | Benchmarking auf Lab-Hardware |

**Querschnittsthema: Symbiotische Nutzung** – Können beide Verfahren kombiniert werden? (z.B. Gaussian Splat für schnelle Visualisierung + Mesh für Messung)

**PA-Scope (4 Wochen) – kombiniert mit T5:**
1. Literaturreview: 3DGS (Kerbl et al. 2023), NeRF, SfM/MVS, Mesh-Rekonstruktion
2. Kriterienkatalog entwickeln (5 Dimensionen)
3. Versuchsdesign: Testdatensatz, Pipeline-Architektur, Ablaufplan
4. Pilot: Testlauf mit öffentlichem Datensatz → Proof-of-Concept
5. Konzept BA: Vollständiges Evaluationsdesign

**BA-Scope:** Vollständige Vergleichsstudie auf mehreren Datensätzen, quantitative + qualitative Auswertung, Handlungsempfehlung

**Stärken:**
- **Höchste Interessenabdeckung** aller Themen (alle 5 Interessen)
- Trendthema 2024/2025 in der 3D-Rekonstruktion
- Photogrammetrie-Labor mit starker GPU
- Müller ist idealer Betreuer (passt zu seinen angebotenen Themen)
- Unabhängig von Skyfall-Daten durchführbar (öffentliche Benchmarks)

**Risiken:**
- Rechenzeit kann hoch sein → Lab-Zugang sichern
- Vergleich muss fair und methodisch sauber sein

**Betreuer-Fit:** 🟢 Müller (CV/3D/ML)

**Status:** ✅ **Hauptthema (kombiniert mit T5)**

### T5+T6 Kombination – Das Hauptthema

**Warum zusammen?** T5 liefert die **Datenbasis und den Use Case** (Schrägluftbilder), T6 liefert die **wissenschaftliche Methodik** (Vergleich). Getrennt fehlt jeweils die Hälfte.

**Arbeitstitel (Entwurf):**
> "Evaluation von 3D Gaussian Splatting im Vergleich zur klassischen Photogrammetrie am Beispiel urbaner Schrägluftbilder"

**Zentrale Herausforderung: Georeferenzierung**
- Für geodätische Nutzung unumgänglich
- Optionen: GCPs (nachträglich), RTK-Drohne (teuer), vorhandene Orientierung (Schrägluftbilder)
- "Wie lässt sich ein 3D Gaussian Splat geodätisch referenzieren?" → Forschungslücke!

**GIS-Integration:** ArcGIS Pro kann inzwischen GS importieren + Messungen. Open Source: Cesium, Potree, Three.js-Viewer, SuperSplat, Nerfstudio.

**PA-Gliederung:**

| Kap. | Inhalt | Seiten |
|---|---|---|
| 1 | Einleitung: Motivation, Problemstellung (Georeferenzierung!), Zielsetzung | 2-3 |
| 2 | Grundlagen: SfM/MVS/Mesh, 3DGS-Theorie, Skyfall-GS, Georeferenzierung | 4-5 |
| 3 | Stand der Forschung: Vergleichsstudien, Geo-Anwendungen, Forschungslücke | 3-4 |
| 4 | Methodik: Kriterienkatalog, Versuchsdesign, Georef.-Ansatz, GIS-Konzept | 4-5 |
| 5 | Proof-of-Concept: Pilotversuch, erste Ergebnisse | 3-4 |
| 6 | Fazit & Ausblick: Zusammenfassung, BA-Plan | 1-2 |
| | **Gesamt** | **~18-23** |

**Datenstrategie (kein Risiko):**

| Datenquelle | Verfügbarkeit | PA | BA |
|---|---|---|---|
| Öffentliche Benchmarks (Tanks & Temples, MipNeRF360) | 🟢 Sofort | ✅ PoC | ✅ Baseline |
| Eigene Drohnenaufnahmen (Campus) | 🟢 Jederzeit | ✅ Test | ✅ Haupt |
| Schrägluftbilder Würzburg (über Dozent) | 🟠 Zu klären | ❌ | ✅ Optional |

---

## T7 – Historische Luftbilder + SAM3 Segmentierung `HISTSAM` 🆕

**Idee:** Auswertung historischer Luftbilder aus dem Luftbilddatenarchiv der Landesvermessung Bayern mittels SAM3 (Segment Anything Model 3 von Microsoft). Testen der KI-gestützten Segmentierung auf alten Bildern zur Erkennung von Straßenstrukturen und Gebäuden/Dörfern. Darstellung der zeitlichen Entwicklung in einer Web-Anwendung.

**Technologie:**
- **SAM3** (Segment Anything Model 3, Microsoft) – KI-basiertes Segmentierungsmodell
- Historische Luftbilder aus dem Luftbilddatenarchiv der Landesvermessung Bayern (LDBV)
- Web-Anwendung zur Visualisierung der Entwicklung von Straßenstrukturen und Siedlungen über die Zeit

**Datengrundlage:**
- Luftbilddatenarchiv LDBV Bayern
- ⚠️ **Kostenproblem:** 30€ pro Luftbild! Nur realistisch, wenn ein ausgewählter Datensatz vom LDBV oder der Stadt Würzburg bereitgestellt wird

**PA-Scope (4 Wochen, vorläufig):**
1. Literaturreview: SAM/SAM2/SAM3, Segmentierung auf historischen Bildern, Change Detection
2. Datenakquise-Strategie: Anfrage LDBV/Stadt Würzburg für Beispieldatensatz
3. Konzept: Pipeline historisches Bild → SAM3-Segmentierung → Vektorisierung → Vergleich
4. Proof-of-Concept: SAM3 auf wenigen frei verfügbaren historischen Bildern testen
5. Web-App-Konzept: Zeitliche Entwicklungsvisualisierung (Slider, Overlay)
6. Versuchsdesign für die BA

**BA-Scope:** Vollständige Pipeline-Implementierung, Auswertung über mehrere Zeitschnitte, Web-App mit interaktiver Karte

**Stärken:**
- Hohe Interessenabdeckung (KI, CV, Geoinformatik, Fernerkundung, AppDev)
- SAM3 ist hochaktuelles KI-Thema
- Gesellschaftlich relevant (Stadtentwicklung, historische Dokumentation)
- Hervorragende PA-BA-Kopplung (PA = Konzept + Pilot, BA = Volle Umsetzung)
- Einzigartige Kombination: modernste KI auf historischem Material

**Risiken:**
- ⚠️ **Hauptrisiko: Datenkosten!** 30€/Bild → ohne Kooperation mit LDBV/Stadt Würzburg nicht finanzierbar
- Qualität historischer Bilder unklar (Kontrast, Auflösung, Verzerrung)
- SAM3-Performance auf historischen Bildern ungetestet → könnte schlecht funktionieren
- Georeferenzierung historischer Bilder ist eigenständige Herausforderung

**Betreuer-Fit:** 🟢 Müller (CV/KI) oder Wilkening (GIS/WebApp)

**Status:** 🆕 Neu – Bewertung steht aus. Datenzugang muss zuerst geklärt werden.

---

## T8 – Bundesweite Geodaten-Plattform `GEOPORT` 🆕

**Idee:** Webbasierte Plattform, die bundesweite Geobasisdaten und Open-Source-Geodaten aggregiert. Nutzer wählen über eine Bounding Box ihr Gebiet aus und erhalten die Daten in einem gewünschten Format (Konvertierung via Open-Source-ETL). Zusätzlich Upload-Funktion für neue Datenquellen mit Review-Prozess.

**Technologie:**
- **Frontend:** Web-Karte mit BBox-Zeichentool (Leaflet/OpenLayers)
- **Backend:** ETL-Pipeline mit GDAL/OGR, hale studio, oder PostGIS
- **Datenquellen:** WFS/WMS-Dienste der Länder, Open Data Portale, OSM
- **Upload & Review:** Nutzergenerierte Daten mit Qualitätsprüfung

**Datengrundlage:**
- Geobasisdaten der Länder (seit 2023 zunehmend Open Data)
- OpenStreetMap
- Weitere Open-Source-Geodaten (z.B. Copernicus, OpenData-Portale)

**PA-Scope (4 Wochen, vorläufig):**
1. Literaturreview: GDI-DE, SDI-Architekturen, Geodaten-Interoperabilität
2. Anforderungsanalyse: Nutzergruppen, Use Cases, Abgrenzung zu Geoportal.de
3. Konzept: System-Architektur, Datenmodell, ETL-Pipeline
4. Prototyp: BBox-Auswahl + Download für 1-2 Datensätze (1 Bundesland)
5. Review-Konzept: Workflow für nutzergenerierte Daten
6. Versuchsdesign für die BA

**BA-Scope:** Vollständige Implementierung, Skalierung auf mehrere Bundesländer, Review-System

**Stärken:**
- Echtes Problem: Geodaten in DE sind fragmentiert über 16+ Portale
- Hohe gesellschaftliche und praktische Relevanz
- Klares, greifbares Produkt
- FOSS-Stack verfügbar (GDAL, PostGIS, Leaflet)

**Risiken:**
- ⚠️ **Hauptrisiko: Scope-Explosion!** 16 Bundesländer × n Datensätze × Formatkonvertierung × Upload × Review
- ⚠️ **Abgrenzung**: Geoportal.de / GDI-DE existiert bereits → Mehrwert muss klar dargelegt werden
- ⚠️ **Wissenschaftliche Tiefe**: Eher Software-Engineering als Forschungsarbeit
- Heterogene APIs und Datenformate der Bundesländer
- FME ist nicht Open Source → Alternative: GDAL/OGR, hale studio

**Betreuer-Fit:** 🟡 Wilkening (WebApp/GIS), weniger Müller (CV/KI)

**Status:** 🆕 Neu – Bewertet. ⚠️ Scope und wissenschaftliche Tiefe problematisch in aktueller Form.

---

## Entscheidungsstand (04.05.2026)

```
T3 ❌ Eliminiert (Scope-Explosion)
T4 ❌ Eliminiert (geringe Eigenleistung)

T5+T6 ⚠️ HAUPTTHEMA – muss heruntergebrochen werden (Skyfall-GS/Schrägluft unrealistisch)
 T6b  ✅ Reduzierte Variante: Reiner Vergleich 3DGS vs. Punktwolke + opt. Segmentierung
T1    ✅ BACKUP (15-Minuten-Stadt, sofort startbar)

T2    🟡 Offen (Datenrisiko, aber möglich)
T7    🆕 Neu (SAM3 + hist. Luftbilder – Datenkosten klären!)
T8    🆕 Bewertet – ⚠️ Scope-Explosion & geringe wiss. Tiefe in aktueller Form
```

### Nächste Schritte

1. **Entscheidung treffen:** T6b (reduzierter 3DGS-Vergleich) oder T1 (15-Min-Stadt) als Hauptthema
2. **Falls T6b:** Alleinstellungsmerkmal definieren (z.B. Punktwolken-Segmentierung als Zusatzdimension)
3. **Falls T8 weiterverfolgt:** Scope radikal auf „Geodaten-Quality-Review mit ML“ einschränken
4. **Dozent kontaktieren:** Thema besprechen, Betreuer-Fit klären
5. **Nach Entscheidung:** Forschungsfrage finalisieren → Exposé schreiben
