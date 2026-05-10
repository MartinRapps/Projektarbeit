# Arbeitsexposé: 3DGS Scan-to-BIM Pipeline

> [!NOTE]
> **Zweck:** Arbeitsgrundlage für das formale Exposé an den Dozenten. Enthält alle technischen Details, Repos, Paper, TODOs und den Pipeline-Aufbau.

---

## 1. Titel & Forschungsfrage

**Arbeitstitel:**
*3D Gaussian Splatting vs. klassische Photogrammetrie: Geometrische Validierung, Segmentierung und Centerline-Extraktion für Leitungsinfrastruktur (Scan-to-BIM)*

**Zentrale Forschungsfrage (BA):**
> Lässt sich aus einem 3DGS-Modell über SuGaR-Mesh-Extraktion und Centerline-Algorithmen eine geometrisch verwertbare 3D-Achslinie für röhrenförmige Infrastruktur ableiten, und wie genau ist diese im Vergleich zur RTK-GNSS-Referenz?

---

## 2. Pipeline-Architektur (Gesamtübersicht)

```
┌─────────────┐    ┌─────────┐    ┌──────────┐    ┌──────────────┐
│ Kamera-Video │───>│ COLMAP  │───>│  3DGS    │───>│ Georef.      │
│ (Testfeld)   │    │ (SfM)   │    │ (gsplat) │    │ (Helmert 7P) │
└─────────────┘    └─────────┘    └──────────┘    └──────┬───────┘
                                                         │
                   ┌─────────────────────────────────────┘
                   │
          ┌────────▼─────────┐    ┌──────────┐    ┌──────────────┐
          │ Gaussian Grouping │───>│  SuGaR   │───>│ Centerline   │
          │ (Segmentierung)   │    │ (Mesh)   │    │ (DGtal)      │
          └──────────────────┘    └──────────┘    └──────┬───────┘
                                                         │
                                                ┌────────▼───────┐
                                                │ GIS-Import     │
                                                │ (ArcGIS/QGIS)  │
                                                └────────────────┘
```

**Schritte im Detail:**

| # | Schritt | Tool | Input | Output |
|---|---------|------|-------|--------|
| 1 | Bilderfassung | Kamera (Video) | Campus-Testfeld | Bildsequenz (JPEG) |
| 2 | SfM | COLMAP | Bilder | Sparse Point Cloud + Kameraposen |
| 3 | 3DGS Training | gsplat | Sparse PC + Kameras | 3DGS-Modell (.ply) |
| 4 | Georeferenzierung | Eigenes Skript (numpy) | GCP-Koordinaten + Modell | Georef. 3DGS-Modell |
| 5 | Segmentierung | Gaussian Grouping | 3DGS + 2D-Masken (DEVA) | Segmentierte Gaussians (Kabel isoliert) |
| 6 | Mesh-Extraktion | SuGaR | Segmentierte Gaussians | 3D-Mesh (.obj/.ply) |
| 7 | Centerline | DGtal / eigenes Skript | Kabel-Mesh | 3D-Linie (Polyline) |
| 8 | GIS-Import | ArcGIS Pro / QGIS | Georef. Linie | Shapefile / GeoJSON |
| 9 | Evaluation | Python (numpy) | Centerline vs. RTK-Referenz | RMSE [cm] |

---

## 3. Scope-Trennung PA / BA

### Projektarbeit (PA) – 7 ECTS, 4 Wochen netto

**Scope:** Testfeldaufbau, Datenerfassung, Proof of Concept (Schritte 1-3).

| TODO | Details | Zeitschätzung |
|------|---------|--------------|
| Testfeld aufbauen | Gartenschlauch + Schnüre auf Campus auslegen | 1 Tag |
| GCPs auslegen & einmessen | 8-12 GCPs mit RTK-GNSS einmessen | 1-2 Tage |
| Videoaufnahme | Kamerasequenz (Nadir + Oblique simuliert) | 0.5 Tage |
| COLMAP installieren | Pre-built Windows Binary von demuc.de | 0.5 Tage |
| COLMAP Pipeline laufen lassen | Feature Extraction → Matching → Sparse Recon | 1 Tag |
| MVS-Baseline erzeugen | COLMAP Dense Reconstruction oder Metashape | 1-2 Tage |
| gsplat installieren | Conda + pip install gsplat | 1 Tag |
| 3DGS-Modell trainieren | gsplat auf COLMAP-Output | 1-2 Tage |
| Visueller Vergleich | Screenshots MVS vs. 3DGS (feine Strukturen) | 1 Tag |
| Rechenzeit-Benchmark | Tabelle: MVS-Zeit vs. 3DGS-Zeit | 0.5 Tage |
| PA schreiben | 15-25 Seiten | 5-7 Tage |

