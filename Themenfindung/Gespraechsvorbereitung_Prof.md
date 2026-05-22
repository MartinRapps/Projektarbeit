# Leitfaden zur Gesprächsvorbereitung (Herr Müller)
**Projektarbeit (PA) & Bachelorarbeit (BA)**  
*KI-gestützte 3D-Rekonstruktion linearer Infrastruktur: Evaluierung einer Docker-basierten Scan-to-BIM Pipeline mittels SAM 3 und Gaussian Splatting*

---

> [!NOTE]
> **Status Zweitbetreuer:** Das ausgefüllte und unterschriebene Formular für den Betreuer bei TenneT wurde bereits an Herrn Müller zurückgeschickt. Hier besteht kein administrativer Handlungsbedarf mehr. Eine kurze Info zu Beginn des Gesprächs reicht völlig aus.

---

## 1. Strategischer Argumentations-Tipp (PA vs. BA)
Betone im Gespräch die klare Trennung von **Feasibility (PA)** und **Skalierung/Validierung (BA)**:
*   **Die Projektarbeit (PA)** ist das **technische Fundament**. Das Ziel ist erreicht, wenn die 5-Container-Architektur steht, das Master-Skript fehlerfrei durchläuft, der Dataloader die Masken einliest, die 4x4-Georeferenzierungsmatrix angewendet wird und ein erster Machbarkeitsnachweis an einem einfachen Testobjekt (Aluabsperrung) gelingt.
*   **Die Bachelorarbeit (BA)** ist die **wissenschaftliche Evaluierung**. Hier finden die reale Feldarbeit (Drohnenflug & GNSS-Messung), die eigentliche Parameterstudie (Poisson-Tiefe, Flughöhe, GCP-Layouts) und der Nachweis der $\pm$ 10 cm Toleranz statt.

---

## 2. Die Top 9 Fragen von Herrn Müller (mit Antworten)

### 1. "Warum Gaussian Splatting (3DGS) und nicht klassische Photogrammetrie (MVS) oder NeRF?"
*   **Hintergrund:** Herr Müller ist im Bereich Computer Vision versiert und kennt traditionelle SfM/MVS-Pipelines (z. B. COLMAP) sowie Neural Radiance Fields (NeRF).
*   **Deine Antwort:**
    *   *Gegenüber MVS:* Klassische Punktwolken (Multi-View Stereo) scheitern häufig an extrem dünnen, einfarbigen oder leicht reflektierenden Objekten wie Stromkabeln in Baugräben, da sich schwer korrespondierende Keypoints finden lassen. 3DGS stellt Geometrie durch kontinuierliche 3D-Gauss-Ellipsoide dar, die feine Strukturen dichter rekonstruieren und besser interpolieren können.
    *   *Gegenüber NeRF:* NeRFs sind implizite neuronale Repräsentationen. Es ist mathematisch extrem rechenintensiv, daraus ein sauberes Mesh (Oberfläche) zu extrahieren. 3DGS ist eine explizite Repräsentation. Frameworks wie **SuGaR** nutzen dies aus, um die Gaussians flach auf den Objektoberflächen zu regularisieren und über Poisson Reconstruction ein präzises, geschlossenes Mesh abzuleiten.

### 2. "Wie funktioniert 'Segment-then-Splat' (STS) und was bringt uns das hier?"
*   **Hintergrund:** Er möchte den wissenschaftlichen Kern des 3D-Rekonstruktionsansatzes verstehen.
*   **Deine Antwort:**
    *   Klassische 3D-Segmentierung (wie *Gaussian Grouping*) arbeitet nach dem Prinzip "Splat-then-Segment" (erst alles rekonstruieren, dann im 3D-Raum klassifizieren). Das führt an Objektkanten zu verwaschenen Rändern und Artefakten.
    *   **Segment-then-Splat (STS)** dreht das Prinzip um: Es nutzt die 2D-Segmentierungsmasken *vor* dem Training, um die initialen COLMAP-Punkte in verschiedene Objekt-Sets aufzuteilen.
    *   Beim Training optimiert STS jedes Set (Kabel vs. Hintergrund) getrennt mit einem **objektspezifischen Loss ($\mathcal{L}_{obj}$)**. Die Kabel-Gaussians dürfen nur das Kabel darstellen. Das verhindert das "Verschmelzen" des Kabels mit dem Erdboden und erlaubt uns die saubere Extraktion des reinen Kabel-Meshes.

