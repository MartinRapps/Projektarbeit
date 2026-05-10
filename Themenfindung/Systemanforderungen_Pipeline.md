# Systemanforderungen: Scan-to-BIM Pipeline

> [!NOTE]
> Stand: Mai 2026. Alle Angaben basieren auf den offiziellen GitHub-Repos und Dokumentationen.

## Übersicht: Kompatibilitätsmatrix

| Tool | Python | PyTorch | CUDA | Min. VRAM | OS | Sprache | Code verfügbar? |
|------|--------|---------|------|-----------|------|---------|-----------------|
| **COLMAP** | - (C++) | - | 11.x / 12.x | 2 GB+ | Win/Linux/Mac | C++ | ✅ Open Source |
| **gsplat** | 3.10-3.12 | 2.0+ | 11.8 / 12.x | 8 GB+ | Win/Linux | Python/CUDA | ✅ Open Source |
| **nerfstudio** | 3.10-3.12 | 2.1+ | 11.8 | 8-12 GB+ | Win/Linux | Python/CUDA | ✅ Open Source |
| **SuGaR** | 3.9 | 2.0.1 | **11.8** | **12 GB+** | Win*/Linux | Python/CUDA | ✅ Open Source |
| **Gaussian Grouping** | **3.8** | **1.12.1** | **11.3** | 8-12 GB | Win/Linux | Python/CUDA | ✅ Open Source |
| **Georef. (klassisch)** | 3.10 | - | - | < 1 GB | Win/Linux | Python (numpy) | Eigenes Skript |
| **DGtal** | - (C++) | - | - (CPU) | < 1 GB | Win/Linux/Mac | C++ | ✅ Open Source |

---

## 1. COLMAP (Structure-from-Motion)

