# Agent Memory (Session-derived Project Knowledge)

Source: opencode session 2026-07-18 (centerline, B-spline, OCR, georeferencing, pipeline analysis)
Author: opencode assistant (glm-5.2)

## Projekt & Bachelorarbeit

- **Thema:** "KI-gestützte 3D-Rekonstruktion linearer Infrastruktur: Evaluierung einer Docker-basierten Scan-to-BIM Pipeline mittels SAM 3 und Gaussian Splatting" — Bachelor- und Projektarbeit an der THWS.
- **Ziel:** Drohnenvideo → SAM-3-Masken → COLMAP SfM → STS objektspezifisches 3DGS → SuGaR-Meshing → DGtal-Centerline → georeferenziertes GeoJSON (EPSG:25832) für GIS-Import (ArcGIS Pro). Toleranzrahmen ±10 cm.
- **Auftraggeber-Bezug:** TenneT (Kabeltrassen-Vermessung). Testdatensatz: `Alurohr_THWS.mp4` (Alurohr-Gestell im Labor), zusätzlich Sonnenbrillen-Experimente im Exposé.
- **Nutzer:** Martin (GitHub: MartinRapps). SuGaR auf eigenen Fork (`https://github.com/MartinRapps/SuGaR`) gepinnt mit maskenbewussten Modifikationen (Commit `48bbfdd "masked SuGaR updates"`).
- **Exposé:** `Themenfindung/Expose_PA_BA.tex` (754 Zeilen, article-Klasse, Deutsch). Kompiliert mit `pdflatex -interaction=nonstopmode -halt-on-error`. Hat `[GELÖST: ...]`- und `[NEUE ERKENNTNIS: ...]`-Einträge im Risikomanagement-Abschnitt für gelöste Probleme. LaTeX-Gotcha: `_` in `\texttt{}` muss als `\_` escaped werden.

## Container-Architektur (Stand 07/2026)

| Container | Base Image | Zweck | GPU |
|---|---|---|---|
| A (sam3-preprocess) | `nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04` | SAM-3-Masken, ffmpeg, GCP-Prep, STS-Scene-Prep, OCR (früher) | ja |
| B (colmap-sfm) | `colmap/colmap:latest` (ungepinnt!) | COLMAP SfM | ja |
| C (sts-training) | `pytorch/pytorch:2.3.1-cuda12.1-cudnn8-devel` | STS 3DGS-Training, PLY-Filtering | ja |
| D (sugar-meshing) | `nvidia/cuda:11.8.0-devel-ubuntu22.04` + Miniconda | SuGaR Meshing (CUDA 11.8, PyTorch 2.0.1, pytorch3d 0.7.4) | ja |
| E (post-processing) | `ubuntu:22.04` | DGtal-Centerline, GDAL, tesseract OCR, B-Spline | nein |

- Alle Container mounten `./data:/data` und `./src:/app/src` (außer E, das `src/cpp` für den Build reinkopiert). Container D zusätzlich `./data/sugar_output:/opt/sugar/output`.
- `docker-compose.yml` nutzt sowohl `gpus: all` (legacy) als auch `deploy.resources.reservations.devices` (redundant).
- `docker-compose.sugar-dev.yml` mountet `./third_party/SuGaR:/opt/sugar` und wird von `run_masked_sugar.sh` **immer** mit `-f` geladen.
- **Kein `.dockerignore`** vorhanden → `build context: .` schickt `data/`, Logs, `.venv/` an den Daemon.

## Pipeline-Ablauf (Autopilot-tauglich seit 07/2026)

```
Step 0: GCP-Prep (prepare_gcp.py → anchor.txt + gcp_relative.csv)
Step 1: SAM3-Masken (extract_masks_notebook_flow.py)
Step 2: COLMAP SfM (run_sfm.sh → sparse/0, points3D.ply)
  → Breakpoint: CloudCompare Point-Picking (Autopilot überspringt)
Step 3: STS-Training (prep_sts_scene.py → train.py, 7000 Iter, Stage2 5000)
Step 4: SuGaR-Meshing (filter_cable_pc.py → run_masked_sugar.sh → refined.obj)
Step 5: Postprocess (postprocess.sh → Centerline + B-Spline + GeoJSON)
```

- **Autopilot-Modus:** `run_pipeline.sh` fragt nach Text-Prompt und Autopilot y/n. Bei y: alle weiteren Prompts werden mit Defaults übersprungen (Video-Komprimierung, SAM3-Auflösung, STS/SuGaR-Parameter, CloudCompare-Breakpoint, GCP-Reuse). Pipeline läuft komplett durch.
- **Vor Autopilot-Auswahl bleiben 3 Eingaben:** HuggingFace-Token (einmalig, dann in `.env`), Text-Prompt (was segmentieren), Autopilot y/n.