**Forschungsfragen PA:**
1. Lassen sich texturlose (Schlauch) und feine Strukturen (Schnüre) durch 3DGS visuell vollständiger rekonstruieren als durch MVS?
2. Wie verhalten sich die Rechenzeiten der dichten Rekonstruktion?

**Ergebnis PA:** Validierter Datensatz, lauffähige Pipelines, erster Vergleich.

---

### Bachelorarbeit (BA) – 15 ECTS, 10 Wochen netto

**Scope:** Georeferenzierung, Segmentierung, Mesh, Centerline, Evaluation (Schritte 4-9).

| TODO | Details | Zeitschätzung |
|------|---------|--------------|
| Georef-Skript schreiben | Helmert 7P Transformation (numpy/scipy) | 2-3 Tage |
| Gaussian Grouping installieren | Conda env (Python 3.8, PyTorch 1.12.1) | 1-2 Tage |
| DEVA Masken erzeugen | 2D-Masken über alle Bilder generieren | 1-2 Tage |
| Gaussian Grouping trainieren | Identity Encoding auf eigenem Datensatz | 2-3 Tage |
| SuGaR installieren | Conda env (Python 3.9, CUDA 11.8) | 1-2 Tage |
| SuGaR Windows-Pfade fixen | `os.path.join` / `pathlib.Path` einsetzen | 0.5 Tage |
| SuGaR Mesh extrahieren | Poisson-Rekonstruktion der Kabel-Gaussians | 1-2 Tage |
| Centerline-Algorithmus | DGtal bauen ODER Python-Reimplementierung | 3-5 Tage |
| Georef. Linie in GIS | Export als Shapefile, Import in ArcGIS/QGIS | 1-2 Tage |
| RMSE-Evaluation | Centerline vs. RTK-GNSS Referenzlinie | 2-3 Tage |
| Wirtschaftlichkeits-Benchmark | Kosten/Zeit Vergleich vs. klassische Vermessung | 2-3 Tage |
| BA schreiben | 40-60 Seiten | 15-20 Tage |

**Forschungsfragen BA:**
1. Wie genau ist die extrahierte Centerline im Vergleich zur RTK-GNSS-Referenz (RMSE)?
2. Welche Segmentierungsstrategie liefert die robusteste Isolation der Kabel-Gaussians?
3. Ab welchem Objektdurchmesser scheitert die Pipeline?
4. Ist 3DGS eine wirtschaftlichere Alternative für die Bauüberwachung?

---

## 4. Alle GitHub-Repositories

| Tool | Repo-URL | Lizenz | Sterne |
|------|----------|--------|--------|
| COLMAP | https://github.com/colmap/colmap | BSD-3 | ~8k |
| gsplat | https://github.com/nerfstudio-project/gsplat | Apache-2.0 | ~2k |
| nerfstudio | https://github.com/nerfstudio-project/nerfstudio | Apache-2.0 | ~10k |
| SuGaR | https://github.com/Anttwo/SuGaR | Custom (Research) | ~3.3k |
| Gaussian Grouping | https://github.com/lkeab/gaussian-grouping | Apache-2.0 | ~1.5k |
| DEVA (Tracking) | https://github.com/hkchengrex/Tracking-Anything-with-DEVA | - | ~2k |
| Grounded-SAM | https://github.com/hkchengrex/Grounded-Segment-Anything | Apache-2.0 | - |
| DGtal | https://github.com/DGtal-team/DGtal | LGPL | ~0.5k |
| DGtalTools | https://github.com/DGtal-team/DGtalTools | LGPL | - |
| Original 3DGS | https://github.com/graphdeco-inria/gaussian-splatting | Custom | ~15k |

---

## 5. Alle Paper-Referenzen

### Kern-Paper (direkt in Pipeline genutzt)

