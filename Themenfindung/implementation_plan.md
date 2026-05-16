# Machbarkeitsanalyse: Der 3-Schritte-Plan unter der Lupe

Sie haben nach 100% Ehrlichkeit und maximaler Tiefe gefragt. Das ist genau der richtige Ansatz für ein Projekt dieser Komplexität. Ihr vorgeschlagener Workflow ist kreativ, birgt aber auf den zweiten Blick massive technische Fallstricke – insbesondere bei der Kombination von Photogrammetrie und KI-generierten Masken.

Hier ist der wasserfeste Überprüfungsplan. Wenn Sie diesen freigeben, werde ich jeden Punkt im Detail recherchieren, bewerten und Ihnen gnadenlos aufzeigen, was funktioniert und was nicht.

## User Review Required

> [!CAUTION]
> Dieser Überprüfungsplan ist darauf ausgelegt, die Schwachstellen Ihrer Idee aufzudecken, *bevor* Sie Wochen in die Programmierung stecken. Bitte lesen Sie die 4 Phasen durch und geben Sie mir grünes Licht für die Tiefenanalyse.

## Der wasserfeste Überprüfungsplan (Schritt-für-Schritt)

### Phase 1: Die Infrastruktur-Hölle (Docker, WSL2 & CUDA)
In dieser Phase evaluiere ich die Systemvoraussetzungen:
- **WSL2-Zwang:** Brauchen Sie wirklich Linux/WSL2? Ich werde aufzeigen, warum Repos wie DEVA oder Gaussian Grouping unter nativem Windows fast immer beim Kompilieren von Custom-CUDA-Kerneln scheitern.
- **Docker als Rettung:** Ist Docker nutzbar, um die Konflikte (z.B. CUDA 11.3 für Grouping vs. 11.8 für SuGaR) zu isolieren? Wie richtet man das NVIDIA Container Toolkit in WSL2/Docker ein, damit die GPU durchgereicht wird?
- **Fazit Phase 1:** Ich erstelle Ihnen ein klares Setup-Konzept (z.B. ein dediziertes Dockerfile pro Teilschritt).

### Phase 2: Die 2D-Vorverarbeitung (SAM + DEVA) & Datenspeicherung
In dieser Phase prüfe ich die Machbarkeit der Maskierung:
- **Dünne Strukturen:** Funktionieren Grounding DINO und SAM *wirklich* bei pixel-dünnen Stromleitungen auf Drohnenbildern, oder verschwimmen diese mit dem Hintergrund?
- **Speicherlogik:** Muss ein eigenes Modell trainiert werden? (Kurze Antwort vorab: *Nein*. Ich werde im Detail erklären, wie die Masken als reine Bilddateien (PNG/Numpy) zwischengespeichert werden und wieso Sie kein Modell-Training für die Zwischenspeicherung brauchen).

### Phase 3: Der fatale Flaschenhals (COLMAP vs. Maskierte Bilder)
> [!WARNING]
> Hier liegt der größte konzeptionelle Denkfehler in Ihrem bisherigen Plan.
In dieser Phase evaluiere ich das Kamera-Tracking:
- **Das COLMAP-Problem:** 3D Gaussian Splatting (und SuGaR) brauchen zwingend Kamerapositionen, die meist mit COLMAP berechnet werden. Wenn Sie in Schritt 2 den Hintergrund schwarz färben, findet COLMAP keine Fixpunkte (Features) mehr, um zu berechnen, wo die Drohne war. Stromleitungen allein haben viel zu wenig Struktur für SfM (Structure-from-Motion).
- **Die Lösungs-Architektur:** Ich werde evaluieren, wie wir den Plan anpassen müssen. (Z.B. COLMAP auf den *Originalbildern* laufen lassen und die schwarzen Masken *danach* nur für das 3DGS-Training anwenden).

### Phase 4: 3D-Meshing (Kann SuGaR dünne Leitungen?)
In dieser Phase knöpfe ich mir den "Finisher" vor:
- **Poisson-Reconstruction vs. Röhren:** SuGaR nutzt zur Mesh-Generierung Poisson-Reconstruction. Diese Mathematik liebt geschlossene, voluminöse Objekte (wie Häuser oder Autos). Ich werde recherchieren, ob SuGaR extrem dünne, offene Röhren (Stromleitungen) überhaupt vernünftig exportieren kann, oder ob das Mesh in Fetzen reißt.
- **Alternativen:** Falls SuGaR bei Leitungen scheitert, werde ich prüfen, ob FlashSplat oder direkt DGtal (wie in Ihrem PA-Exposé erwähnt) die zwingend notwendige Alternative sind.

## Verification Plan

Sobald Sie diesem Plan zustimmen, werde ich die Analyse durchführen und das Ergebnis in einem detaillierten **Feasibility_Report.md** zusammenfassen. Dieser Report wird Ihnen exakt sagen: *"Ja, mach das"* oder *"Nein, ändere diesen Teil, sonst scheitert das Projekt an Woche 2"*.
