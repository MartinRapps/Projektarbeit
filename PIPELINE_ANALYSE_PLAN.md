# Pipeline-Analyse, Exposé-Ergänzung und Repo-Umzug — Master-Plan

> Stand: 18.07.2026
> Status: Analyse abgeschlossen, Plan zur Genehmigung vorgelegt.
> Repo-Umzug wird **nicht** automatisch durchgeführt — nur Exposé-Ergänzung und diese Dokumentation.

---

## 1. Effizienz- und Verbesserungsanalyse

### 1.1 Shell-Orchestrierung — starke Duplikation

| Befund | Detail |
|---|---|
| `pipeline_lib.sh` ist tote Code | Definiert saubere `run_step_*`-Funktionen + `run_pipeline_from <step>`, wird aber von keinem Skript gesourced. |
| `run_from_colmap.sh` / `run_from_sts.sh` | Byte-identische Teilmengen von `run_pipeline.sh` (~130 Zeilen kopiert). |
| `run_sugar_only.sh` | Veraltet — ruft nicht-maskenbewusstes `extract_mesh.py` direkt auf. |
| `explain_*`-Helfer | 5× kopiert (`run_pipeline.sh`, `run_from_sts.sh`, `run_from_sugar.sh`, `run_masked_sugar.sh`, `run_coarse_mesh_ablation.sh`). |
| `ask_value` / `ask_config_value` / `ask_yes_no` | 3 nahezu identische Varianten in 3 Skripten. |
| `docker compose run --rm …` | ~30× ausgeschrieben, kein `run_in <service>`-Helfer, kein `--no-deps`. |
| Inline-Python „preserve full-scene PLY" | 4× kopiert mit obskurem `(_ for _ in ()).throw(...)`-Idiom. |
| Postprocess-Aufruf | 5× identisch. |

**Maßnahme:** `pipeline_lib.sh` ausbauen, `run_from_*.sh` zu Dünn-Wrappern (`run_pipeline.sh --from <step>`) reduzieren, alle interaktiven Helfer zentralisieren. Erwartete Reduktion der Shell-Codebasis: ~40 %.

### 1.2 Python — zwei Code-Kulturen, Duplikation, tote Skripte

**Tote / explorative Skripte (kein Aufruf aus der Pipeline):**

| Skript | Grund | Umgang |
|---|---|---|
| `extract_masks.py` | superseded durch `extract_masks_notebook_flow.py` | nicht ins neue Repo |
| `generate_hierarchical_masks.py` | superseded durch inline-Block in `extract_masks_notebook_flow.py` | nicht ins neue Repo |
| `evaluation.py` | Stub ohne CLI, kein Aufruf | nicht ins neue Repo |
| `generate_synthetic_gcp.py` | Testdaten-Generator | nach `tools/` |
| `export_mask_review_samples.py` | interaktives QA-Tool mit `input()` | nach `tools/` |
| `centerline_graph_simplify.py` | Research-Vorläufer von `centerline_bspline.py` | nach `tools/` |

**4× duplizierte CSV-Parsing-Logik** in `transform_centerline.py`, `centerline_bspline.py`, `centerline_geojson.py`, `centerline_graph_simplify.py` → faktorisieren in `centerline_io.py`.

**Duplizierte Masken-Helfer** (`mask_candidates` / `find_mask` / `frame_id`) in `crop_mesh_multiview.py` + `filter_sugar_cameras_by_mask.py` → `mask_paths.py`.

**Inkonsistente Code-Kultur:**
- Centerline-Familie = produktionsreif (argparse, dataclasses, Fehlerbehandlung).
- SAM3/STS-Familie = explorativ (hardcodierte `/data/...`-Pfade, `os._exit()`, `print("Error")+return`, gemischt DE/EN).

