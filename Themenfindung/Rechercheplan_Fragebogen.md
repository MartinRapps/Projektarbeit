# Rechercheplan & Validierungs-Fragebogen (Der 3-Schritte-Plan)

Dieses Dokument dient als Checkliste und Fragebogen für deine aktuelle Projektidee: Die Isolation von dünnen Objekten (Stromleitungen) durch intelligente 2D-Vorverarbeitung (SAM+DEVA), Hintergrund-Ausblendung und anschließendes fokussiertes Meshing mit SuGaR.

Bitte fülle die Antworten aus, um sicherzustellen, dass dein 3-Schritte-Plan wasserdicht ist und alle technischen Hürden bedacht wurden.

---

## 1. Zielsetzung & Kernvorteile

> **Dein Ansatz:** 100% Splat-Budget auf das Objekt, perfekte Kanten durch schwarzen Hintergrund, Umgehung der CUDA-"Dependency Hell" durch Entkopplung der Teilschritte.

* **Fokus-Objekte:** Welche Art von "dünnen Leitungen" (Durchmesser, Material) auf welchem Hintergrund (Wald, Himmel, Straße) möchtest du im Testfeld abbilden?
  * *[Deine Antwort hier einfügen...]*

* **PA vs. BA Aufteilung:** Wie teilst du diesen 3-Schritte-Plan auf? 
  * *Empfehlung: PA = Proof of Concept der 2D-Vorarbeit (Docker, SAM, DEVA, Filter-Skript) auf wenigen Testbildern. BA = Die komplette Pipeline inkl. COLMAP, SuGaR-Meshing und Evaluierung der Genauigkeit.*
  * *[Deine Antwort hier einfügen...]*

---

## 2. Phase 1: Die intelligente 2D-Vorarbeit (SAM + DEVA)

> **Das Risiko:** KI-Modelle sind nicht perfekt. SAM übersieht feine Linien, DEVA verliert das Tracking bei schnellen Bewegungen.

* **Das Bounding-Box-Problem (Grounded-SAM):** Wenn eine Stromleitung diagonal durchs Bild läuft, ist die Bounding Box riesig und SAM fokussiert evtl. den Hintergrund. Wie löst du das? (Hinweis: Schau dir "SAHI" oder Image-Tiling an, um das Bild in kleinere Kacheln zu zerschneiden).
  * *[Deine Antwort hier einfügen...]*

* **Motion Blur & Tracking-Abbrüche (DEVA):** DEVA ist anfällig für Bewegungsunschärfe. Wie stellst du sicher, dass dein Videomaterial gestochen scharf ist? (z.B. Vorgaben für die Drohne: 60+ FPS, extrem kurze Belichtungszeit). Was passiert im Skript, wenn DEVA für 3 Frames die Maske verliert?
  * *[Deine Antwort hier einfügen...]*

---

## 3. Phase 2: Logisches Bündeln & Der COLMAP-Flaschenhals

> **Das größte technische Risiko:** Wenn du die Bilder (Leitung auf schwarzem Hintergrund) in eine Standard 3D-Pipeline wirfst, stürzt das Kamera-Tracking ab.

* **Das Aperture-Problem:** Weder SuGaR noch 3DGS wissen, wo die Kameras waren. Dafür brauchst du zwingend COLMAP. Wenn du COLMAP aber deine Bilder mit dem schwarzen Hintergrund gibst, findet es keine Feature-Punkte mehr und bricht ab. **Wie baust du den Workflow um, um das zu verhindern?** 
  * *Lösungs-Idee (Der "Bait & Switch" / "Image Swap" Trick):* COLMAP muss auf den **Originalbildern** (mit Wald und Bäumen) laufen, um die Kameras zu berechnen. Erst direkt vor dem Start von SuGaR tauschst du die Bilder im COLMAP-Ordner heimlich gegen deine gefilterten (schwarzen) Bilder aus. 
  * *Wirst du diesen Trick in dein Orchestrierungs-Skript einbauen?*
  * *[Deine Antwort hier einfügen...]*

---

## 4. Phase 3: Fokussiertes 3D-Meshing (SuGaR)

> **Das Risiko:** SuGaR nutzt den "Poisson Surface Reconstruction" Algorithmus, um aus den Splats ein Gitter zu bauen. Poisson hasst offene Röhren und baut lieber geschlossene Klumpen.

* **Das Oversmoothing-Problem:** Selbst wenn alle Splats perfekt auf der Leitung liegen, könnte der Poisson-Algorithmus versuchen, "Löcher" großflächig zu schließen, wodurch die Leitung wie ein unförmiger Wassertropfen aussehen könnte. Was ist dein **Plan B**, wenn das SuGaR-Mesh unbrauchbar wird?
  * *Lösungs-Idee:* Da du dank des schwarzen Hintergrunds ein 100% reines 3DGS-Leitungs-Modell hast, könntest du auf das Mesh verzichten. Du exportierst nur die Mittelpunkte der Gaussians als dichte Punktwolke (.ply) und fittest mathematisch perfekte 3D-Zylinder (CAD) durch diese Wolke (z.B. mit Tools wie DGtal oder CloudCompare).
  * *[Deine Antwort hier einfügen...]*

---

## 5. Scope & Bewertung (Wann ist das Projekt erfolgreich?)

* **Erfolgskriterium:** Woran misst du am Ende der BA, ob diese neue Methode besser ist als klassische Punktwolken? (Geht es um Zeitersparnis beim Berechnen? Um die Vollständigkeit der Leitung ohne Lücken? Um millimetergenaue Maßhaltigkeit?)
  * *[Deine Antwort hier einfügen...]*

* **Out-of-Scope (Was du NICHT tust):** Um dich zu schützen, was klammerst du explizit aus? (z.B. Kein Training von eigenen KI-Modellen, keine Echtzeit-Verarbeitung, keine automatische Objekterkennung anderer Bauteile außer den Leitungen).
  * *[Deine Antwort hier einfügen...]*