## Centerline-Extraktion (Container E, `src/cpp/src/main.cpp`)

- **Modi:** `single` (Default, robust) und `network` (experimentell).
- **`single`-Modus:** Voxeliert Mesh (0,1 m), Flood-Fill, topologieerhaltendes Thinning (DGtal `asymetricThinningScheme`), dann `extract_diameter()` = BFS vom ersten Skeleton-Voxel (scan-order-abhängig!) zum weitesten, nochmal BFS, kürzester Pfad dazwischen. EIN Pfad, ignoriert Spurs automatisch. Startpunkt ist willkürlich (bounding-Box-Ecke), nicht strukturell.
- **`network`-Modus:** Zerlegt Skeleton-Graphen an Junction-Voxeln in Äste. Schreibt `branch_id,component_id,x,y,z`. Bei reinen Zyklen (alle Knoten Grad 2) wird der Loop geschlossen (Start==Ende).
- **Skeleton-Qualität auf verrauschten Meshes:** Bei 0,1 m Voxeln und dünnen, unebenen Röhren erzeugt das 2D-Isthmus-erhaltende Thinning bushy Skeletons (2D-Medialflächen + Stachel → Junction alle 1–2 Voxel → 302 Mikro-Äste, alle < 0,75 m → `MIN_PATH_LENGTH`-Filter verwirft alles → 0 Pfade im network-Modus). `single` funktioniert, weil der BFS-Diameter-Pfad Spurs ignoriert.
- **`--one-isthmus`-Flag (neu, 07/2026):** Wechselt das Thinning auf `DGtal::functions::oneIsthmus<Complex>` (nur 1D-Isthmus, kollabiert 2D-Medialflächen zu Kurven). Skeleton: 508→261 Voxel, saubere 1D-Kurven, aber fragmentiert (Lücken 0,5–1 m, Röhren-Enden rezidivieren). Baustein für network-Modus-Experimente; begrenzender Faktor bleibt Mesh-Qualität.
- **Gotcha:** `std::function`-Lambda mit Referenz-Capture von lokalen Variablen (`isthmus_table`, `point_map`) → Dangling-Reference-Segfault, wenn das Lambda nach dem Block verwendet wird. Fix: Variablen vor dem `if` deklarieren.
- **Extractor-Pfade:** `centerline_local_raw.csv` (Roh-Pfad, `x,y,z` im single-Modus; `branch_id,component_id,x,y,z` im network-Modus) → `centerline_local.csv` (B-Spline-geglättet).

## B-Spline (`src/python/centerline_bspline.py`)

- **Implementierung:** Geklemmter uniformer B-Spline via De-Boor-Algorithmus (`uniform_bspline_point`). Padding: `[points[0]] * degree + points + [points[-1]] * degree`. Endpunkte werden interpoliert (geklammert).
- **Degree einstellbar** (`--degree`, Default 3): 1 = linear (Polylinie), 2 = quadratisch, 3 = kubisch. Env-Var `BSPLINE_DEGREE`. Regressionstest: Degree 3 weicht max. 4.77e-15 von alter kubischer Basis ab.
- **Eckensegmentierung** (`--segment-corners`, Default an): Fensterbasierte Corner-Detection (Fenster `--corner-window` Default 4, Min-Winkel `--corner-min-angle` Default 30°) unterdrückt Voxel-Treppenrauschen (45°-Stufen). Split am Corner; Corner-Punkt gehört zu beiden Segmenten → schließen exakt (0 mm Spalt). Env-Vars: `SEGMENT_CORNERS`, `SEGMENT_CORNER_WINDOW`, `SEGMENT_CORNER_ANGLE`.
- **Punktdichte:** `--samples-per-segment` (Default 4), Env `BSPLINE_SAMPLES_PER_SEGMENT`.
- **CSV-Schema:** `branch_id,component_id,x,y,z`. Wird von `transform_centerline.py` (Branch-Spalten durchgereicht), `centerline_geojson.py` (1 LineString pro Branch) konsumiert.
- **4× duplizierte CSV-Parsing-Logik** in `transform_centerline.py`, `centerline_bspline.py`, `centerline_geojson.py`, `centerline_graph_simplify.py` → faktorisieren in `centerline_io.py` (geplant).