**Konkrete Ineffizienzen:**
- `prep_sts_scene.py`: `cv2.imread(frame)` nur um Shape `(h,w)` zu lesen → `PIL.Image.open().size` spart ~700 volle JPEG-Decodes.
- `filter_cable_pc.py` + `create_opacity_diagnostic_ply.py`: laden beide die volle PLY, könnten zu einem Skript verschmolzen werden (halbe I/O auf mehr-GB-PLYs).
- `centerline_geojson.py`: bbox über 6 separate Generator-Passes → einmalig berechnen.
- Keine Tests vorhanden (`tests/` fehlt komplett).

**Maßnahme:** Faktorisierung in gemeinsame Module (`centerline_io.py`, `mask_paths.py`, `hierarchical_masks.py`, `cameras_json.py`, `cli_utils.py`); Standardisierung auf `argparse` und ein einheitliches Fehlerbehandlungs-Idiom; Aufbau eines `tests/`-Moduls für die numerisch gut isolierbaren Centerline-Funktionen (`bspline`, `find_corners`, `segment_path`).

### 1.3 Docker — Bloat, fehlende Reproduzierbarkeit

| Container | Problem |
|---|---|
| **Alle** | Kein `.dockerignore` → `build context: .` schickt `data/`, Logs, `.venv/`, `Ausarbeitung/` an den Daemon. Keine `image:`-Tags → impliziter Rebuild-Check. Redundantes `gpus: all` + `deploy.resources`. |
| **A (sam3)** | `devel`-Image statt `runtime` (~2 GB mehr). `tesseract-ocr` doppelt (auch in E). |
| **B (colmap)** | `colmap/colmap:latest` — nicht gepinnt, Flag-Kompatibilität kann brechen. |
| **C (sts)** | STS git clone **nicht auf SHA gepinnt** (SuGaR macht es richtig). `TORCH_CUDA_ARCH_LIST` baut 6 Architekturen → Build ~6× langsamer. `devel`-Image. |
| **D (sugar)** | Schwerster Container (~10 GB): Miniconda + devel-CUDA + pytorch3d. `chmod -R 777 /opt/sugar`. Multi-Stage-Build würde ~halbieren. |
| **E (postprocess)** | Behält `build-essential`/`cmake`/`git`/`libboost-all-dev`/`libgdal-dev`/`libeigen3-dev` im finalen Image (nur für Build nötig). Multi-Stage würde halbieren. |
| **compose** | `sam3-preprocess` überladen (SAM3 + ffmpeg + GCP + STS-prep). `docker-compose.sugar-dev.yml` wird von `run_masked_sugar.sh` **immer** mit `-f` geladen — überraschend für Produktivläufe. |

**Maßnahme:**
- `.dockerignore` anlegen (schließt `data/`, `*.log`, `.venv/`, `Ausarbeitung/`, `Themenfindung/`, `docs/`, `.git/` aus).
- Alle Images auf konkrete Tags pinnen (`colmap/colmap:4.0.4-cuda`, STS auf SHA).
- Multi-Stage-Builds für C/D/E (devel-Buildphase, schlankes Runtime-Image).
- `TORCH_CUDA_ARCH_LIST` auf Ziel-GPU festlegen (z. B. nur `8.9` für RTX 40xx).
- `image:`-Felder in `docker-compose.yml` setzen, `tesseract-ocr` nur in Container E.
- `docker-compose.sugar-dev.yml` als opt-in via Env-Var (`SUGAR_USE_DEV_FORK=1`).

### 1.4 COLMAP-Speedups (`run_sfm.sh`)

| Maßnahme | geschätzte Wirkung |
|---|---|
| `database.db` cachen (Feature-Extraction überspringen wenn vorhanden) | **hoch** (größter Iterations-Gewinn) |
| `--ImageReader.mask_path` setzen (Masks sind upstream vorhanden!) → Features nur auf Objekt | **hoch** |
| `max_num_features` 16384 → 8000 | **mittel-hoch** |
| `--SiftExtraction.max_image_size` ~2000 setzen (Default 3200) | **mittel-hoch** |
| `guided_matching 1` → 0 bei hochüberlappendem Video (halbiert Matching) | **mittel** |
| `--num_threads` explizit an alle Stages | **mittel** |
| `--Mapper.max_num_models 1` → eliminiert bash-Largest-Model-Loop | **mittel** |
| `colmap/colmap:latest` → `:4.0.4-cuda` pinnen | niedrig (Reproduzierbarkeit) |
| Redundante `model_converter`-Branches zusammenführen | niedrig |