### 3. "STS basiert auf einem Curriculum-Training mit den Stufen 'small', 'middle' und 'default'. Wie erzeugen Sie diese drei Masken, wenn der SAM 3 Video-Tracker im Video-Modus pro Frame nur eine Maske liefert?"
*   **Hintergrund:** Ein tiefergehendes technisches Detail. Der SAM 3 Video Predictor propagiert aus Konsistenzgründen im Video-Modus immer nur eine resolved Maske pro Objekt, während die STS-Loss-Funktion drei hierarchische Detailstufen (Granularitäten) für das Curriculum-Training erwartet.
*   **Deine Antwort:**
    *   Wir nutzen die Tatsache aus, dass ein Erdkabel ein geometrisch homogenes, linienförmiges Objekt ist (es besitzt keine hierarchischen Unterteile wie z. B. ein Auto mit Rädern und Radmuttern).
    *   Daher generieren wir die drei Maskenebenen in Container A künstlich über **morphologische Bildoperationen (Erosion und Dilation)** in OpenCV:
        *   **`middle.png`:** Die originale, von SAM 3 getrackte Maske des Kabels.
        *   **`small.png`:** Eine durch Erosion verkleinerte Version der Maske. Dies fokussiert das STS-Training im frühen Stadium des Curriculums auf den absolut sichersten, innersten Kern (die Kabelachse).
        *   **`default.png`:** Eine leicht dilatierte (vergrößerte) Version der Maske, um den äußeren Randbereich zum Grabenboden abzudecken.

### 4. "Wie verbinden Sie SAM 3 und STS technisch im Code?"
*   **Hintergrund:** Die beiden Repositories haben inkompatible Anforderungen.
*   **Deine Antwort:**
    *   Wir entkoppeln die Schritte vollständig über unsere Docker-Architektur und nutzen das Shared Volume `/data/` als Brücke.
    *   **In Container A (SAM 3):** Das Python-Skript führt das Tracking durch, wendet die morphologischen Operationen an und speichert die Masken in Unterordnern pro Frame ab (z. B. `data/masks/frame_00001/small.png`, `middle.png`, `default.png`).
    *   **In Container C (STS):** Wir passen den Dataloader (in `scene/dataset_readers.py` oder `scene/cameras.py`) so an, dass er die drei PNG-Dateien pro Frame einliest, als Boolean-Tensoren normiert und dem Dictionary `viewpoint_cam.object_masks` zuweist. STS nutzt diese Tensoren dann nativ für den Loss.

### 5. "Warum SAM 3 und was machen Sie, wenn das Kabel im Graben kaum sichtbar oder verschmutzt ist?"
*   **Hintergrund:** Er hinterfragt die Robustheit des 2D-Segmentierungs-Frontends.
*   **Deine Antwort:**
    *   *Warum SAM 3:* SAM 3 bietet im Vergleich zu SAM 2 ein verbessertes Concept-Prompting und vor allem ein hervorragendes **temporales Video-Tracking** (Memory-Modul). Wir prompten das Kabel in Frame 0 und SAM 3 verfolgt es flackerfrei durch das gesamte Video. Das garantiert die für 3DGS zwingend erforderliche zeitliche Konsistenz der Masken.
    *   *Fallback bei schlechter Sicht:* Sollte das Tracking wegen starker Verschmutzung reißen, nutzen wir die Fallback-Route: **SAHI (Slicing Aided Hyper Inference)** in Kombination mit SAM 3 Image. SAHI kachelt das 4K-Bild in hochauflösende Patches, wodurch auch extrem dünne und kontrastarme Kabelsegmente zuverlässig segmentiert werden.

### 6. "Wie läuft die Georeferenzierung genau ab? Warum CloudCompare?"
*   **Hintergrund:** Die Einhaltung der $\pm$ 10 cm Toleranz ist das kritische Kriterium für TenneT.
*   **Deine Antwort:**
    *   COLMAP und 3DGS-Rekonstruktionen laufen zunächst maßstabs- und orientierungslos im lokalen SfM-Koordinatenraum um den Ursprung (0,0,0).
    *   Wir nutzen reale, per GNSS eingemessene GCPs (Ground Control Points) im Graben, um die Rekonstruktion maßstäblich und absolut auszurichten.
    *   **Der Ablauf:**
        1. **Vorverarbeitung (Step 0):** Das Skript `prepare_gcp.py` liest die globalen UTM-Koordinaten (`gcp_coordinates.csv`), wählt den ersten GCP als globalen Ankerpunkt, berechnet relative GCP-Koordinaten und speichert diese als `gcp_relative.csv` sowie den Anker in `anchor.txt`. Dies verhindert Rundungsfehler (Präzisionsverlust) in CloudCompare (das intern mit 32-Bit-Floats arbeitet und bei UTM-Koordinaten im Bereich $>10^6$ cm-große Verzerrungen erzeugen würde).
        2. **Punktwolken-Ausrichtung (Breakpoint):** Der Nutzer lädt die lokale SfM-Punktwolke aus COLMAP (Container B) und die `gcp_relative.csv` in CloudCompare. Durch manuelles Point Picking wird die Wolke auf die relativen GCPs registriert. CloudCompare gibt eine **4x4-Transformationsmatrix** (`matrix.txt`) aus, die die Rotation, Translation und Skalierung beschreibt.
        3. **3DGS-Training & Meshing (Steps 3 & 4):** Das Training läuft im lokalen Raum (STS / SuGaR), und wir extrahieren die lokale Centerline (`centerline_local.csv`).
        4. **Georeferenzierung (Step 5):** Das Skript `transform_centerline.py` wendet die 4x4-Matrix auf die lokale Centerline an und addiert anschließend die UTM-Koordinaten des Ankers aus `anchor.txt` wieder hinzu. So erhalten wir die absolute UTM-Centerline (`centerline_utm.csv`) mit voller 64-Bit-Präzision.
        5. **GIS-Export (Step 5):** Mittels `ogr2ogr` wird die UTM-Centerline in ein standardisiertes GeoJSON (EPSG:25832) konvertiert.