## Georeferenzierung (`src/scripts/postprocess.sh`, umstrukturiert 07/2026)

- **Neuer Ablauf:** (1) Extractor → raw, (2) B-Spline → local, (3) lokales GeoJSON (`local_output.geojson`, SRS=LOCAL), (4) Georeferenzierung am ENDE.
- **Georeferenzierung-Priorität:** matrix.txt + anchor.txt vorhanden → volle 4×4-Transformation → `centerline_utm.csv` + `final_output.geojson` (EPSG:25832). Sonst → Fallback-Translation zu `FALLBACK_ANCHOR` (Default `567028.563,5516784.082,177`) → `centerline_fallback_georeferenced.csv` + `final_output_fallback_georeferenced.geojson`. Bricht **nicht** mehr ab.
- **OCR-Fallback:** Wenn `matrix.txt` fehlt aber `data/01_raw/matrix_screenshot.png` existiert und tesseract verfügbar → `ocr_matrix.py` läuft automatisch → `matrix.txt`.
- **`matrix.txt`-Format:** 16 Werte in 4 Zeilen (Komma oder Leerzeichen), letzte Zeile `0,0,0,1`, `#`-Kommentare erlaubt. Beispiel (real):
  ```
  -0.979,0.157,-0.123,-2.287
  -0.194,0.599,-0.776,2.658
  -0.048,0.784,0.618,-3.049
  0.000,0.000,0.000,1.000
  ```
- **`anchor.txt`-Format:** Exakt 3 Zahlen (Rechtswert, Hochwert, Höhe in m), Komma oder Leerzeichen. Zonen-Präfix `32U` NICHT in Datei (CRS wird erst bei GeoJSON-Export gesetzt). Wird von `prepare_gcp.py` aus erstem GCP der `gcp_coordinates.csv` erzeugt. Beispiel: `567028.563,5516784.082,175.230`.

## OCR / Tesseract (`src/python/ocr_matrix.py`)

- **Warum OCR nicht funktionierte (zwei Ursachen):**
  1. Container A (sam3-preprocess) hatte `tesseract-ocr` + `pytesseract` im Dockerfile, aber Image wurde nie neu gebaut → `tesseract: command not found`.
  2. Whitelist `-c tessedit_char_whitelist=0123456789.,-+ \n\r` unterdrückte Leerzeichenerkennung → alle Zahlen einer Zeile verschmolzen zu einem String; Timestamp `17:11:04` (Doppelpunkte nicht in Whitelist) wurde mit erster Zahl verbunden.
- **Fix (07/2026):** Whitelist entfernt (`--psm 6` allein), Timestamp-Präfix `[...]` wird herausgefiltert. Tesseract + pytesseract + pillow in **Container E** installiert (Dockerfile), OCR läuft dort automatisch am Ende. Rohe Tesseract-Ausgabe ohne Whitelist ist fast perfekt.
- **Container A** hat weiterhin tesseract im Dockerfile (für eigenständige OCR-Nutzung), aber Image muss neu gebaut werden (`docker compose build sam3-preprocess`).

## Perspektiventäuschung (Centerline-Loop)

- **Beobachtung:** Single-Mode-Pfad bildet Loop nur aus zwei exakt gegenüberliegenden Blickrichtungen. Erklärung: Start- und Endpunkt liegen ca. 24 cm auseinander in 3D. Blickrichtung (anti-)parallel zum Verbindungsvektor → beide projizieren auf denselben Bildpunkt → offener Bogen sieht wie geschlossener Loop aus. Von jeder anderen Richtung ist die Lücke sichtbar. Reine 3D→2D-Projektion, kein Code-Bug.

## COLMAP (`src/scripts/run_sfm.sh`)

- 4 Stagen: `feature_extractor` → `sequential_matcher` (overlap 20, guided_matching 1) → `mapper` (abs_pose_min_num_inliers 15, min_num_matches 10) → `model_converter` (bash-Loop sucht größtes Teilmodell).
- Dense MVS korrekt übersprungen.
- **Fehlende Optimierungen:** kein `--num_threads`, kein `--SiftExtraction.max_image_size` (Default 3200), `max_num_features 16384` (sehr hoch), kein `--ImageReader.mask_path` (Masks sind upstream vorhanden!), `database.db` wird每次 neu erzeugt, `colmap/colmap:latest` ungepinnt.
- **Geschätzter Speedup bei Optimierung: 50–70 %.**

## STS / SuGaR