**Geschätzter Iterationsgewinn bei Replay: ~50–70 %.**

### 1.5 STS- und SuGaR-Speedups

| Maßnahme | geschätzt |
|---|---|
| `STOP_AFTER_COARSE_MESH=1` + `REFINEMENT_TIME=short` als „Screening"-Autopilot-Modus (skippt ~7000 Refinement + UV + Crop) | **hoch** |
| `SURFACE_SAMPLE_COUNT` 5M → 2M, `MESH_VERTICES` 200k → 50k für Screening | **hoch** |
| `--poisson-depth` exposen (in `extract_mesh.py` vorhanden, Default 10 → 8) | **mittel** |
| 6 sequenzielle `docker compose run` zwischen STS→SuGaR zu ≤2 zusammenfassen (jeweils ~10–30 s CUDA-Init) | **mittel** (~2 min/run) |
| STS git clone auf SHA pinnen (wie SuGaR) | niedrig (Build) |
| `TORCH_CUDA_ARCH_LIST` auf Ziel-GPU pinnen → CUDA-Build ~6× | **mittel** (Build) |
| `filter_cable_pc.py` + `create_opacity_diagnostic_ply.py` verschmelzen (eine PLY-Load) | **mittel** |
| `prep_sts_scene.py`: `PIL.Image.open().size` statt `cv2.imread` für Shape; Masken-Schreiben parallelisieren | **mittel** |
| AMP/fp16 im STS-Trainer (Code-Änderung upstream) | **mittel-hoch** (~1.4×, 50 % VRAM) |
| Multi-Stage-Docker-Builds (devel→runtime) für C + D + E | **mittel** (Image-Größe halbiert, schneller Cold-Start) |

**Geschätzter Gewinn im Screening-Modus: ~60–80 %, im Produktivlauf ~30–40 %.**

---

## 2. Exposé-Neuabschnitt (Phase 1)

**Position:** neue `\section{Effizienzanalyse und Optimierungspotenzial}` zwischen „Risikomanagement und Datenhandling" und „Wissenschaftliche Evaluationsmetriken" (~Zeile 150 im Exposé).

**Inhalt (6 Unterabschnitte):**
1. Shell-Orchestrierung und Code-Duplikation
2. Python-Codequalität und tote Skripte
3. Docker-Optimierung
4. COLMAP-Beschleunigung
5. STS- und SuGaR-Beschleunigung
6. Repository-Konsolidierung

### 2.1 Vorgesehener LaTeX-Text

