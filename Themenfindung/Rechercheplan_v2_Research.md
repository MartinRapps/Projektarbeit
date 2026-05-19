# Rechercheplan & Validierung (v2) - Research-Fokus & Suchbegriffe

Dieses Dokument enthält gezielte **Suchbegriffe und Research-Empfehlungen** basierend auf deinen ausgefüllten Antworten im Fragebogen. Es dient als Begleitdokument für deine weitere Recherche, ohne deine Originalantworten anzutasten.

---

## 1. Zielsetzung & Kernvorteile (Drohnenflug & Graben)
Da du Stromerdkabel in 1,5m tiefen Gräben aus 10m Höhe erfassen möchtest:
Für den Flug über Gräben ist der Winkel der Kamera extrem wichtig. Ein reiner "Nadir"-Flug (Kamera schaut direkt 90 Grad nach unten) reicht oft nicht aus, um die runden Seiten des Kabels zu sehen, besonders im Graben. Du wirst oblique (schräge) Aufnahmen brauchen.
* **🔍 Suchbegriffe (Google / YouTube):** 
  * `Drone photogrammetry for trenches`
  * `Oblique vs Nadir drone mapping`
  * `Corridor mapping drone flight plan`

---

## 2. Phase 1: Die 2D-Vorarbeit (SAM 3 als Gamechanger!)
**Zu deiner Frage bezüglich SAHI und SAM 3:**
Du hast hier den absoluten Volltreffer gelandet! **SAM 3 (Segment Anything 3) ist der ultimative Gamechanger für dein Projekt.** 
Bisher war der Plan, drei verschiedene KI-Modelle wie mit Klebeband aneinander zu heften: *Grounding DINO* (für Text) $\rightarrow$ *SAM* (für Masken) $\rightarrow$ *DEVA* (für das Video-Tracking). 

Mit SAM 3 fällt diese Fehlerkette komplett weg. SAM 3 vereint Text-Erkennung (Concept Prompting), Segmentierung UND Video-Tracking nativ in einem einzigen Modell! Du kannst den komplexen Tech-Stack verwerfen. SAM 3 nutzt einen `sam3_video_predictor`. Du gibst ihm das Video, schreibst als Text-Prompt "thick black power cable in a trench" und das Modell trackt das Kabel durch alle Frames. Das löst auch dein Problem mit SAHI, da SAM 3 nicht zwingend auf riesigen Bounding-Boxen basiert, sondern das Konzept (die Semantik) der Leitung versteht.

* **🔍 Suchbegriffe & Code (Google / YouTube / GitHub):** 
  * `Meta SAM 3 video tracking tutorial`
  * `SAM 3 concept prompting python`
  * `Replacing DEVA with SAM 3 video predictor`
  * *GitHub-Tipp:* Schau dir im offiziellen SAM 3 Repo unbedingt das Notebook `sam3_video_predictor_example.ipynb` an. Das ist der perfekte Startpunkt für deine PA!

**Zum Thema Motion Blur (Bewegungsunschärfe):**
Da du das Problem über gute Kameraeinstellungen lösen willst (was der professionellste Weg ist!), musst du die exakten Hardware-Einstellungen für Drohnenflüge recherchieren.
* **🔍 Suchbegriffe:** 
  * `Drone camera settings to eliminate motion blur mapping`
  * `Shutter speed vs flight speed drone mapping`
  * `ND filters for drone photogrammetry`

---

## 3. Phase 2: Der COLMAP-Flaschenhals (Der "Bait & Switch")
Du planst korrekterweise eine "Wait"-Funktion, um COLMAP erst auf den Originalbildern rechnen zu lassen und die Bilder dann heimlich durch deine schwarzen Masken-Bilder auszutauschen. Das bedeutet, du musst COLMAP über ein Python-Skript (und nicht über die Klick-GUI) steuern.
* **🔍 Suchbegriffe:** 
  * `Automating COLMAP with Python subprocess`
  * `COLMAP CLI tutorial`
  * `Python wait for process to finish subprocess`

---

## 4. Phase 3: Fokussiertes 3D-Meshing (SuGaR)
Dein Plan B ist der Export als Punktwolke, falls der Poisson-Algorithmus bei den extrem dünnen Kabeln versagt und das Mesh "klumpig" (Oversmoothing) wird. Du musst dann aus der Punktwolke wieder einen geometrischen Zylinder machen.
* **🔍 Suchbegriffe:** 
  * `DGtal centerline extraction from point clouds`
  * `Open3D cylinder fitting RANSAC Python`
  * `CloudCompare trace polyline from point cloud`

---

## 5. Scope & Bewertung
Für die wirtschaftliche Bewertung (Serverkosten/Codeaufwand vs. Feldeinsatz bei der klassischen Vermessung) und die Evaluierung der Zielgenauigkeit (+/- 10cm):
* **🔍 Suchbegriffe:** 
  * `Cost benefit analysis Scan-to-BIM vs classical surveying`
  * `Economic evaluation of drone mapping utility lines`
  * `Python RMSE calculation 3D polylines`