- **Defaults (Autopilot):** `ITERATIONS=7000`, `STAGE2_ITERS=5000`, `COARSE_ITERATIONS=9001`, `MESH_VERTICES=200000`, `SURFACE_SAMPLE_COUNT=5000000`, `REFINEMENT_TIME=medium` (=7000 Refinement-Iter), `REGULARIZATION=dn_consistency`.
- **`STOP_AFTER_COARSE_MESH=1`** existiert, ist im Autopilot nicht verfügbar → skippt ~7000 Refinement + UV + Crop. Potenzieller „Screening"-Modus.
- **6 sequenzielle `docker compose run` zwischen STS→SuGaR** (object_init, train, copy-ply, filter_cable, opacity-rewrite, filter_cameras, sugar_train) → jeweils ~10–30 s CUDA-Init.
- **PLY wird 4× kopiert:** STS-Save → Full-Scene → gefiltert → Opazitäts-Rewrite → gestaged.
- **`filter_cable_pc.py` + `create_opacity_diagnostic_ply.py`** laden beide die volle PLY, könnten verschmolzen werden.
- **`prep_sts_scene.py`:** `cv2.imread(frame)` nur um Shape zu lesen → `PIL.Image.open().size` spart ~700 JPEG-Decodes.
- **Docker:** STS git clone nicht auf SHA gepinnt (SuGaR macht es richtig via `SUGAR_REF`). `TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0"` baut 6 Architekturen → Build ~6× langsamer als nötig. Container D ~10 GB (Miniconda + devel-CUDA + pytorch3d).

## Shell-Orchestrierung — Duplikation

- **`pipeline_lib.sh`** existiert mit `run_step_*`-Funktionen + `run_pipeline_from <step>`, wird aber von **keinem** Skript gesourced → tote Code.
- **`run_from_colmap.sh` / `run_from_sts.sh`** sind byte-identische Teilmengen von `run_pipeline.sh`.
- **`explain_*`-Helfer** 5× kopiert. **`ask_value`/`ask_config_value`/`ask_yes_no`** 3× kopiert.
- **Postprocess-Aufruf** 5× identisch. **Inline-Python „preserve full-scene PLY"** 4× kopiert mit `(_ for _ in ()).throw(...)`-Idiom.

## Python-Skripte — Code-Kultur

- **Produktionsreif (argparse, dataclasses, Fehlerbehandlung):** Centerline-Familie (`centerline_bspline.py`, `centerline_geojson.py`, `transform_centerline.py`, `centerline_graph_simplify.py`), `crop_mesh_multiview.py`, `filter_sugar_cameras_by_mask.py`, `create_opacity_diagnostic_ply.py`.
- **Explorativ (hardcodierte Pfade, `os._exit()`, `print("Error")+return`):** `extract_masks.py` (tot), `extract_masks_notebook_flow.py`, `prep_sts_scene.py`, `prepare_gcp.py`, `generate_hierarchical_masks.py` (tot), `evaluation.py` (Stub, tot), `ocr_matrix.py` (manuelles `sys.argv`).
- **Tote Skripte (kein Pipeline-Aufruf):** `extract_masks.py`, `generate_hierarchical_masks.py`, `evaluation.py`, `generate_synthetic_gcp.py`, `export_mask_review_samples.py`, `centerline_graph_simplify.py`.
- **Keine Tests** vorhanden (`tests/` fehlt).

## Daten-Verzeichnisse

| Verzeichnis | entsteht wie? |
|---|---|
| `data/01_raw/` | manuell (Eingabevideo + GCP-CSV) |
| `data/02_frames/` bis `data/09_evaluation/` | automatisch (Pipeline) |
| `data/hf_cache/` | automatisch (HuggingFace-Cache) |
| `data/sugar_output/` | automatisch (SuGaR-Checkpoints) |

## Repo-Umzug-Plan (in `PIPELINE_ANALYSE_PLAN.md` dokumentiert, nicht ausgeführt)

- Fresh `git init`, ein Initial-Commit mit Verweis auf Ursprungsrepo.
- `third_party/SuGaR` als Git-Submodule (`.gitmodules` verweist auf `MartinRapps/SuGaR @ 48bbfdd`).
- `ui/` und `docs/agent-memory-repo.md` werden mit übernommen.
- 6 tote Skripte nach `tools/`.
- Refactorings: `centerline_io.py`/`mask_paths.py`/etc. faktorisieren, `pipeline_lib.sh` ausbauen, `run_from_*.sh` zu `--from`-Wrappern, `.dockerignore`/`.gitignore`/`tests/`.

## Wichtige Env-Vars (Postprocess)