```latex
\section{Effizienzanalyse und Optimierungspotenzial}

Im Verlauf der Implementierung erwies sich die Pipeline als funktionstüchtig,
offenbart jedoch an mehreren Stellen signifikantes Effizienz- und
Wartbarkeitspotenzial. Die folgenden Befunde sind als begründeter
Maßnahmenkatalog für die weitere Entwicklung zu lesen, nicht als bereits
umgesetzte Optimierung.

\subsection{Shell-Orchestrierung und Code-Duplikation}
Die fünf Einstiegsskripte (\texttt{run\_pipeline.sh}, \texttt{run\_from\_colmap.sh},
\texttt{run\_from\_sts.sh}, \texttt{run\_from\_sugar.sh}, \texttt{run\_sugar\_only.sh})
enthalten großteils byte-identische Kopien derselben Blöcke: die
STS-Trainingskonfiguration, den SuGaR-Aufruf, den Postprocessing-Schritt sowie
die \texttt{explain\_regularization}- und \texttt{ask\_value}-Helfer (jeweils bis
zu fünf Kopien). Eine bereits angelegte Shared-Library (\texttt{pipeline\_lib.sh}
mit \texttt{run\_pipeline\_from <step>}) wird von keinem Skript gesourced und ist
damit tote Code. \textbf{Maßnahme:} \texttt{pipeline\_lib.sh} vollständig
ausbauen, die \texttt{run\_from\_*.sh}-Skripte zu Dünn-Wrappern
(\texttt{run\_pipeline.sh -{}-from colmap}) reduzieren und alle interaktiven
Helfer zentralisieren. Erwartete Reduktion der Shell-Codebasis: ca.~40\,\%.

\subsection{Python-Codequalität und tote Skripte}
Sechs der 17 Python-Skripte werden von keinem Pipelineschritt referenziert
(\texttt{extract\_masks.py}, \texttt{generate\_hierarchical\_masks.py},
\texttt{evaluation.py}, \texttt{generate\_synthetic\_gcp.py},
\texttt{export\_mask\_review\_samples.py}, \texttt{centerline\_graph\_simplify.py})
und werden in ein \texttt{tools/}-Verzeichnis verschoben. Die vier
Centerline-Skripte reimplementieren jeweils dieselbe CSV-Lese-Logik
(\texttt{branch\_id}, \texttt{component\_id}, \texttt{x}, \texttt{y}, \texttt{z});
\texttt{crop\_mesh\_multiview.py} und \texttt{filter\_sugar\_cameras\_by\_mask.py}
duplizieren Maskenpfad-Helfer. Die SAM3-/STS-Familie nutzt teilweise hartcodierte
\texttt{/data/...}-Pfade, \texttt{os.\_exit()} und \texttt{print("Error")+return}
statt Ausnahmen. \textbf{Maßnahme:} Faktorisierung in gemeinsame Module
(\texttt{centerline\_io.py}, \texttt{mask\_paths.py},
\texttt{hierarchical\_masks.py}, \texttt{cameras\_json.py}, \texttt{cli\_utils.py}),
Standardisierung auf \texttt{argparse} und ein einheitliches
Fehlerbehandlungs-Idiom sowie Aufbau eines \texttt{tests/}-Moduls für die
numerisch gut isolierbaren Centerline-Funktionen
(\texttt{bspline}, \texttt{find\_corners}, \texttt{segment\_path}).

\subsection{Docker-Optimierung}
Es existiert keine \texttt{.dockerignore}, sodass jeder Build den gesamten
Projektbaum inklusive \texttt{data/}, Logs und \texttt{.venv/} an den Daemon
sendet. Das COLMAP-Image ist auf \texttt{colmap/colmap:latest} gepinnt und damit
nicht reproduzierbar; der STS-\texttt{git clone} ist nicht auf einen Commit
festgelegt. Die Container A, C und D nutzen \texttt{devel}-Basisimages, obwohl
zur Laufzeit nur die kompilierten CUDA-Erweiterungen benötigt werden;
\texttt{TORCH\_CUDA\_ARCH\_LIST} baut sechs Architekturen, was den Build
ca.~6-fach verlangsamt. Container E behält die gesamten Build-Abhängigkeiten
(\texttt{build-essential}, \texttt{libboost-all-dev}, \texttt{libgdal-dev})
im finalen Image. \texttt{tesseract-ocr} ist in Container A und E doppelt
installiert. \textbf{Maßnahme:} \texttt{.dockerignore} anlegen, alle Images auf
konkrete Tags pinnen, Multi-Stage-Builds für C/D/E (devel-Buildphase, schlankes
Runtime-Image), \texttt{TORCH\_CUDA\_ARCH\_LIST} auf die Ziel-GPU festlegen,
\texttt{image:}-Felder in \texttt{docker-compose.yml} setzen und
\texttt{tesseract-ocr} nur in Container E vorhalten.

\subsection{COLMAP-Beschleunigung}
Das SfM-Skript übergibt weder \texttt{-{}-num\_threads} noch
\texttt{-{}-SiftExtraction.max\_image\_size} und nutzt mit
\texttt{max\_num\_features 16384} einen sehr hohen Wert. Trotz vorhandener
SAM-3-Masken wird \texttt{-{}-ImageReader.mask\_path} nicht gesetzt, sodass
Features auch im Hintergrund extrahiert werden. Die \texttt{database.db} wird
bei jedem Lauf neu erzeugt. Ein Bash-Loop sucht das größte Teilmodell, was
durch \texttt{-{}-Mapper.max\_num\_models 1} entfällt. \textbf{Maßnahme:}
Mask-Pfad setzen, \texttt{max\_num\_features} auf $\sim$8000 senken,
\texttt{max\_image\_size} auf $\sim$2000 begrenzen, \texttt{guided\_matching}
bei hochüberlappendem Video deaktivieren, \texttt{database.db} cachen und
COLMAP auf \texttt{colmap/colmap:4.0.4-cuda} pinnen. Geschätzter
Iterationsgewinn bei Replay: ca.~50--70\,\%.

\subsection{STS- und SuGaR-Beschleunigung}
Zwischen STS-Training und SuGaR-Meshing werden sechs sequenzielle
\texttt{docker compose run}-Aufrufe gestartet, die jeweils ca.~10--30\,s
CUDA-Kontextinitialisierung kosten. Die Punktfolke wird vierfach kopiert
(STS-Save $\to$ Full-Scene $\to$ gefiltert $\to$ Opazitäts-Rewrite $\to$ gestaged).
Das bereits implementierte Flag \texttt{-{}-stop\_after\_coarse\_mesh} ist im
Autopilot nicht verfügbar; \texttt{REFINEMENT\_TIME=medium} (7000 Iterationen)
ist für Screening-Läufe konservativ. \texttt{filter\_cable\_pc.py} und
\texttt{create\_opacity\_diagnostic\_ply.py} laden beide die volle PLY und
könnten verschmolzen werden. \texttt{prep\_sts\_scene.py} dekodiert mit
\texttt{cv2.imread} vollständige JPEGs, nur um die Bildgröße abzufragen.
\textbf{Maßnahme:} einen „Screening"-Autopilot-Modus
(\texttt{STOP\_AFTER\_COARSE\_MESH=1}, \texttt{REFINEMENT\_TIME=short},
reduzierte Sample-/Vertex-Zahlen) einführen, die sechs Container-Aufrufe zu
$\leq$2 zusammenfassen, die Poisson-Tiefe als durchreichbares Flag exposen,
die PLY-Skripte verschmelzen und \texttt{PIL.Image.open().size} statt
\texttt{cv2.imread} nutzen. Mittelfristig: AMP/fp16 im STS-Trainer
($\sim$1{,}4$\times$ Speedup, $\sim$50\,\% weniger VRAM). Geschätzter Gewinn
im Screening-Modus: ca.~60--80\,\%, im Produktivlauf ca.~30--40\,\%.

\subsection{Repository-Konsolidierung}
Die bisherige Arbeitskopie vereint Pipeline-Code, Third-Party-Quellen
(\texttt{third\_party/SuGaR}), Datensätze, Web-UI, Schreibprojekte
(\texttt{Ausarbeitung}, \texttt{Vorlage}, \texttt{Themenfindung}) und
Experiment-Skripte in einem Repository. Für die Übergabe und weitere
Wartung wird die Pipeline in ein eigenes, sauber strukturiertes Repository
überführt: ein einziger Einstieg (\texttt{run\_pipeline.sh -{}-from <step>}),
geteilte Module unter \texttt{src/python/}, diagnostische Skripte unter
\texttt{tools/}, ein \texttt{tests/}-Verzeichnis und das Exposé unter
\texttt{docs/}. Third-Party-Quellen, Datensätze, Web-UI und Schreibprojekte
verbleiben im archivierten Ursprungsrepo. Der Umzug erfolgt als
\texttt{git init} mit einem sauberen Initial-Commit, der das Ursprungsrepo
referenziert; die bisherige Historie bleibt im archivierten Repo lückenlos
erhalten.
```