1. **3D Gaussian Splatting** – Kerbl, Kopanas, Leimkühler, Drettakis (SIGGRAPH 2023)
   - *"3D Gaussian Splatting for Real-Time Radiance Field Rendering"*
   - ACM Transactions on Graphics 42(4). Best Paper SIGGRAPH 2023.

2. **SuGaR** – Guédon, Lepetit (CVPR 2024)
   - *"SuGaR: Surface-Aligned Gaussian Splatting for Efficient 3D Mesh Reconstruction and High-Quality Mesh Rendering"*
   - ArXiv: 2311.12775

3. **Gaussian Grouping** – Ye et al. (ECCV 2024)
   - *"Gaussian Grouping: Segment and Edit Anything in 3D Scenes"*
   - GitHub: lkeab/gaussian-grouping

4. **Centerline-Extraktion** – Kerautret, Krähenbühl, Debled-Rennesson, Lachaud (DGCI 2016)
   - *"3D Geometric Analysis of Tubular Objects based on Surface Normal Accumulation"*
   - DGtal-Bibliothek

5. **COLMAP** – Schönberger, Frahm (CVPR 2016)
   - *"Structure-from-Motion Revisited"*

### Vergleichsstudien & Benchmarks

6. **GauU-Scene V2 Benchmark** – Inverse Korrelation PSNR vs. geometrische Genauigkeit
7. **ISPRS Annals 2025** – Geodätisch relevanteste Vergleichsstudie 3DGS vs. Photogrammetrie
8. **GeoRefGS** – *"Towards Georeferenced 3DGS from UAV Platforms"* (MDPI 2025)
   - Erwähnt als State-of-the-Art, nicht genutzt (kein öffentlicher Code)

### Varianten (State-of-the-Art Kapitel)

9. **Mip-Splatting** (CVPR 2024, Best Student Paper) – Anti-Aliasing für Multi-Scale
10. **2D Gaussian Splatting** (SIGGRAPH 2024) – Planare Gaussians, bessere Geometrie
11. **GaussianPro** (ICML 2024) – Löst texturlose Regionen
12. **Scaffold-GS** (CVPR 2024, Highlight) – Speicher-Reduktion
13. **DroneSplat** – Drohnenspezifische 3DGS-Pipeline

### GIS/BIM-Integration

14. **glTF KHR_gaussian_splatting** – Neuer Standard für 3DGS in GIS
15. **3D Tiles / CesiumJS** – Streaming von 3DGS in Webviewern

---

## 6. Installations-Checkliste

### Voraussetzung: Hardware & Treiber
- [ ] NVIDIA GPU mit ≥ 8 GB VRAM (empfohlen: RTX 3090/4090, 24 GB)
- [ ] NVIDIA Treiber ≥ 525.x (unterstützt CUDA 11.3-11.8)
- [ ] Conda/Miniconda installiert
- [ ] Git installiert
- [ ] Visual Studio Build Tools (C++ Compiler für Windows)

### Schritt 1: COLMAP
- [ ] Pre-built Binary von https://demuc.de/colmap/ (CUDA-Version!) herunterladen
- [ ] Entpacken und PATH setzen
- [ ] Test: `colmap -h`

### Schritt 2: gsplat (3DGS Training)
```bash
conda create -n gsplat python=3.10 -y
conda activate gsplat
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install gsplat
```
- [ ] Test: `python -c "import gsplat; print('OK')"`

### Schritt 3: SuGaR (Mesh-Extraktion)
```bash
git clone https://github.com/Anttwo/SuGaR.git --recursive
cd SuGaR
python install.py  # Erstellt conda env "sugar"
conda activate sugar
```
- [ ] Windows-Pfade fixen: `/` → `os.path.join()` in relevanten Skripten
- [ ] Test: `python train.py --help`

### Schritt 4: Gaussian Grouping (Segmentierung)
```bash
git clone https://github.com/lkeab/gaussian-grouping.git
cd gaussian-grouping
conda create -n gaussian_grouping python=3.8 -y
conda activate gaussian_grouping
conda install pytorch==1.12.1 torchvision==0.13.1 torchaudio==0.12.1 cudatoolkit=11.3 -c pytorch
pip install plyfile==0.8.1 tqdm scipy wandb opencv-python scikit-learn lpips
pip install submodules/diff-gaussian-rasterization
pip install submodules/simple-knn
```
- [ ] Optional DEVA für eigene Masken:
```bash
cd Tracking-Anything-with-DEVA
pip install -e .
bash scripts/download_models.sh
```

