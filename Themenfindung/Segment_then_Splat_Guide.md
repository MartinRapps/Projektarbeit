# Leitfaden: Segment-then-Splat (STS) & SAM 3 Integration

Dieses Dokument erklärt vereinfacht die Funktionsweise von **Segment-then-Splat (STS)** (NeurIPS 2025), wie die objektspezifischen Daten gespeichert werden und wie **SAM 3** nahtlos in diesen Workflow integriert wird.

---

## 1. Was macht Segment-then-Splat (STS)?

Klassische Ansätze (wie *LangSplat* oder *Gaussian Grouping*) arbeiten nach dem Prinzip **"Splat-then-Segment"**:
1. Die gesamte Szene wird als 3D-Modell rekonstruiert.
2. Erst danach wird versucht, Pixel oder Gaussians in Klassen zu unterteilen.
*Problem:* Gaussians an Kanten enthalten Mischinformationen (Hintergrund + Vordergrund). Dies führt zu verwaschenen Kanten, "schwebenden" Artefakten und ungenauen Geometrien.

**Segment-then-Splat (STS)** dreht dieses Prinzip komplett um:
```
[2D Masken & Bilder] ──(Projektion)──> [3D Gaussians mit Objekt-IDs] ──(Reconstruction)──> [Saubere 3D Objekte]
```

1. **Objekt-Initialisierung:** 
   Noch *vor* dem Training werden die von COLMAP generierten 3D-Punkte (Sparse Point Cloud) anhand der 2D-Segmentierungsmasken klassifiziert. Wenn ein 3D-Punkt in den 2D-Bildern überwiegend auf dem "Kabel" liegt, bekommt er die Objekt-ID für das Kabel zugewiesen.
2. **Objektspezifische Sets:** 
   Die Punktwolke wird in getrennte Objekt-Sets aufgeteilt (z. B. Set 1: Kabel, Set 2: Bagger, Set 3: Erdboden).
3. **Objekt-spezifischer Loss ($\mathcal{L}_{obj}$):** 
   Beim Training optimiert das Modell jedes Set getrennt. Die Gaussians des Kabels dürfen nur zum Rendern des Kabels beitragen. Wenn sie in den Hintergrund "bluten", bestraft das der Loss.
4. **Keine Vermischung:** 
   Klonen, Teilen und Löschen (Densification & Pruning) von Gaussians finden streng *innerhalb* des jeweiligen Objekt-Sets statt. Ein Kabel-Gaussian kann niemals zu einem Erdboden-Gaussian werden.

---

## 2. Wie werden die Daten abgespeichert?

Da STS auf dem Standard-Framework von 3D Gaussian Splatting (Inria) aufbaut, werden die trainierten Szenen primär als **`.ply`-Dateien** (Polygon File Format) abgespeichert.

### Datenstruktur in der `.ply`-Datei:
Die Gaussians besitzen neben den Standard-Attributen zusätzliche benutzerdefinierte Spalten für die Objektzuordnung auf drei Detailstufen (Granularitäten):

| Attribut | Typ | Beschreibung |
|---|---|---|
| `x`, `y`, `z` | `float` | 3D-Position des Gaussians |
| `f_dc_*`, `f_rest_*` | `float` | Farbe (Spherical Harmonics) |
| `opacity` | `float` | Transparenz |
| `scale_*`, `rot_*` | `float` | Größe und Ausrichtung (Ellipsoid) |
| **`obj_id_s`** | `int` | Objekt-ID auf kleiner Granularitätsstufe (z. B. einzelne Kabelmuffe) |
| **`obj_id_m`** | `int` | Objekt-ID auf mittlerer Granularitätsstufe (z. B. Kabeltrasse) |
| **`obj_id_l`** | `int` | Objekt-ID auf großer Granularitätsstufe (z. B. gesamte Baugrube) |

### Wie du das Kabel-Sub-Mesh für SuGaR / DGtal extrahierst:
Beim Laden des Checkpoints in **SuGaR** kannst du die Gaussians anhand der ID filtern:
```python
# Pseudo-Code zur Extraktion des Kabel-Sub-Meshes
import numpy as np
from plyfile import PlyData

ply_data = PlyData.read("point_cloud.ply")
vertex_data = ply_data['vertex']

# Finde die Objekt-ID, die der Kabeltrasse entspricht (z. B. ID 42 auf mittlerer Ebene)
kabel_mask = vertex_data['obj_id_m'] == 42

# Behalte nur die Kabel-Gaussians
kabel_gaussians = vertex_data[kabel_mask]
```
Dieses isolierte Set wird dann an das Geometrie-Meshing von SuGaR übergeben. Dadurch entsteht ein Mesh, das **ausschließlich das Kabel** enthält, ohne Hintergrundrauschen.