| Var | Default | Zweck |
|---|---|---|
| `CENTERLINE_MODE` | `single` | Extractor-Modus (single/network) |
| `VOXEL_SIZE` | `0.1` | Voxelgröße in m |
| `MIN_PATH_LENGTH` | `0.75` | Mindestastlänge in m |
| `BSPLINE_DEGREE` | `3` | B-Spline-Grad (1/2/3) |
| `BSPLINE_SAMPLES_PER_SEGMENT` | `4` | Punkte pro Segment |
| `SEGMENT_CORNERS` | `1` | Eckensegmentierung an/aus |
| `SEGMENT_CORNER_WINDOW` | `4` | Fenstergröße Corner-Detection |
| `SEGMENT_CORNER_ANGLE` | `30` | Min-Winkel in Grad |
| `FALLBACK_ANCHOR` | `567028.563,5516784.082,177` | Fallback-Translation bei fehlender Georeferenzierung |
| `GEOJSON_SRS` | `EPSG:25832` | SRS für GeoJSON-Export |
| `ONE_ISTHMUS` | (CLI-Flag) | 1D-only-Thinning im Extractor |

## Wichtige Dateien (geändert in dieser Session)

| Datei | Änderung |
|---|---|
| `src/cpp/src/main.cpp` | `--one-isthmus`-Flag, Dangling-Reference-Fix |
| `src/python/centerline_bspline.py` | De-Boor-Implementierung (Degree 1–5), Eckensegmentierung, `--degree`/`--segment-corners` |
| `src/python/centerline_graph_simplify.py` | NEU (Spur-Pruning, Junction-Clustering für network-Modus) |
| `src/scripts/postprocess.sh` | Georeferenzierung ans Ende, lokales GeoJSON, Fallback, OCR-Integration, Fehlerbehandlung |
| `src/python/ocr_matrix.py` | Whitelist entfernt, Timestamp-Filter |
| `docker/container-e-postprocess/Dockerfile` | tesseract-ocr + pytesseract + pillow |
| `run_pipeline.sh` | Autopilot-Absicherung (GCP/Breakpoint), OCR-Dialog durch Hinweis ersetzt |
| `README.md` / `setup_guide.md` | Centerline-Ablauf, B-Spline-Degree, Georeferenzierung, Fallback |
| `Themenfindung/Expose_PA_BA.tex` | Centerline-Abschnitt, Dateiformate matrix/anchor, [GELÖST]-Eintrag Skeleton, OCR-Abschnitt aktualisiert |
| `PIPELINE_ANALYSE_PLAN.md` | NEU (Master-Plan Analyse + Umzug) |

## Gotchas & Lessons Learned

- **Voxel-Skeleton auf verrauschten Meshes:** 2D-Isthmus-erhaltendes Thinning erzeugt bushy Graphen (Sheets + Spurs). `single`-Modus robust (BFS-Diameter ignoriert Spurs). `network`-Modus braucht Junction-Clustering + Spur-Pruning + Gap-Bridging → fragil. Coarsere Voxelgröße (0,15–0,25 m) fragmentiert stattdessen.
- **`set -e` + nicht-leere Fehler-Datei:** Extractor schreibt CSV-Header, dann Exception → Datei nicht leer → `[[ ! -s ]]`-Check passiert → Pipeline fährt mit leerer CSV fort. Fix: `[[ $(wc -l) -lt 2 ]]` prüfen + stderr ausgeben.
- **Docker `--break-system-packages`:** Ubuntu 22.04's pip (22.0.2) kennt diesen Flag nicht → Build fehlschlägt. Auf 22.04 weglassen, auf 24.04 notwendig.
- **Float-Repräsentation Container vs. Host:** Dieselbe De-Boor-Berechnung liefert `-1.48082` (Host) vs. `-1.4808199999999998` (Container) — 1-ulp-Unterschied durch Summationsreihenfolge. Für Geometrie irrelevant (1e-15).
- **SuGaR-Submodule:** Lokaler HEAD `48bbfdd` (Martins Fork mit Masken-Mods), Dockerfile pinnt auf `7c10c4ae` (Anttwo-Original). Dev-Overlay nutzt lokalen Fork-Stand. Für Image-Builds mit Fork-Stand: `SUGAR_REF=48bbfdd` im Dockerfile setzen.
- **Exposé-Kompilieren:** Immer `pdflatex -interaction=nonstopmode -halt-on-error` ausführen nach Edits — fängt `_`-in-`\texttt{}`-Fehler ab.
