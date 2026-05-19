# Rechercheplan & Validierungs-Fragebogen (v2 - Inklusive Antworten & Research-Fokus)

Dieses Dokument enthält nun deine Antworten auf den 3-Schritte-Plan sowie gezielte **Suchbegriffe und Research-Empfehlungen**, damit du für die anstehenden Detailfragen (besonders rund um das neue SAM 3) Artikel und Tutorials suchen kannst.

---

## 1. Zielsetzung & Kernvorteile

* **Fokus-Objekte:**
  * *Deine Antwort:* Ich will Stromerdkabel erfassen. Diese liegen in einem ca 1,5m tiefen Graben und haben einen Durchmesser von ca 20cm. Die Aufnahme sollte mit Hilfe von Drohnen erfolgen, welche in ca. 10m über dem Objekt fliegen. Die maximale Aufnahmestrecke ist ca. 1000m und müsste einmal links und einmal rechts um das Objekt rumgeflogen werden.
  * **🔍 Research-Fokus & Suchbegriffe:** Für den Flug über Gräben ist der Winkel der Kamera entscheidend. Da du das Kabel im Graben erfassen musst, reicht "Nadir" (direkt nach unten) oft nicht aus, um die Seiten des Kabels zu sehen.
    * *Suchbegriffe (Google/YouTube):* `Drone photogrammetry for trenches`, `Oblique vs Nadir drone mapping`, `Corridor mapping drone flight plan`.

* **PA vs. BA Aufteilung:** 
  * *Deine Antwort:* PA: Fokus auf die 2D-Vorarbeit. Nur wenige Testbilder, Machbarkeit überprüfen (Aluabsperrung, zylindrischer Sitzhocker). BA: Komplette Pipeline inkl. COLMAP, SuGaR-Meshing, Georeferenzierung (GNSS GCPs), Laserscan-Referenz.
  * **🔍 Feedback:** Perfekte Aufteilung. Die Alu-Absperrung (dünne Rohre) ist ein exzellenter Stresstest für die PA!

---

## 2. Phase 1: Die intelligente 2D-Vorarbeit (SAM + DEVA $\rightarrow$ Upgrade auf SAM 3!)

* **Das Bounding-Box-Problem (Grounded-SAM) & Deine Frage zu SAM 3:**
  * *Deine Antwort:* Wie kann ich bei SAHI sichergehen, dass die Leitung als Ganzes erfasst wird? [...] Kann ich in Gaussian Grouping einfach SAM 3 einfügen? (Mit SAM 3 kann ich textbasiert suchen und es trackt über Frames hinweg). Ich brauche Research zum Zusammenspiel von DEVA, G-DINO, SAM und SAM 3.
  * **🔍 Antwort & Research-Fokus (BINGO!):** Du hast den Nagel auf den Kopf getroffen! **SAM 3 (Segment Anything 3) ist ein absoluter Gamechanger für dein Projekt.** SAM 3 vereint Text-Erkennung (Concept Prompting), Segmentierung UND Video-Tracking in einem *einzigen* Modell!
    Du kannst den komplexen Tech-Stack (Grounding DINO $\rightarrow$ SAM $\rightarrow$ DEVA) komplett in den Müll werfen! SAM 3 hat einen nativen `sam3_video_predictor`. Du gibst ihm dein Drohnen-Video und den Text-Prompt "thick black power cable in a trench" und es trackt das Kabel automatisch durch alle Frames. Das löst auch dein SAHI-Problem, da SAM 3 von Haus aus viel besser auf Text-Konzepte trainiert ist.
    * *Suchbegriffe (Google/YouTube):* `Meta SAM 3 video tracking tutorial`, `SAM 3 concept prompting python`, `Segment Anything 3 custom dataset inference`, `Replacing DEVA with SAM 3 video predictor`.
    * *GitHub:* Schau dir im SAM 3 Repo unbedingt das Notebook `sam3_video_predictor_example.ipynb` an. Das ist exakt das, was du für die PA brauchst!

* **Motion Blur & Tracking-Abbrüche:**
  * *Deine Antwort:* Ich kann das Problem vernachlässigen, da ich es über gute Kameraeinstellungen löse. Fehlerhafte Artefakte kann ich manuell bereinigen.
  * **🔍 Research-Fokus & Suchbegriffe:** Da du die Fehlerquelle bei der Hardware anpackst (sehr gut!), musst du die exakten Kamera-Einstellungen für schnelle Drohnenflüge recherchieren.
    * *Suchbegriffe:* `Drone camera settings to eliminate motion blur mapping`, `Shutter speed vs flight speed drone mapping`, `ND filters for drone photogrammetry`.

---

## 3. Phase 2: Logisches Bündeln & Der COLMAP-Flaschenhals

* **Das Aperture-Problem ("Image Swap" Trick):** 
  * *Deine Antwort:* Ja, ich muss das einbauen mit einer einfachen Wait-Funktion, um sicherzustellen, dass COLMAP die Cameras berechnet hat. Und danach tausche ich die Bilder aus.
  * **🔍 Research-Fokus & Suchbegriffe:** Du wirst COLMAP idealerweise nicht über die GUI steuern, sondern über Kommandozeilen (CLI) via Python aufrufen, damit dein Workflow automatisiert ist.
    * *Suchbegriffe:* `Automating COLMAP with Python subprocess`, `COLMAP CLI tutorial`, `Python wait for process to finish`.

---

## 4. Phase 3: Fokussiertes 3D-Meshing (SuGaR)

* **Das Oversmoothing-Problem (Poisson Mesh):**
  * *Deine Antwort:* Ja, Export als Punktwolke wäre eine Möglichkeit. Ich werde anhand der Testobjekte in der PA evaluieren, wann ich Schwierigkeiten bekomme und wie ich diese verhindere.
  * **🔍 Research-Fokus & Suchbegriffe:** Falls das Mesh bei der Alu-Absperrung (in der PA) wie Knetmasse aussieht, musst du wissen, wie du die 3DGS-Zentren (die `.ply` Datei) als saubere Punktwolke in eine CAD-Leitung umwandelst.
    * *Suchbegriffe (Google/YouTube/Scholar):* `DGtal centerline extraction from point clouds`, `Open3D cylinder fitting RANSAC Python`, `CloudCompare trace polyline from point cloud`.

---

## 5. Scope & Bewertung

* **Erfolgskriterium & Wirtschaftlichkeit:**
  * *Deine Antwort:* +/- 10cm Abweichung in Lage und Höhe. Vektorisierte, georeferenzierte Linie. Wirtschaftliche Bewertung: Rechtfertigt der niedrige Aufwand der Vermessung die Serverkosten/Rechenzeit im Vergleich zur klassischen Vermessung?
  * **🔍 Research-Fokus & Suchbegriffe:** Für den wirtschaftlichen Vergleich brauchst du Literatur, die aufzeigt, was "klassische" Vermessung kostet (Zeit/Personal im Feld). 
    * *Suchbegriffe:* `Cost benefit analysis Scan-to-BIM vs classical surveying`, `Economic evaluation of drone mapping utility lines`, `Python RMSE calculation 3D polylines`.

* **Out-of-Scope:**
  * *Deine Antwort:* Georeferenzierung ist "nice-to-have" und kommt erst, wenn der Rest läuft. Sonstige Bauteile sind out of scope. Überlandleitungen sind out of scope.
  * **🔍 Feedback:** Sehr smarte, defensive Scope-Setzung! Das schützt dich vor bösen Überraschungen bei der Zeitplanung. Behalte diese Argumentation für das Exposé genau so bei!