### 7. "Warum ist CloudCompare ein manueller Schritt? Stört das nicht den Workflow?"
*   **Hintergrund:** Er hinterfragt den Grad der Automatisierung.
*   **Deine Antwort:**
    *   Die vollautomatische Erkennung künstlicher Passpunkte in unstrukturierten 3D-Punktwolken ist ein hochgradig komplexes, eigenständiges Forschungsgebiet der Computer Vision.
    *   Da der Fokus dieser Arbeit auf der Evaluierung der Rekonstruktionsqualität des Kabels liegt, ist der manuelle Schritt in CloudCompare ein pragmatischer und extrem sicherer "Breakpoint", der eine fehlerhafte automatische Ausrichtung verhindert.

### 8. "Warum brauchen Sie eine Docker-Architektur mit 5 Containern? Reicht nicht eine Conda-Umgebung?"
*   **Hintergrund:** Herr Müller fragt nach dem System-Overhead.
*   **Deine Antwort:**
    *   Es liegt an unlösbaren CUDA- und Bibliotheksschnittstellen-Konflikten:
        *   **Container A (SAM 3):** Benötigt modernstes PyTorch/CUDA (CUDA $\ge$ 12.6).
        *   **Container C (STS):** Läuft stabil unter CUDA 12.1 (PyTorch 2.3.1).
        *   **Container D (SuGaR):** Nutzt PyTorch3D-Abhängigkeiten und den 3DGS-Rasterizer, die zwingend CUDA 11.8 erfordern.
        *   **Container E (Post-Processing):** Ist ein C++ (DGtal) und GDAL basierter reiner CPU-Dienst, der ohne Grafikkarte auskommt.
    *   Diese unterschiedlichen CUDA-Versionen lassen sich auf einem Betriebssystem (selbst mit Conda) nicht parallel ohne Compiler- und Treiberkonflikte betreiben. Docker isoliert die Abhängigkeiten perfekt.

### 9. "Wie evaluieren Sie die Genauigkeit der rekonstruierten Kabelachse?"
*   **Hintergrund:** Er verlangt nach harten, mathematischen Metriken.
*   **Deine Antwort:**
    *   Die gemessenen GNSS-Referenzpunkte der Kabelscheitelachse werden über eine kontinuierliche, mathematisch glatte **3D-B-Spline-Kurve ($S(t)$)** interpoliert.
    *   Wir berechnen:
        1.  **RMSE (Root Mean Square Error):** Bestimmt den quadratischen Mittelwert der euklidischen Abstände der extrahierten DGtal-Centerline zur B-Spline-Referenzkurve. Das gibt uns den durchschnittlichen systematischen Fehler über die gesamte Trasse.
        2.  **Hausdorff-Distanz:** Ermittelt den maximalen lokalen Abstand (Worst-Case) zwischen den beiden Kurven im Raum. Nur wenn die Hausdorff-Distanz unter 10 cm liegt, ist die geforderte Toleranz von TenneT an jedem einzelnen Punkt der Trasse nachweisbar eingehalten.

---

## 3. Schnelle Checkliste für das Gespräch
*   [ ] **Zweitbetreuer klären:** Direkt am Anfang kurz erwähnen, dass die Unterschriften von TenneT bereits vorliegen und eingereicht sind.
*   [ ] **Fokus der PA betonen:** Es geht in der PA um die lauffähige Software-Architektur (Docker, Skripte, Koordinatentransformation) und den prinzipiellen Funktionsnachweis am Testobjekt.
*   [ ] **Hardware/Workstation ansprechen:** Du hast lokal eine RTX 4000 (16 GB VRAM). Das reicht für die Entwicklung, kleinere Test-Szenen und reduzierte Bildauflösungen (z. B. `--resolution 2` oder `--resolution 4` beim STS-Training). Für die volle 4K-Bildauflösung und längere Trassenabschnitte in der Bachelorarbeit (BA) sind 24 GB+ VRAM (z. B. RTX 3090/4090 oder RTX A5000) jedoch dringend ratsam. Frage ihn aktiv nach dem Zugriff auf Workstations des Lehrstuhls (inkl. Docker- und Admin-Rechten).