> **Hinweis:** Der Text gibt den Stand der Analyse korrekt wieder. Falls `third_party/SuGaR`, `ui/` und `docs/agent-memory-repo.md` (siehe Abschnitt 3) mit umgezogen werden, ist der letzte Unterabschnitt entsprechend anzupassen („Third-Party-Quellen … verbleiben im archivierten Ursprungsrepo" → „SuGaR wird als Git-Submodule des eigenen Forks eingebunden; die Web-UI und die Agent-Memory-Dokumentation werden mit überführt").

---

## 3. Repo-Umzug (Phase 2)

### 3.1 Entscheidungen

- **Fresh `git init`**, ein sauberer Initial-Commit mit Verweis auf das Ursprungsrepo.
- `third_party/SuGaR` als **bestehendes Git-Submodule** (`.gitmodules` unverändert übernommen, referenziert `https://github.com/MartinRapps/SuGaR.git` @ `48bbfdd` — dein Fork mit maskenbewussten Modifikationen).
- `ui/` und `docs/agent-memory-repo.md` werden mit übernommen (Weiterentwicklung gewünscht).
- `data/01_raw/.gitkeep` als Platzhalter; Rest von `data/` in `.gitignore` (wird on-demand von der Pipeline erstellt: `02_frames` bis `09_evaluation`, `hf_cache`, `sugar_output`).
- 6 tote/explorative Skripte nach `tools/`.