### Schritt 5: DGtal (Centerline)
```bash
git clone https://github.com/DGtal-team/DGtal.git
cd DGtal && mkdir build && cd build
cmake .. && make -j$(nproc)
```
- [ ] Alternativ: Centerline-Algorithmus (Normalenakkumulation) selbst in Python mit Open3D/Trimesh reimplementieren (~100 Zeilen)

### Schritt 6: Georeferenzierung (eigenes Skript)
```python
# Nur numpy + scipy nötig, kein extra Environment
pip install numpy scipy
```
- [ ] CSV vorbereiten: `ID, X_lokal, Y_lokal, Z_lokal, X_welt, Y_welt, Z_welt`
- [ ] Helmert 7P berechnen mit `scipy.spatial.transform`
- [ ] Transformation auf alle Gaussian-Positionen anwenden

---

## 7. Evaluation-Framework (Dimensionen D1-D5)

| Dimension | Metrik | Tool | PA | BA |
|-----------|--------|------|----|----|
| D1: Geometrie | RMSE horizontal/vertikal [cm] | numpy (eigenes Skript) | ❌ | ✅ |
| D2: Visuelle Qualität | PSNR, SSIM, LPIPS | gsplat metrics | ✅ | ✅ |
| D3: Manuelle Identifizierbarkeit | Visueller Vergleich (Screenshots) | Manuell | ✅ | ✅ |
| D4: ML-Objekterkennung | Precision, Recall, F1 (Segmentierung) | Python (sklearn) | ❌ | ✅ |
| D5: Praktikabilität/Kosten | Zeit [min], Kosten [€], Hardware | Tabelle | ✅ | ✅ |

---

## 8. Testfeld-Design (Campus)

| Element | Simulation von | Spezifikation |
|---------|---------------|---------------|
| Gartenschlauch (terracotta) | DC-Erdkabel | ⌀ ca. 20 cm, 5-10 m Länge |
| Gartenschlauch (schwarz) | Weiteres Kabel | ⌀ ca. 15 cm, 5-10 m Länge |
| Schnur (dünn, hell) | Überlandleitung | ⌀ ca. 5-10 mm |
| Schnur (dünn, dunkel) | Überlandleitung | ⌀ ca. 3-5 mm |
| GCP-Targets | Passpunkte | 8-12 Stück, Schachbrett oder Kreuzmarker |
| Referenzstrecken | Kontrollmaße | 3-5 bekannte Distanzen (Maßband + RTK) |

---

## 9. Risikomatrix

| Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|--------|-------------------|--------|------------|
| SuGaR Windows-Pfade | Hoch | Niedrig | Trivial fixbar mit pathlib |
| Gaussian Grouping: Kabel nicht erkannt | Mittel | Hoch | Fallback: manuelle Farb-Filterung der Splat-Attribute |
| Centerline-Algorithmus liefert schlechte Ergebnisse | Mittel | Hoch | Alternative: Skeleton-Extraktion mit Open3D |
| VRAM reicht nicht (< 12 GB) | Niedrig | Hoch | Cloud-GPU (Vast.ai ~0.40€/h) |
| RTK-GNSS nicht verfügbar | Niedrig | Sehr hoch | Frühzeitig beim Photogrammetrie-Labor anfragen |
| Mesh zu verrauscht für Centerline | Mittel | Mittel | SuGaR `dn_consistency` Regularisierung verwenden |

---

## 10. Diskussionspunkte für den Dozenten

1. **Scope PA vs. BA:** PA = Datenerhebung + Vergleich (MVS vs. 3DGS). BA = Scan-to-BIM Pipeline.
2. **Segmentierung:** Einfache Farb-Filterung vs. Gaussian Grouping (ECCV 2024)?
3. **Georeferenzierung:** Klassische Helmert-Transformation über COLMAP GCPs.
4. **Testfeld:** Campus ausreichend, oder Drohnenflug im Photogrammetrie-Labor?
5. **KI-Nutzung:** Copilot/ChatGPT/Claude für Code – Dokumentation gemäß PABA-Hinweise Kap. 3.5.
6. **Hardware:** Eigene GPU oder Hochschul-Rechner / Cloud?
7. **Centerline:** DGtal (C++) oder eigene Python-Reimplementierung?