- **Repo:** [github.com/colmap/colmap](https://github.com/colmap/colmap)
- **Funktion:** SfM + Dense MVS (Baseline)
- **GPU:** NVIDIA GPU mit CUDA **zwingend** für Dense Reconstruction
- **CUDA:** Flexibel, 11.x und 12.x getestet
- **VRAM:** Dense Reconstruction ist speicherintensiv, 4+ GB empfohlen für mittlere Szenen
- **OS:** Windows (Pre-built Binaries verfügbar!), Linux, macOS
- **Installation:** Pre-built Binaries auf [demuc.de/colmap](https://demuc.de/colmap/) oder Build from Source
- **Hinweis für Windows:** Pre-built CUDA-Binaries direkt downloadbar → kein Build nötig!

> [!TIP]
> COLMAP ist das einzige Tool mit offiziellen **Windows-Binaries**. Alle anderen Tools sind primär für Linux entwickelt.

---

## 2. gsplat (3D Gaussian Splatting Library)

- **Repo:** [github.com/nerfstudio-project/gsplat](https://github.com/nerfstudio-project/gsplat)
- **Funktion:** Effizientes 3DGS-Training (bis zu 4× weniger VRAM als Referenz-Implementierung)
- **Python:** 3.10-3.12
- **PyTorch:** 2.0+ (2.6+ empfohlen)
- **CUDA:** 11.8 oder 12.x (JIT-Kompilierung der CUDA-Kernel beim ersten Lauf)
- **VRAM:** Ab 8 GB nutzbar, 12-16 GB empfohlen
- **OS:** Linux (primär), Windows (unterstützt)
- **Installation:** `pip install gsplat` (kompiliert CUDA-Kernel automatisch)

---

## 3. nerfstudio (Framework, enthält gsplat)

- **Repo:** [github.com/nerfstudio-project/nerfstudio](https://github.com/nerfstudio-project/nerfstudio)
- **Funktion:** Komplettes Framework für NeRF/3DGS mit Viewer, Daten-Pipeline, etc.
- **Python:** 3.10-3.12
- **PyTorch:** 2.1+ mit CUDA
- **CUDA:** 11.8 (primär getestet), 12.x kompatibel
- **VRAM:**
  - Minimum: 6-8 GB (stark eingeschränkt, nur mit Downscaling)
  - Empfohlen: **12-24 GB**
  - Ideal: RTX 3090/4090 (24 GB)
- **OS:** Linux (primär empfohlen), Windows (möglich, aber mehr Setup-Aufwand)
- **Hinweis:** Benötigt C++ Build-Tools für `tiny-cuda-nn`

---

## 4. SuGaR (Mesh-Extraktion aus 3DGS)

- **Repo:** [github.com/Anttwo/SuGaR](https://github.com/Anttwo/SuGaR)
- **Funktion:** Surface-aligned Gaussians → Poisson Mesh → texturiertes OBJ
- **Python:** 3.9 (fix in `environment.yml`)
- **PyTorch:** 2.0.1
- **CUDA:** **11.8** (explizit angegeben)
- **Weitere Deps:** PyTorch3D 0.7.4, Open3D, PyMCubes, Nvdiffrast (optional)
- **VRAM:** **12 GB Minimum**, 24 GB empfohlen (enthält intern eine volle 3DGS-Kopie)
- **OS:** Windows und Linux. Im README steht als To-Do: *"Due to path-writing conventions, the current code is not compatible with Windows."* – dies betrifft **nur hartcodierte Pfadtrenner** (`/` statt `\`), was mit `os.path.join()` oder `pathlib.Path` trivial zu fixen ist.
- **Installation:** Conda Environment via `python install.py`
- **Trainingszeit:** Gesamte Pipeline (7k 3DGS + SuGaR-Optimierung + Mesh + Refinement) ca. 30-60 Min auf RTX 3090

> [!NOTE]
> Die Windows-Inkompatibilität ist nur ein Pfad-Problem (To-Do im Repo), kein fundamentales Architekturproblem. Die eigentlichen Anforderungen sind: Conda, C++ Compiler, CUDA 11.8.

---

## 5. Gaussian Grouping (Semantische Segmentierung)

- **Repo:** [github.com/lkeab/gaussian-grouping](https://github.com/lkeab/gaussian-grouping)
- **Funktion:** Semantische Segmentierung der 3D-Gaussians via Identity Encoding
- **Python:** **3.8** (fix in install.md)
- **PyTorch:** **1.12.1**
- **CUDA:** **11.3** (cudatoolkit)
- **Weitere Deps:** plyfile, tqdm, scipy, wandb, opencv, scikit-learn, lpips
- **VRAM:** Vergleichbar mit vanilla 3DGS (~8-12 GB für mittlere Szenen)
- **OS:** Keine explizite Einschränkung dokumentiert (Standard Conda + pip)
- **Optionale Zusatz-Tools:**
  - **DEVA** (für Masken-Generierung auf eigenen Daten) – separates Setup mit Grounded-SAM
  - **LaMa** (nur für Inpainting/Objektentfernung – für deine Pipeline nicht nötig)
- **Workflow:**
  1. DEVA + Grounded-SAM generiert konsistente 2D-Masken über alle Bilder
  2. Training der Gaussians mit Identity-Encoding-Supervision
  3. Export segmentierter Gaussians

> [!NOTE]
> Die Kern-Installation ist überraschend schlank (PyTorch 1.12.1 + CUDA 11.3). Die DEVA-Masken-Vorbereitung ist ein **separater Schritt**, der nicht gleichzeitig mit dem 3DGS-Training im Speicher liegt – die VRAM-Anforderung ist daher nicht so hoch wie zunächst angenommen.

---

## 6. Georeferenzierung (klassisch, ohne GeoRefGS)

GeoRefGS (Paper auf MDPI, 2025) hat keinen verifizierbaren öffentlichen Code. **Das ist aber kein Problem**, weil die Georeferenzierung über den klassischen geodätischen Weg trivial lösbar ist:

**Workflow:**
1. GCPs auf dem Testfeld auslegen und mit RTK-GNSS einmessen (→ CSV: `ID, X, Y, Z`)
2. In COLMAP die GCPs in den Bildern manuell markieren
3. COLMAP berechnet die 3D-Position der GCPs im lokalen Modellsystem
4. **7-Parameter Helmert-Transformation** (3 Translationen, 3 Rotationen, 1 Maßstab) berechnen
5. Transformation auf alle Gaussian-Positionen anwenden → georeferenziertes Modell

- **Aufwand:** Ein Python-Skript mit ~50 Zeilen (`numpy`, `scipy.spatial.transform`)
- **COLMAP-Support:** COLMAP unterstützt GCPs nativ über `model_aligner` oder über die GUI
- **Vorteil:** Als Geoinformatiker ist die Helmert-Transformation Grundlagenwissen → fachlich souverän erklärbar

> [!TIP]
> Dieser klassische Weg ist **robuster und besser dokumentiert** als GeoRefGS. Für die Thesis kannst du GeoRefGS im State-of-the-Art erwähnen und erklären, warum du den klassischen Weg wählst (kein Code verfügbar, bewährte Methodik, volle Kontrolle).

---

## 7. DGtal (Centerline-Extraktion)

- **Repo:** [github.com/DGtal-team/DGtal](https://github.com/DGtal-team/DGtal)
- **Funktion:** Centerline-Extraktion aus Meshes via Normalenakkumulation
- **Sprache:** C++ (kein Python!)
- **Compiler:** C++20 kompatibel (g++, clang++)
- **Build-System:** CMake ≥ 3.20
- **Dependencies:** zlib (Standard), optional Polyscope (Visualisierung)
- **GPU:** ❌ **Nicht benötigt** (läuft komplett auf CPU)
- **VRAM:** < 1 GB (reines CPU-Programm)
- **OS:** Windows, Linux, macOS
- **Laufzeit:** Sekunden bis wenige Minuten (laut Paper: 0.5s - 22s je nach Szene)

> [!TIP]
> DGtal ist das **unkomplizierteste Tool** in deiner Pipeline. Reines C++, kein CUDA, läuft überall. Du könntest alternativ auch den Algorithmus aus dem Paper (Normalenakkumulation) in Python mit Open3D/Trimesh selbst implementieren – das wäre für die BA sogar ein Plus.

---

## Hardware-Empfehlung

### Minimum (funktioniert, aber knapp):
| Komponente | Spezifikation |
|------------|---------------|
| GPU | NVIDIA RTX 3060 Ti / 4060 Ti (8 GB VRAM) |
| RAM | 32 GB |
| Storage | 256 GB SSD (für Bilder, Modelle, Checkpoints) |
| OS | Ubuntu 22.04 (WSL2 möglich) |
| CUDA | 11.8 |

### Empfohlen (komfortabel):
| Komponente | Spezifikation |
|------------|---------------|
| GPU | **NVIDIA RTX 3090 / 4080 / 4090 (16-24 GB VRAM)** |
| RAM | 64 GB |
| Storage | 512 GB NVMe SSD |
| OS | Ubuntu 22.04 (nativ oder WSL2) |
| CUDA | 11.8 (für maximale Kompatibilität) |

### Cloud-Alternative:
| Anbieter | GPU | Kosten ca. |
|----------|-----|------------|
| Google Colab Pro+ | A100 (40 GB) | ~50 €/Monat |
| Vast.ai | RTX 3090/4090 | ~0.30-0.50 €/Stunde |
| Lambda Labs | A100 (80 GB) | ~1.10 €/Stunde |
| RunPod | RTX 4090 (24 GB) | ~0.40 €/Stunde |

---

## Kritische Engpässe und Risiken

### 🔴 Hohes Risiko
1. ~~GeoRefGS: Kein Code verfügbar.~~ → **Gelöst:** Klassische Helmert-Transformation über COLMAP GCPs.
2. ~~SuGaR auf Windows: Offiziell nicht unterstützt.~~ → **Geringes Risiko:** Nur Pfad-Konventionen, trivial fixbar.

### 🟡 Mittleres Risiko
3. **Gaussian Grouping VRAM:** Braucht 12-24 GB. Mit 8 GB GPU wird es sehr eng.
4. **Python-Version-Konflikte:** SuGaR will Python 3.9, gsplat will 3.10+. Du brauchst **separate Conda-Environments** pro Tool.
5. **CUDA 11.8 vs. 12.x:** SuGaR ist explizit auf CUDA 11.8 festgelegt. Neuere Treiber sind abwärtskompatibel, aber die PyTorch-Version muss stimmen.

### 🟢 Niedriges Risiko
6. **COLMAP:** Stabil, gut dokumentiert, Windows-Binaries verfügbar.
7. **DGtal:** Reines C++, keine GPU-Abhängigkeit, läuft überall.
8. **gsplat:** Gut gepflegt (nerfstudio-Team), breite Kompatibilität.

---

## Empfohlene Environment-Strategie

```
conda create -n colmap python=3.10    # Für PyCOLMAP (optional)
conda create -n gsplat python=3.10    # Für gsplat / nerfstudio
conda create -n sugar python=3.9      # Für SuGaR (eigene Umgebung!)
conda create -n gaussgroup python=3.9 # Für Gaussian Grouping + SAM + DEVA
# DGtal: Kein Python, wird separat mit CMake gebaut
```

> [!IMPORTANT]
> **Nutze CUDA 11.8 als gemeinsame Basis!** Das ist die Version, die von allen Tools unterstützt wird. Installiere den CUDA Toolkit 11.8 systemweit und nutze in jedem Conda-Environment die entsprechende PyTorch-Version mit `pytorch-cuda=11.8`.
