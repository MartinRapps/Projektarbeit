# Praxis-Handbuch: System-Setup & Docker für die 3DGS-Pipeline
*(Für Geoinformatik-Studenten)*

Dieses Handbuch übersetzt die komplexen Anforderungen aus dem Feasibility Report in eine praktische, schrittweise Anleitung. Wenn Sie bisher nur mit Windows, QGIS oder Standard-Python gearbeitet haben, ist dieses Dokument Ihr Kompass durch die Linux- und Container-Welt.

---

## 1. Die absoluten Grundlagen (Einfach erklärt)

Wenn Sie eine KI wie "Grounded-SAM" oder "SuGaR" herunterladen, laden Sie keinen fertigen `.exe`-Installer herunter. Sie laden rohen Quellcode herunter, der oft erst auf Ihrem Rechner zusammengebaut (kompiliert) werden muss.

### Was ist WSL2?
Stellen Sie sich vor, all diese KI-Tools sprechen nur fließend Französisch (Linux), Ihr Computer spricht aber nur Deutsch (Windows). Wenn Sie versuchen, die Tools unter Windows auszuführen, gibt es massive Verständigungsprobleme (Kompilierungsfehler). 
**WSL2 (Windows Subsystem for Linux)** ist ein offizieller Übersetzer von Microsoft. Es installiert ein echtes, vollwertiges Linux (Ubuntu) *in* Ihrem Windows, ohne dass Sie Ihren PC neu aufsetzen müssen. 

### Was ist Docker?
Stellen Sie sich Docker wie **abgeschottete GIS-Workspaces** vor.
In der KI-Welt braucht Tool A (Vorverarbeitung) oft exakt Python 3.8 und CUDA 11.3. Tool B (SuGaR) braucht aber Python 3.9 und CUDA 11.8. Installieren Sie beides normal auf Ihrem PC, überschreiben sie sich gegenseitig und nichts funktioniert ("Dependency Hell").
Ein **Docker Container** ist ein virtueller Mini-PC (ein "Labor").
- **Labor 1 (Container A):** Hat nur CUDA 11.3 und Python 3.8. Hier läuft Grounded-SAM.
- **Labor 2 (Container B):** Hat nur CUDA 11.8. Hier läuft SuGaR.
Beide Labore wissen nichts voneinander, stören sich nicht, laufen aber auf demselben PC.

---

## 2. Die System-Analyse: Nativer Linux-PC vs. WSL2

Sollten Sie das Projekt auf Ihrem Windows-Laptop via WSL2 machen, oder sich einen echten Linux-Rechner (z.B. im Uni-Labor) besorgen?

| Kriterium                | Nativer Linux-PC (Ubuntu) | Windows Laptop mit WSL2 |
| :---                | :---                        | :---                    |
| **Geschwindigkeit (GPU)** | 100% (Direkter Zugriff)   | ca. 95% (Minimaler Verlust durch Übersetzung) |
| **Geschwindigkeit (Festplatte)** | 100% (Sehr schnell)       | **Achtung:** 10% bis 100% (Wenn falsch konfiguriert, extrem langsam!) |
| **Einrichtung**     | Erfordert Dual-Boot oder Zweitrechner | Direkt auf Ihrem Alltags-Gerät |
| **Fehleranfälligkeit** | Sehr gering                | Mittel (Oft Probleme mit Treibern in WSL2) |

**Fazit:** Wenn Sie Zugang zu einem dicken Linux-Rechner an der Uni haben: **Nutzen Sie ihn!** Er erspart Ihnen 50% der Kopfschmerzen. Müssen Sie auf Ihrem eigenen Windows-Rechner arbeiten, ist **WSL2 Ihr absolut zwingender Weg**.

---

## 3. Installation & Administrator-Rechte

Hier ist der Ablaufplan. **Wichtig:** Sie benötigen für die grundlegende Einrichtung Administrator-Rechte auf dem Windows-Rechner.

### Schritt 1: WSL2 aktivieren (Erfordert Admin)
1. Öffnen Sie in Windows die Eingabeaufforderung (CMD) **als Administrator**.
2. Tippen Sie: `wsl --install`
3. Starten Sie den PC neu. Nun haben Sie "Ubuntu" als App auf Ihrem Rechner.

> [!CAUTION]
> **Die goldene Dateisystem-Regel:**
> WSL2 ist nur schnell, wenn Sie Dateien *innerhalb* von Linux speichern. Speichern Sie Ihre Bilder und Ihren Code **NIEMALS** unter `C:\Users\Name\Projekt`. Speichern Sie alles im Linux-Pfad: `\\wsl$\Ubuntu\home\IHR_NAME\Projekt`. Das ist kritisch für die Performance!

### Schritt 2: Docker Desktop installieren (Erfordert Admin)
1. Laden Sie **Docker Desktop für Windows** herunter.
2. Führen Sie den Installer **als Administrator** aus.
3. Stellen Sie sicher, dass in den Docker-Einstellungen die Option *"Use the WSL 2 based engine"* aktiviert ist.