### 3.2 Zielstruktur

```
scan2bim-pipeline/
├── README.md  /  setup_guide.md  /  .env.example  /  .dockerignore  /  .gitignore
├── .gitmodules                      # verweist auf MartinRapps/SuGaR @ 48bbfdd
├── run_pipeline.sh                  # einziger Einstieg mit --from <step>
├── prepare_sugar_input.sh
├── run_masked_sugar.sh
├── run_multiview_crop.sh
├── docker-compose.yml  /  docker-compose.sugar-dev.yml
├── docker/
│   ├── container-a-sam3/Dockerfile
│   ├── container-b-colmap/Dockerfile
│   ├── container-c-sts/Dockerfile
│   ├── container-d-sugar/Dockerfile
│   └── container-e-postprocess/Dockerfile
├── src/
│   ├── scripts/
│   │   ├── pipeline_lib.sh          # ausgebaut (shared library)
│   │   ├── run_sfm.sh
│   │   └── postprocess.sh
│   ├── python/
│   │   ├── centerline_io.py         # NEU: geteiltes CSV-I/O
│   │   ├── mask_paths.py            # NEU: geteilte Masken-Helfer
│   │   ├── hierarchical_masks.py    # NEU: geteilte Erosion
│   │   ├── cameras_json.py          # NEU: geteilter Camera-Loader
│   │   ├── cli_utils.py             # NEU: einheitlicher CLI-Wrapper
│   │   ├── centerline_bspline.py
│   │   ├── centerline_geojson.py
│   │   ├── transform_centerline.py
│   │   ├── ocr_matrix.py
│   │   ├── prepare_gcp.py
│   │   ├── prep_sts_scene.py
│   │   ├── extract_masks_notebook_flow.py
│   │   ├── filter_cable_pc.py
│   │   ├── filter_sugar_cameras_by_mask.py
│   │   ├── create_opacity_diagnostic_ply.py
│   │   └── crop_mesh_multiview.py
│   └── cpp/
│       ├── CMakeLists.txt
│       └── src/main.cpp
├── third_party/
│   └── SuGaR                         # git submodule (MartinRapps/SuGaR @ 48bbfdd)
├── ui/                               # Web-UI (server.py, start.sh, public/)
├── tools/                            # diagnostisch / experimentell
│   ├── run_coarse_mesh_ablation.sh
│   ├── centerline_graph_simplify.py
│   ├── export_mask_review_samples.py
│   └── generate_synthetic_gcp.py
├── tests/
│   ├── test_centerline_bspline.py
│   ├── test_centerline_io.py
│   └── test_find_corners.py
├── data/
│   └── 01_raw/.gitkeep              # Eingabeverzeichnis (User befüllt)
└── docs/
    ├── Expose_PA_BA.tex              # + Abbildungen
    └── agent-memory-repo.md
```