---

## 3. Wie wird SAM 3 in STS eingebunden?

Im Original-Repository von STS wird das veraltete **AutoSeg-SAM2** zur automatischen Maskengenerierung verwendet. In deiner Pipeline wird dieses durch das präzisere **SAM 3 (Container A)** ersetzt.

Da die Übergabe der Masken dateibasiert über Docker-Volumes erfolgt, ist die Einbindung sehr einfach.

### Schritt-für-Schritt Integrationsweg:

```
[Container A: SAM 3]  ──(Schreibt PNG-Masken)──>  [Shared Volume: /data/masks]  ──(Liest PNGs)──>  [Container C: STS]
```

1. **Schritt 1: Masken mit SAM 3 generieren (Container A)**
   Du lässt SAM 3 das Drohnenvideo verarbeiten. Über die Python-Schnittstelle von SAM 3 kannst du die Masken direkt aus dem Predictor-Stream auslesen und als Binärbilder (PNG) speichern:

   ```python
   import os
   import numpy as np
   from PIL import Image
   from sam3.model_builder import build_sam3_video_predictor

   # 1. Video Predictor initialisieren
   predictor = build_sam3_video_predictor(gpus_to_use=[0])

   # 2. Session mit dem Video oder einem Frame-Ordner starten
   video_path = "/data/video.mp4"
   response = predictor.handle_request(
       request=dict(type="start_session", resource_path=video_path)
   )
   session_id = response["session_id"]

   # 3. Prompt setzen (z.B. Text-Prompt "cable" auf Frame 0)
   predictor.handle_request(
       request=dict(
           type="add_prompt",
           session_id=session_id,
           frame_index=0,
           text="cable"
       )
   )

   # 4. Stream-Propagation & PNG-Export
   output_dir = "/data/masks"
   os.makedirs(output_dir, exist_ok=True)

   # propagate_in_video liefert einen Generator
   for response in predictor.handle_stream_request(
       request=dict(type="propagate_in_video", session_id=session_id)
   ):
       frame_idx = response["frame_index"]
       outputs = response["outputs"]
       obj_ids = outputs["out_obj_ids"]
       binary_masks = outputs["out_binary_masks"]  # Shape: [num_objects, H, W]

       for idx, obj_id in enumerate(obj_ids):
           mask = binary_masks[idx]  # Bool-Array [H, W]
           if mask.any():
               # Konvertierung: True -> 255, False -> 0
               mask_uint8 = (mask * 255).astype(np.uint8)
               img = Image.fromarray(mask_uint8)
               # Speichern im Format: frame_[index]_obj_[id].png
               img.save(os.path.join(output_dir, f"frame_{frame_idx:05d}_obj_{obj_id:03d}.png"))

   # 5. Session schließen
   predictor.handle_request(
       request=dict(type="close_session", session_id=session_id)
   )
   ```

   *Dateistruktur in `/data/masks/`:*
   ```text
   /data/masks/
   ├── frame_00001_obj_001.png
   ├── frame_00002_obj_001.png
   └── ...
   ```

2. **Schritt 2: STS Masken-Preprocessing starten (Container C)**
   STS erwartet die Masken in einem bestimmten Format. Das STS-Hilfsskript `preprocess_mask.py` bereitet deine SAM 3 Masken auf und verknüpft sie mit der Bildstruktur:
   ```bash
   python ./helpers/preprocess_mask.py \
       --mask_root /data/masks \
       --out_root /data/scene/ \
       --image_path /data/scene/images
   ```
   *Was hier passiert:* Das Skript kopiert deine Masken in die STS-Datenstruktur und berechnet die für den Loss notwendigen Masken-Dateipfade.

3. **Schritt 3: 3D-Punkte zuweisen**
   Anschließend ordnest du die initialen COLMAP-Punkte den Masken zu:
   ```bash
   python ./helpers/object_specific_initialization.py --scene_root /data/scene/
   ```
   STS prüft für jeden COLMAP-Punkt, in welchen SAM 3 Masken er sichtbar ist, und schreibt die entsprechende Kabel-ID in die Initialisierungsdatei.

4. **Schritt 4: Training starten**
   Nun trainierst du das Modell mit dem objektspezifischen Loss:
   ```bash
   python train.py -s /data/scene/ -m /data/output --eval --iterations 40000
   ```
   Der $\mathcal{L}_{obj}$ sorgt jetzt dafür, dass die Kabel-Gaussians exakt innerhalb der von SAM 3 vorgegebenen Grenzen trainiert werden.
