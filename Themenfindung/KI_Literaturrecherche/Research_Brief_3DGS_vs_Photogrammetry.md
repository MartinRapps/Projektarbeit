# Research Brief: 3D Gaussian Splatting vs. Klassische Photogrammetrie – Drohnenbasierte Pipeline-Evaluation

> **Zielgruppe:** Autonome Research-AI  
> **Auftraggeber:** Student, B.Sc. Geoinformatik, THWS Würzburg  
> **Kontext:** Projektarbeit (PA, 4 Wochen netto) + anschließende Bachelorarbeit (BA, 10 Wochen netto)  
> **Datum:** 09.05.2026

---

## 1. Überblick & Forschungskontext

### 1.1 Worum geht es?

Diese Arbeit kombiniert zwei Themenstränge zu einem integrierten Forschungsvorhaben:

- **T5 – Skyfall-GS Pipeline:** Nutzung der frei verfügbaren [Skyfall-GS](https://huggingface.co/spaces/Skyfall-GS) Pipeline (GitHub + HuggingFace) zur 3D-Rekonstruktion aus Schrägluftaufnahmen und Drohnenvideos. Skyfall-GS ist speziell für Schrägluft- und Satellitenbilder optimiert.
- **T6 – 3DGS vs. Punktwolke:** Systematischer, quantitativer Vergleich von **3D Gaussian Splatting (3DGS)** mit klassischer photogrammetrischer 3D-Rekonstruktion (SfM → MVS → Dense Point Cloud → Mesh).

### 1.2 Erweiterte Idee des Autors

Der Autor plant zusätzlich:

1. **Skyfall-GS als zentrale Pipeline** für die Verarbeitung von **Drohnenvideos** (UAV footage) einzusetzen.
2. Einen **systematischen Benchmark** aufzubauen, der den Trade-off zwischen:
   - ⏱️ **Geschwindigkeit** (Processing-Zeit, Ende-zu-Ende)
   - 🎯 **Genauigkeit** (metrisch, geometrisch, visuell)
   - 💰 **Kosten** (Hardware, Rechenzeit, Cloud vs. Lokal)
   
   für verschiedene 3D-Rekonstruktionsverfahren quantifiziert.
3. Ein **physisches Testfeld** mit bekannten Referenzpunkten (Ground Control Points / GCPs) aufzubauen, um die **metrische Genauigkeit** der gerenderten Gaussian Splats objektiv zu messen.
4. Die **Qualität der gerenderten Gaussian Splats** anhand sinnvoller Metriken zu erfassen und mit klassischen Verfahren zu vergleichen.

### 1.3 Arbeitstitel (Entwurf)

> „Evaluation von 3D Gaussian Splatting im Vergleich zur klassischen Photogrammetrie am Beispiel drohnenbasierter Schrägluftaufnahmen – Analyse von Geschwindigkeit, Genauigkeit und Kosten"

---

## 2. Forschungsfragen

Die Research-AI soll den aktuellen Stand der Forschung zu folgenden Kernfragen ermitteln:

### Primäre Forschungsfragen

1. **Wie schneidet 3D Gaussian Splatting im direkten Vergleich mit klassischer Photogrammetrie (SfM/MVS/Mesh) bei drohnenbasierten Aufnahmen ab?**
   - In den Dimensionen: geometrische Genauigkeit, visuelle Qualität, Verarbeitungsgeschwindigkeit, Speicherbedarf, Kosten.

2. **Ist Skyfall-GS als Pipeline für Drohnenvideos geeignet und wie performt es im Vergleich zu Standard-3DGS-Implementierungen und klassischen Photogrammetrie-Lösungen?**

3. **Wie lässt sich ein 3D Gaussian Splat geodätisch referenzieren (Georeferenzierung)?**
   - Dies ist eine identifizierte **Forschungslücke** – bisher gibt es wenig Literatur zur metrisch genauen Georeferenzierung von 3DGS-Szenen.

4. **Können beide Verfahren symbiotisch genutzt werden?** (z.B. Gaussian Splat für schnelle Visualisierung + Mesh/Punktwolke für geodätische Messung)

### Sekundäre Forschungsfragen

5. **Welche Metriken sind für die Bewertung der Qualität von 3DGS-Rekonstruktionen im geodätischen/vermessungstechnischen Kontext am aussagekräftigsten?**

6. **Welche Rolle spielt die Eingabe-Datenqualität (Videoauflösung, Überlappung, Flughöhe, Kameramodell) für die Qualität der 3DGS-Rekonstruktion?**

7. **Wie ist der aktuelle Stand der GIS-Integration von 3DGS?** (ArcGIS Pro, Cesium, Potree, Three.js, SuperSplat, Nerfstudio)

---

## 3. Evaluationsdimensionen (Kriterienkatalog)

Die folgenden 5 Dimensionen sollen in der Literaturrecherche berücksichtigt und mit bestehenden Studien belegt werden:

| Dimension | Kriterien | Messmethode |
|---|---|---|
| **D1: Geometrische Genauigkeit** | RMSE, Hausdorff-Distanz, Maßstabstreue, Georeferenzierung | Vergleich mit Referenzdaten (GCPs, GNSS, Tachymeter) |
| **D2: Visuelle Qualität** | PSNR, SSIM, LPIPS, subjektive Bewertung | Novel View Synthesis Metriken |
| **D3: Objekterkennbarkeit** | Manuelle Identifizierbarkeit von Objekten, semantische Kohärenz | Nutzerstudie / Experteneinschätzung |
| **D4: ML-Objekterkennung** | Erkennungsrate trainierter Modelle auf gerenderten 3D-Daten | YOLOv8 / Mask R-CNN auf gerenderten Views |
| **D5: Praxistauglichkeit** | Rechenzeit, Speicher, Skalierbarkeit, GIS-Import, Kosten | Benchmarking auf definierter Hardware |

> [!IMPORTANT]
> Besonders relevant ist **D1 (Geometrische Genauigkeit)** im geodätischen Kontext – dies unterscheidet die Arbeit von reinen Computer-Vision-Studien, die sich oft nur auf D2 (visuelle Qualität) fokussieren.

---

## 4. Recherche-Aufgaben für die Research-AI

### 4.1 Themenblöcke

Bitte recherchiere den **aktuellen Stand der Forschung** (Schwerpunkt 2023–2026) zu folgenden 7 Themenblöcken:

---

#### Block A: 3D Gaussian Splatting – Grundlagen & Weiterentwicklungen

- **Foundational Paper:** Kerbl et al. (2023) – „3D Gaussian Splatting for Real-Time Radiance Field Rendering" (SIGGRAPH 2023)
- Weiterentwicklungen: Mip-Splatting, 2D Gaussian Splatting, Scaffold-GS, GaussianPro, SuGaR, 3DGS-DR, etc.
- Aktuelle Survey-Paper zu 3DGS (2024–2026)
- Vergleich mit NeRF-basierten Methoden (Instant-NGP, Nerfacto, Zip-NeRF)
- **Suchbegriffe:** `"3D Gaussian Splatting" survey`, `3DGS improvements 2024 2025`, `Gaussian Splatting vs NeRF`, `radiance field rendering comparison`

---

#### Block B: Skyfall-GS – Pipeline, Architektur, Leistungsfähigkeit

- **Paper:** Skyfall-GS (auf HuggingFace/GitHub veröffentlicht)
- Architektur und Besonderheiten (Optimierung für Schrägluft-/Satellitenbilder)
- Vergleich mit anderen 3DGS-Pipelines für Luftbilddaten
- Limitierungen und bekannte Schwächen
- **Suchbegriffe:** `Skyfall-GS`, `"Skyfall GS" Gaussian Splatting`, `3DGS oblique aerial imagery`, `Gaussian Splatting satellite images`, `3DGS UAV pipeline`

---

#### Block C: Drohnenbasierte 3D-Rekonstruktion – Klassische Photogrammetrie

- State of the Art: SfM → MVS → Dense Matching → Mesh (OpenDroneMap, COLMAP, Agisoft Metashape, Pix4D, RealityCapture)
- Drohnenvideos vs. Einzelbilder als Input (Videobasierte SfM-Pipelines)
- Georeferenzierung: RTK-Drohnen, GCPs, direkte Georeferenzierung
- Genauigkeitsstudien mit Drohnenaufnahmen (RMSE-Analysen, GCP-basiert)
- Open-Source-Pipelines: OpenDroneMap, COLMAP, MVE, OpenMVS
- **Suchbegriffe:** `UAV photogrammetry accuracy benchmark`, `drone 3D reconstruction comparison`, `SfM MVS point cloud accuracy`, `OpenDroneMap vs Metashape accuracy`, `video-based SfM UAV`

---

#### Block D: 3DGS auf Drohnendaten – Spezifische Studien

- Studien, die 3DGS explizit auf Drohnenaufnahmen anwenden
- Qualität von 3DGS bei großflächigen Outdoor-Szenen (Large-Scale Gaussian Splatting)
- Probleme: floaters, sky reconstruction, unbounded scenes, sparse views
- Lösungsansätze für Drohnenspezifische Herausforderungen
- **Suchbegriffe:** `Gaussian Splatting drone`, `3DGS UAV`, `3DGS aerial images`, `large-scale Gaussian Splatting outdoor`, `3DGS urban reconstruction`, `Gaussian Splatting oblique`

---

#### Block E: Vergleichsstudien 3DGS vs. Photogrammetrie

- **Kernfrage:** Welche direkten Vergleichsstudien existieren bereits?
- Metriken, die in bestehenden Studien verwendet werden
- Ergebnisse: Wo ist 3DGS überlegen, wo klassische Photogrammetrie?
- Identifizierte Forschungslücken
- **Hinweis:** Der Autor hat bereits folgendes Paper: *„Comparative Evaluation of 3D Reconstruction with Photogrammetry"* – bitte nach vergleichbaren und neueren Studien suchen.
- **Suchbegriffe:** `"Gaussian Splatting" vs photogrammetry`, `3DGS comparison point cloud`, `Gaussian Splatting accuracy evaluation`, `3DGS geometric accuracy`, `novel view synthesis vs photogrammetry`, `3DGS vs mesh reconstruction`

---

#### Block F: Georeferenzierung von 3D Gaussian Splats

- **Identifizierte Forschungslücke!** Wie kann ein 3DGS-Modell in ein geodätisches Koordinatensystem eingehängt werden?
- Ansätze: Transformation über bekannte Punkte, Integration von GNSS-Daten in die Pipeline, Post-Processing-Alignment
- GIS-Integration: Können Gaussian Splats in GIS-Systeme importiert werden? (ArcGIS Pro 3.x, QGIS, Cesium)
- Standards: OGC, CityGML, 3D Tiles, glTF
- **Suchbegriffe:** `Gaussian Splatting georeferencing`, `3DGS coordinate system`, `3DGS GIS integration`, `Gaussian Splatting geospatial`, `3D Tiles Gaussian Splatting`, `ArcGIS Gaussian Splatting`

---

#### Block G: Testfeld-Design & Benchmark-Methodik

- Best Practices für den Aufbau photogrammetrischer Testfelder
- GCP-Design, Passpunktverteilung, Referenzmessungen (Tachymeter, GNSS)
- Benchmark-Datensätze für 3D-Rekonstruktion: Tanks & Temples, MipNeRF360, ETH3D, DTU, BlendedMVS
- Kosten-Nutzen-Analysen für 3D-Rekonstruktionsverfahren (Hardware, Rechenzeit, Lizenzkosten)
- **Suchbegriffe:** `photogrammetric test field design`, `3D reconstruction benchmark UAV`, `GCP placement accuracy`, `cost-benefit 3D reconstruction`, `photogrammetry vs 3DGS computational cost`

---

### 4.2 Spezifische Paper, die gesucht/verifiziert werden sollen

| Paper | Status | Aktion |
|---|---|---|
| Kerbl et al. (2023) – 3D Gaussian Splatting | ✅ Bekannt | Vollzitat + aktuelle Zitationszahl |
| Skyfall-GS Paper | ✅ Vorhanden (PDF) | Autoren, Jahr, Venue, DOI verifizieren |
| „Comparative Evaluation of 3D Reconstruction with Photogrammetry" | ✅ Vorhanden (PDF) | Autoren, Jahr, Venue, DOI verifizieren |
| „Novel UAV-based 3D reconstruction using dense LiDAR point cloud" | ✅ Vorhanden (PDF) | Autoren, Jahr, Venue, DOI verifizieren |
| Aktuelle Survey-Paper zu 3DGS (2024–2026) | ❓ Zu suchen | Mindestens 2–3 aktuelle Surveys identifizieren |
| Vergleichsstudien 3DGS vs. Photogrammetrie auf Drohnendaten | ❓ Zu suchen | Alle verfügbaren Studien sammeln |
| Studien zur Georeferenzierung von 3DGS | ❓ Zu suchen | Forschungslücke dokumentieren |

---

## 5. Erwartete Deliverables der Research-AI

### 5.1 Strukturierter Literature Review

Für jeden der 7 Themenblöcke (A–G):

1. **Zusammenfassung des aktuellen Stands** (3–5 Sätze)
2. **Wichtigste Paper** (Titel, Autoren, Jahr, Venue/Journal, DOI/Link)
3. **Kernerkenntnisse** (Was hat die Community herausgefunden?)
4. **Offene Fragen / Forschungslücken** (Was fehlt noch?)
5. **Relevanz für diese Arbeit** (Wie passt es zum Forschungsvorhaben?)

### 5.2 Gap-Analyse

- Welche konkreten **Forschungslücken** existieren, die diese Arbeit füllen könnte?
- Gibt es bereits eine Studie, die exakt das geplante Vorhaben abdeckt? (→ Abgrenzung notwendig)
- Was wäre das **Alleinstellungsmerkmal (USP)** dieser Arbeit?

### 5.3 Methodik-Empfehlungen

- Welche **Metriken** werden in der Community am häufigsten verwendet und sollten übernommen werden?
- Welche **Pipelines/Tools** sind State of the Art für den Vergleich?
- Welche **Benchmark-Datensätze** eignen sich als Baseline?
- Welche **Hardware-Konfigurationen** werden in vergleichbaren Studien genutzt?

### 5.4 Bibliographie

- Vollständige Zitationsdaten aller gefundenen relevanten Paper
- Bevorzugt im **BibTeX-Format**
- Mindestens **20–30 relevante Quellen**

---

## 6. Kontextinformationen für die Recherche

### 6.1 Verfügbare Infrastruktur

| Ressource | Details |
|---|---|
| **Photogrammetrie-Labor (THWS)** | 128 GB RAM, starke GPU (Modell zu klären) |
| **Software (FOSS)** | COLMAP, OpenDroneMap, Nerfstudio, gsplat, SuperSplat, CloudCompare |
| **Software (Kommerziell)** | ArcGIS Pro (Uni-Lizenz), ggf. Agisoft Metashape (Uni-Lizenz) |
| **Drohne** | Uni-Drohne vorhanden (Modell zu klären) |
| **Daten** | Eigene Drohnenaufnahmen (Campus), öffentliche Benchmarks, ggf. Schrägluftbilder Würzburg (5 cm DOP) |

### 6.2 Zeitlicher Rahmen

| Phase | Zeitraum | Fokus |
|---|---|---|
| **PA (Projektarbeit)** | 4 Wochen netto, ~15–25 Seiten | Konzept, Literaturreview, Kriterienkatalog, Pilotversuch, Versuchsdesign |
| **BA (Bachelorarbeit)** | 10 Wochen netto, ~40–80 Seiten | Vollständige Vergleichsstudie, Testfeld, quantitative Auswertung |

### 6.3 Betreuer-Fit

- **Prof. Müller** – Erstprüfer, Schwerpunkte: Computer Vision, Photogrammetrie, 3D-Rekonstruktion, ML
- **Prof. Wilkening** – Zweitprüfer, Schwerpunkte: GIS, WebApp-Entwicklung

---

## 7. Qualitätsanforderungen an die Recherche

> [!CAUTION]
> Die folgenden Anforderungen sind für die Qualität der Recherche kritisch.

1. **Aktualität:** Bevorzuge Paper von **2023–2026**. Ältere Paper nur, wenn sie Foundational sind (z.B. NeRF 2020, COLMAP).
2. **Peer-Review:** Bevorzuge peer-reviewed Publikationen (CVPR, ECCV, ICCV, SIGGRAPH, ISPRS, IEEE TGRS). ArXiv-Preprints sind akzeptabel, aber als solche kennzeichnen.
3. **Geodätischer Fokus:** Viele 3DGS-Paper kommen aus der Computer-Vision-Community und ignorieren geodätische Genauigkeit. Suche gezielt nach Studien mit **geodätischem/vermessungstechnischem Fokus**.
4. **Reproduzierbarkeit:** Bevorzuge Studien mit verfügbarem Code und Daten.
5. **Sprache:** Englisch bevorzugt, Deutsch akzeptabel (insb. für ISPRS-D, DVW, zfv).
6. **Keine Halluzinationen:** Wenn zu einem Themenblock wenig Literatur existiert, dokumentiere dies ehrlich als Forschungslücke. Erfinde keine Paper.

---

## 8. Suchstrategie-Empfehlungen

### Datenbanken & Quellen

| Quelle | URL | Zweck |
|---|---|---|
| Google Scholar | scholar.google.com | Breite Suche, Zitationsanalyse |
| Semantic Scholar | semanticscholar.org | KI-gestützte Relevanzsuche |
| IEEE Xplore | ieeexplore.ieee.org | Geomatik, Remote Sensing |
| ISPRS Archives | isprs.org | Photogrammetrie, Fernerkundung |
| arXiv (cs.CV, cs.GR) | arxiv.org | Neueste Preprints |
| Papers With Code | paperswithcode.com | Code-Verfügbarkeit prüfen |
| DBLP | dblp.uni-trier.de | Vollständige Publikationslisten |
| GitHub / HuggingFace | github.com, huggingface.co | Skyfall-GS, Implementierungen |

### Vorgeschlagene Suchketten (Copy-Paste ready)

```
"3D Gaussian Splatting" AND (UAV OR drone OR aerial) AND (accuracy OR evaluation)
"Gaussian Splatting" AND photogrammetry AND comparison
"3DGS" AND georeferencing
"Gaussian Splatting" AND (point cloud OR mesh) AND metric
Skyfall-GS OR "Skyfall GS"
"novel view synthesis" AND UAV AND benchmark
"3D reconstruction" AND drone AND (cost OR speed OR accuracy) AND comparison
"Gaussian Splatting" AND (GIS OR geospatial OR coordinate)
"3DGS" AND (RMSE OR "Hausdorff distance" OR "geometric accuracy")
"oblique aerial imagery" AND "3D Gaussian Splatting"
```

---

## 9. Zusammenfassung der Forschungsidee (Elevator Pitch)

> **Ziel:** Aufbau eines standardisierten Testfelds mit GCPs zur systematischen Evaluation von 3D Gaussian Splatting (insb. Skyfall-GS) im Vergleich zu klassischer UAV-Photogrammetrie. Der Benchmark erfasst den Trade-off zwischen **Geschwindigkeit**, **metrischer Genauigkeit** und **Kosten** und schließt die Forschungslücke der **geodätischen Referenzierung von 3DGS-Szenen**. Die Arbeit liefert eine praxisorientierte Handlungsempfehlung für den Einsatz von 3DGS in geodätischen Anwendungen.

---

> [!NOTE]
> **An die Research-AI:** Du hast volle Freiheit, zusätzliche relevante Themenblöcke oder Paper zu identifizieren, die über dieses Briefing hinausgehen. Wenn du während der Recherche auf relevante Aspekte stößt, die hier nicht abgedeckt sind (z.B. neue 3DGS-Varianten, regulatorische Aspekte für Drohnenflüge, Datenschutzfragen bei Luftbildern), dokumentiere diese als „Zusätzliche Erkenntnisse". Die Struktur dieses Briefings ist ein Leitfaden, kein Korsett.