### 3.3 Nicht übernehmen (bleiben im archivierten Ursprungsrepo)

| Pfad | Grund |
|---|---|
| `Ausarbeitung/`, `Vorlage/` | Schreibprojekte, nicht Pipeline-relevant |
| `Themenfindung/` (außer Exposé → `docs/`) | Schreibprojekte |
| `run_from_colmap.sh`, `run_from_sts.sh`, `run_from_sugar.sh` | werden zu `--from`-Wrappern |
| `run_sugar_only.sh`, `run_sam3.sh`, `sam3_1_Video.sh` | veraltet / Duplikate |
| `clean_data_interactive.sh` | One-off |
| `*.log` (`extract_masks_run.log`, `output_run.log`, `texput.log`) | Logs |
| `sam3.1_video_predictor_example.ipynb` | explorativ |
| `SAM3.1_Image_and_Video.json` | explorativ |
| `arbeitsablauf.md` | Projekt-spezifische Notiz |
| `.agents/`, `skills-lock.json` | opencode-Konfiguration |
| `extract_masks.py`, `evaluation.py`, `generate_hierarchical_masks.py` | tote Skripte (nicht nach `tools/`, da eindeutig superseded) |

### 3.4 SuGaR-Submodule — Details

- Lokaler Zustand: `third_party/SuGaR` ist bereits ein Git-Submodule mit `origin = https://github.com/MartinRapps/SuGaR.git` und `upstream = https://github.com/Antwo/SuGaR.git`.
- Lokaler HEAD: `48bbfdd "masked SuGaR updates"` (deine maskenbewussten Modifikationen, in deinen Fork gepusht).
- Dockerfile pinnt auf `SUGAR_REF=7c10c4ae…` (ursprünglicher Anttwo-Stand) für Image-Builds.
- Dev-Overlay (`docker-compose.sugar-dev.yml`) mountet `./third_party/SuGaR:/opt/sugar` → nutzt deinen Fork-Stand zur Laufzeit.
- **Beim Umzug:** `.gitmodules` unverändert übernehmen. Nach `git clone --recursive <neues-repo>` wird SuGaR @ `48bbfdd` ausgecheckt. Optional später: `SUGAR_REF` im Dockerfile auf `48bbfdd` aktualisieren, damit auch Image-Builds deinen Fork-Stand nutzen.

### 3.5 `data/` — automatisch vs. manuell

| Verzeichnis | entsteht wie? |
|---|---|
| `data/01_raw/` | **manuell** — User legt Eingabevideo + GCP-CSV ab. `.gitkeep` hält Verzeichnis im Clone. |
| `data/02_frames/` | automatisch (SAM3-Frame-Extraktion) |
| `data/03_masks/` | automatisch (SAM3) |
| `data/04_sfm/` | automatisch (COLMAP) |
| `data/05_3dgs/` | automatisch (STS) |
| `data/06_mesh/` | automatisch (SuGaR) |
| `data/07_centerline/` | automatisch (`mkdir -p` in `postprocess.sh`) |
| `data/08_gis/` | automatisch (`mkdir -p` in `postprocess.sh`) |
| `data/09_evaluation/` | automatisch (Evaluation) |
| `data/hf_cache/` | automatisch (HuggingFace-Cache) |
| `data/sugar_output/` | automatisch (SuGaR-Checkpoints) |

→ `data/` (außer `01_raw/.gitkeep`) in `.gitignore`.

### 3.6 Refactorings während des Umzugs

