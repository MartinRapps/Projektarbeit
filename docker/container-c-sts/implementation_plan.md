# Implementation Plan: Segment-then-Splat (STS) Container & Multi-Scale Mask Generation

Dieses Dokument beschreibt den detaillierten Implementierungsplan für die Bereitstellung des **Segment-then-Splat (STS)** Containers sowie die automatische Erzeugung der hierarchischen 2D-Masken-Ebenen (`small.png`, `middle.png`, `default.png`) innerhalb unseres Scan-to-BIM-Workflows.

---

## 1. Theoretischer Hintergrund & Masken-Hierarchie (Curriculum-Training)
Das photogrammetrische Rekonstruktionsmodell **Segment-then-Splat (STS)** nutzt die 2D-Masken der Kamera-Frames, um die initialen COLMAP-Punktwolkenwerte segmentweise aufzuteilen (z. B. in die Objektklasse "Kabel" und den Hintergrund). 

Um Rauschen an den Kanten zu minimieren, verwendet STS ein **Curriculum-Schulungsverfahren (Curriculum Training)**, das während der Trainingsphasen zwischen drei Granularitätsstufen wechselt:
1. **`small.png` (Erodiert):** Konzentriert sich im frühen Stadium radikal auf den sichersten Kern des Objekts (die Kabelachse). Verhindert, dass der Hintergrund fälschlicherweise als Kabel trainiert wird.
2. **`middle.png` (Original):** Repräsentiert die unveränderte, von SAM 3.1 getrackte 2D-Maske.
3. **`default.png` (Dilatiert):** Ein geweitetes Band, das einen umliegenden Sicherheitskorridor freigibt, um sicherzustellen, dass die dichten Querschnitte der Kabelaußenseite vollständig erfasst werden.

---

## 2. Implementierungsarchitektur

### Phase 1: Post-Processing in Container A (`sam3-preprocess`)
Statt die komplexen mathematischen Operatoren während des rechenintensiven Trackings oder innerhalb der asynchronen Streams auszuführen, implementieren wir eine **Post-Processing-Pipeline** am Ende des Maskenextraktions-Skripts `extract_masks_notebook_flow.py`:

1. Das Skript propagiert die Maske standardmäßig durch das Video und wählt den Gewinner-Prompt.
2. Nach dem Schreiben aller finalen robusten flachen Maskendateien (`frame_xxxxx_obj_001.png`) in `data/03_masks/` erfolgt die automatische Konvertierung:
   - Schleife über alle extrahierten Vollmasken.
   - Pro Frame-Index `xxxxx` wird ein Unterordner `data/03_masks/frame_xxxxx/` angelegt.
   - **`middle.png`** wird direkt als Kopie abgelegt.
   - **`small.png`** wird über eine binäre Erosion mittels einer $5 \times 5$ (oder $3 \times 3$) Strukturierungs-Matrix (`cv2.erode`) erzeugt.
   - **`default.png`** wird über eine binäre Dilation (`cv2.dilate`) erzeugt.
   - Für leere Masken (Hintergrund-Frames) werden drei vollständig schwarze Dummy-Plätze generiert, damit STS keine Null-Pointer-Ladefehler meldet.

### Phase 2: Docker-Bereitstellung für Container C (`sts-training`)
Wir entwerfen ein robustes Docker-Image für **Segment-then-Splat**. Da die CUDA-Kernel von STS (Extensions wie `diff-gaussian-rasterization` und `simple-knn`) während des Image-Builds kompiliert werden müssen, bauen wir den Service auf einem performanten NVIDIA-Entwickler-Image auf:

* **Basis-Image:** `pytorch/pytorch:2.3.1-cuda12.1-cudnn8-devel` (Ubuntu 22.04 mit Python 3.10 und PyTorch 2.3.1 – exakt wie vom STS-Autor gefordert).
* **Git-Klonen:** Wir klonen das offizielle STS-Repository (`https://github.com/luyr/Segment-then-Splat.git`) direkt beim Build in den Container.
* **Bibliotheken & Kompilierung:**
  - Installation von CMake, Ninja-Build und g++ Compilern.
  - Kompilieren der C++/CUDA Untermodule ohne Build-Isolation, um native Performance zu garantieren.

---

## 3. Konkrete Umsetzungsschritte

1. **Skript-Erweiterung (`extract_masks_notebook_flow.py`):** Integration der morphologischen Post-Processing-Methode am Skriptende unter Nutzung von OpenCV.
2. **Dockerfile-Erweiterung für Container C (`docker/container-c-sts/Dockerfile`):** Vollständiges Befüllen des Setup-Files und automatische Kompilierung der CUDA-Kerne.
3. **Build und Verifikation:** 
   - Test des Maskenschreibers auf dem Host.
   - Build-Test des STS-Dienstes im Hintergrund.