### Schritt 3: NVIDIA Treiber (Erfordert Admin)
Sie müssen in Ubuntu/WSL2 *keinen* Grafikkartentreiber installieren! Sie installieren einfach den ganz normalen NVIDIA Game-Ready oder Studio-Treiber in Windows. WSL2 reicht diesen automatisch an das Linux durch.

---

## 4. Abhängigkeiten und die Wahrheit über "Issue #20"

Im *Tracking-Anything-with-DEVA* Repository gibt es das berühmte **Issue #20**, das exakt von Installationen unter WSL2 handelt. Dort scheitern Nutzer reihenweise bei der Installation von "Multi-Scale Deformable Attention" (MSDA).

**Warum passiert Issue #20?**
Um MSDA zu nutzen, muss der Quellcode in Maschinensprache übersetzt (kompiliert) werden. Das erfordert einen C++ Compiler und einen CUDA Compiler (`nvcc`). In WSL2 verheddern sich diese Compiler oft mit den Windows-Umgebungsvariablen oder finden die CUDA-Pfade (`/usr/local/cuda`) nicht.

**Die Lösung durch Docker:**
Da Sie Docker nutzen, ist Issue #20 für Sie **höchstwahrscheinlich völlig irrelevant!**
Warum? Wenn wir den DEVA-Container bauen, nutzen wir als Fundament ein sogenanntes `devel`-Image von NVIDIA (z.B. `nvidia/cuda:11.7.1-devel-ubuntu22.04`). Dieses Image enthält ein isoliertes, perfekt konfiguriertes, reines Ubuntu. Dort drin gibt es keinen Windows-Müll, keine falschen Pfade, sondern nur die perfekten, offiziellen NVIDIA-Compiler. Der MSDA-Code wird *im Container* kompiliert und wird dort fehlerfrei durchlaufen.

---

## 5. Die Architektur: Ihr Plan als Docker Compose

Um nicht für jeden der 3 Schritte endlos lange Docker-Befehle tippen zu müssen, nutzen wir **Docker Compose**. Das ist wie ein Bauplan-Skript, das alle "Labore" (Container) automatisch startet und verbindet.

### Das Prinzip der Volumes (Ordner-Freigabe)
Damit Container A (Vorverarbeitung) die schwarzen Bilder an Container B (Meshing) weitergeben kann, ohne dass sie sich sehen, nutzen wir ein Volume. Das ist ein realer Ordner auf Ihrem WSL2-System (z.B. `~/Projekt/daten`), der in beide Container "hineingespiegelt" wird.

### Vorlage: `docker-compose.yml`

Erstellen Sie in Ihrem Hauptordner eine Datei namens `docker-compose.yml`. Das ist die Blaupause für Ihre Architektur.

```yaml
version: '3.8'

services:
  # Container A: Schritt 1 & 2 (Grounded-SAM, DEVA, Filter)
  vorverarbeitung:
    build:
      context: ./Repos_Pipeline/Tracking-Anything-with-DEVA
      dockerfile: Dockerfile
    container_name: pipeline_vorverarbeitung
    volumes:
      - ./mein_drohnen_datensatz:/daten_ordner  # Spiegelt Ihren Ordner in den Container
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all      # Zwingend nötig, um die GPU durchzureichen
              capabilities: [gpu]
    command: /bin/bash # Hält den Container offen, damit Sie rein können

  # Container B: Schritt 4 (SuGaR Finisher)
  meshing:
    build:
      context: ./Repos_Pipeline/SuGaR
      dockerfile: Dockerfile
    container_name: pipeline_meshing
    volumes:
      - ./mein_drohnen_datensatz:/daten_ordner
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: /bin/bash
```

### Wie Sie damit arbeiten (Workflow):

1. **Starten:** Sie tippen `docker compose up -d`. Beide Labore (Container) wachen auf und laufen im Hintergrund.
2. **Vorverarbeitung:** Sie "betreten" das Vorverarbeitungs-Labor per Befehl (`docker exec -it pipeline_vorverarbeitung /bin/bash`). Sie starten Ihr Python-Filterskript. Das Skript greift auf `/daten_ordner` zu, rechnet, und speichert die schwarzen Bilder wieder im `/daten_ordner` ab. Sie verlassen das Labor.
3. **Schritt 3 (COLMAP Image Swap):** Machen Sie direkt auf dem Host (Linux) – wie im Feasibility Report beschrieben.
4. **Meshing:** Sie betreten das Meshing-Labor (`docker exec -it pipeline_meshing /bin/bash`). Sie starten SuGaR. SuGaR greift auf denselben `/daten_ordner` zu, liest die schwarzen Bilder und trainiert.
5. Das fertige Mesh landet im Ordner und ist sofort auf Ihrem Windows-Rechner sichtbar.

### Fazit
Mit diesem Dokument haben Sie das nötige Grundwissen, um der IT/Dem Admin genau zu sagen, was Sie brauchen (WSL2, Docker Desktop). Und Sie wissen, dass Sie keine Angst vor Linux-Kompilierungsfehlern (Issue #20) haben müssen, solange Sie strikt im Docker-Container bleiben.