1. **`centerline_io.py`** — kanonischer Reader/Writer für `branch_id,component_id,x,y,z`-CSV. Dünnn-Wrapper für `transform_centerline.py`, `centerline_bspline.py`, `centerline_geojson.py`.
2. **`mask_paths.py`** — `frame_id_from_image_name`, `iter_mask_candidates`, `find_mask`, `load_mask` für `crop_mesh_multiview.py` + `filter_sugar_cameras_by_mask.py`.
3. **`hierarchical_masks.py`** — `to_binary_mask`, `write_hierarchical_masks` für `extract_masks_notebook_flow.py`, `prep_sts_scene.py`.
4. **`cameras_json.py`** — geteilter Camera-Loader (list-or-`{frames:[...]}`).
5. **`cli_utils.py`** — einheitlicher `if __name__ == '__main__': try/except`-Wrapper.
6. **`pipeline_lib.sh`** ausbauen: `configure_sam3_frame_resolution`, `configure_object_filter`, `configure_sugar_values`, alle `explain_*`-Helfer zentralisieren, `run_step_sam3` mit `SAM3_FRAME_MAX_SIDE`-Forwarding.
7. **`run_from_*.sh`** zu Dünn-Wrappern: `run_pipeline.sh --from colmap|sts|sugar`.
8. **`.dockerignore`** anlegen (schließt `data/`, `*.log`, `.venv/`, `Ausarbeitung/`, `Themenfindung/`, `docs/`, `.git/` aus).
9. **`.env.example`** anlegen (mit allen Env-Vars dokumentiert).
10. **`.gitignore`** anlegen (`data/` außer `01_raw/.gitkeep`, `*.log`, `__pycache__/`, `.venv/`, etc.).
11. **`tests/`** anlegen (Unit-Tests für `bspline`, `find_corners`, `segment_path`, `centerline_io`).

### 3.7 Umzug-Schritte

1. Neues Repo-Verzeichnis erstellen: `mkdir scan2bim-pipeline && cd scan2bim-pipeline && git init`.
2. `.gitmodules` + `third_party/SuGaR` als Submodule einbinden:
   ```
   git submodule add https://github.com/MartinRapps/SuGaR.git third_party/SuGaR
   cd third_party/SuGaR && git checkout 48bbfdd && cd ../..
   git submodule update --init --recursive
   ```
3. Dateien gemäß Zielstruktur kopieren (essentielle Pipeline-Skripte, Docker, src/, ui/, docs/).
4. Refactorings durchführen (shared Modules, pipeline_lib.sh, `--from`-Wrapper, .dockerignore, .gitignore, .env.example, tests/).
5. `data/01_raw/.gitkeep` anlegen, Rest von `data/` in `.gitignore`.
6. 6 tote/explorative Skripte nach `tools/` verschieben.
7. Initial-Commit mit Verweis auf Ursprungsrepo:
   ```
   git add -A
   git commit -m "Initial commit: scan2bim-pipeline (aus Projektarbeit-Repo ausgegründet)"
   ```
8. Ursprungsrepo unangetastet lassen (Archiv).
9. Optional: neues Repo zu GitHub pushen (`git remote add origin …`).

---

## 4. Offene Punkte / Empfehlungen

- **Exposé-Abschnitt (Phase 1)** ist bereit zum Einfügen. Der LaTeX-Text in Abschnitt 2.1 ist vollständig und kompilierfähig. **Warten auf Freigabe.**
- **Repo-Umzug (Phase 2)** wird **nicht automatisch** durchgeführt. Dieser Plan dient als Vorlage für die manuelle Umsetzung oder eine spätere Session.
- **`SUGAR_REF` im Dockerfile** auf `48bbfdd` aktualisieren? Optional — aktuell nutzt Image-Build den Anttwo-Stand, Dev-Overlay deinen Fork. Falls Image-Builds auch deinen Fork nutzen sollen, Anpassung nötig.
- **Screening-Autopilot-Modus** als zusätzliche Option in `run_pipeline.sh` (neben normalem Autopilot) wäre ein schneller Gewinn für die Iteration — unabhängig vom Repo-Umzug umsetzbar.
