# Schritt-für-Schritt Installations- und Setup-Anleitung

Diese Anleitung führt Sie strukturiert von der Systemvorbereitung mit Administratorrechten auf Windows 11 bis hin zum Ausführen der Docker-Container für die Scan-to-BIM-Rekonstruktions-Pipeline. 

---

## 💡 Wichtige Klarstellung zu NVIDIA CUDA & Docker

> [!IMPORTANT]
> **Sie müssen KEINE verschiedenen NVIDIA Toolkit-Versionen auf Ihrem Host-System (Windows) installieren!**
> Einer der größten Vorteile von Docker ist die vollständige Kapselung der Laufzeitumgebungen:
> - **Auf dem Windows-Host** wird lediglich **ein einziger, aktueller NVIDIA-Grafikkartentreiber** installiert.
> - **In den Docker-Containern** sind die jeweils benötigten CUDA-Versionen isoliert vorinstalliert. Für SAM 3.1 in Container A sollte die Runtime CUDA 12.6+, Python 3.12 und PyTorch 2.7+ unterstützen.
> - Der Windows-Host-Treiber leitet die GPU-Befehle über Docker Desktop (WSL2-Backend) weiter, unabhängig davon, welche CUDA-Version im Container läuft.

---

## 📊 Übersicht der Schritte & Admin-Rechte

Führen Sie die Schritte genau in dieser Reihenfolge aus, um doppelte Arbeit oder Konfigurationskonflikte zu vermeiden.

| Schritt | Aufgabe | System | Rechte-Level | Warum? |
| :--- | :--- | :--- | :--- | :--- |
| **Schritt 1** | [NVIDIA Grafiktreiber installieren](#schritt-1-nvidia-grafiktreiber-auf-windows-host) | Windows 11 | 🔐 **ADMINISTRATOR** | Installiert den physischen Treiber im Betriebssystem. |
| **Schritt 2** | [WSL2 aktivieren & Ubuntu einrichten](#schritt-2-wsl2-und-ubuntu-2204-einrichten) | Windows 11 | 🔐 **ADMINISTRATOR** (Teil A)<br>👤 **BENUTZER** (Teil B) | Aktiviert das Windows-Subsystem für Linux und richtet das Linux-Terminal ein. |
| **Schritt 3** | [Docker Desktop installieren](#schritt-3-docker-desktop-installieren--konfigurieren) | Windows 11 | 🔐 **ADMINISTRATOR** (Teil A)<br>👤 **BENUTZER** (Teil B) | Installiert die Virtualisierungs-Engine und verknüpft sie mit WSL2. |
| **Schritt 4** | [Projekt-Ordnerstruktur vorbereiten](#schritt-4-projekt-setup-in-wsl2) | WSL2 (Ubuntu) | 👤 **BENUTZER** | Bereitet das Arbeitsverzeichnis und die Datenordner vor. |
| **Schritt 5** | [Docker-GPU-Verbindung verifizieren](#schritt-5-gpu-zugriff-in-docker-testen) | WSL2 (Ubuntu) | 👤 **BENUTZER** | Prüft, ob Docker-Container auf die Grafikkarte zugreifen können. |
| **Schritt 6** | [Pipeline-Images bauen](#schritt-6-pipeline-images-bauen) | WSL2 (Ubuntu) | 👤 **BENUTZER** | Kompiliert und baut die Container-Images für die 5 Pipeline-Dienste. |
| **Schritt 7** | [Pipeline ausführen](#schritt-7-pipeline-ausführen) | WSL2 / Windows | 👤 **BENUTZER** | Führt die Pipeline-Schritte (inkl. CloudCompare-Breakpoint) aus. |

---

## 🛠️ Detaillierte Installationsschritte

### 🔍 Systemvoraussetzungen & Vorab-Prüfungen

Bevor Sie mit der Installation beginnen, müssen folgende Punkte überprüft werden:

1. **Hardware-Virtualisierung im BIOS/UEFI:**
   - **Warum:** WSL2 läuft in einer schlanken virtuellen Maschine. Wenn die Virtualisierung im BIOS deaktiviert ist, startet WSL2 nicht.
   - **Prüfung:** Öffnen Sie den Windows **Task-Manager** (Strg + Umschalt + Esc), gehen Sie auf den Reiter **Leistung** -> **CPU** und prüfen Sie unten rechts den Eintrag **Virtualisierung**. Dort muss **"Aktiviert"** (bzw. **"Enabled"**) stehen.
   - *Falls deaktiviert (🔐 [ADMINISTRATOR / BIOS]):* Starten Sie den PC neu, gehen Sie ins BIOS/UEFI (meistens Entf- oder F2-Taste beim Start) und aktivieren Sie unter den CPU-Einstellungen "Intel Virtualization Technology" (VT-x) oder "AMD-V / SVM Mode".
2. **Windows-Version prüfen:**
   - **Warum:** Ältere Windows-Builds unterstützen keine GPU-Beschleunigung in WSL2.
   - **Prüfung:** Drücken Sie Windows-Taste + R, geben Sie `winver` ein und drücken Sie Enter.
   - **Mindestanforderung:** Windows 10 (Version 21H2 oder höher, Build 19044+) oder Windows 11.
3. **CloudCompare auf Windows Host:**
   - **Warum:** Nach Schritt 2 der Pipeline müssen Sie die Punktwolke in CloudCompare laden, um die GCP-Punkte zu picken.
   - **Prüfung (👤 [BENUTZER]):** Laden Sie CloudCompare (empfohlen: v2.13 oder neuer) herunter und installieren Sie es auf Windows.

---

### Schritt 1: NVIDIA Grafiktreiber auf Windows Host

#### Welche Version wird benötigt?
Da die Container in der Pipeline unterschiedliche CUDA-Runtimes nutzen und SAM 3.1 in Container A eine CUDA-12.6+-fähige Runtime voraussetzt, muss der Windows-Host-Treiber diese GPU-Weiterleitung unterstützen.
* **Empfehlung:** Installieren Sie einfach den neuesten verfügbaren Treiber (Game Ready, Studio oder RTX Enterprise) von NVIDIA.

#### Aktuelle Version prüfen (Habe ich den richtigen Treiber bereits?):
Führen Sie eine der folgenden Prüfungen durch (👤 **[BENUTZER]**):
* **Möglichkeit A (Schnell über Terminal):** Öffnen Sie die Windows-Eingabeaufforderung (`cmd`) und führen Sie folgenden Befehl aus:
  ```cmd
  nvidia-smi
  ```
   Oben links sehen Sie `Driver Version: XXX.XX` und oben rechts `CUDA Version: YY.Y`. Für SAM 3.1 sollte die angezeigte CUDA-Version mindestens 12.6 unterstützen.
* **Möglichkeit B (NVIDIA Systemsteuerung):** Machen Sie einen Rechtsklick auf den Desktop -> *NVIDIA Systemsteuerung* -> unten links auf *Systeminformationen*. Dort steht die Treiberversion direkt unter "Details".
* **Möglichkeit C (Geräte-Manager):** Drücken Sie Win+X -> *Geräte-Manager* -> *Grafikkarten* -> Rechtsklick auf die NVIDIA-GPU -> *Eigenschaften* -> Reiter *Treiber*. Die letzten 5 Ziffern der Treiberversion entsprechen der NVIDIA-Versionsnummer (z. B. `32.0.15.6070` entspricht Version `560.70`).

#### Treiber installieren / aktualisieren:
1. 🔐 **[ADMINISTRATOR ERFORDERLICH]** Falls Ihr Treiber veraltet ist oder kein Treiber installiert ist: Laden Sie den neuesten Treiber von der [NVIDIA Treiber-Download-Seite](https://www.nvidia.com/download/index.aspx) herunter.
2. 🔐 **[ADMINISTRATOR ERFORDERLICH]** Führen Sie den Installer aus, wählen Sie die Standardoptionen und führen Sie die Installation durch.
3. 👤 **[BENUTZER]** Starten Sie den PC neu.
4. **Verifizierung:** Führen Sie `nvidia-smi` im `cmd` aus, um die erfolgreiche Erkennung zu bestätigen.

---

### Schritt 2: WSL2 und Ubuntu 22.04 einrichten
WSL2 ermöglicht es, ein vollwertiges Linux-System direkt unter Windows auszuführen.

1. 🔐 **[ADMINISTRATOR ERFORDERLICH]** Suchen Sie im Windows-Startmenü nach **PowerShell**, machen Sie einen Rechtsklick darauf und wählen Sie **"Als Administrator ausführen"**. Führen Sie folgenden Befehl aus:
   ```powershell
   wsl --install -d Ubuntu-22.04
   ```
   *Dieser Befehl aktiviert die benötigten Windows-Features (Virtual Machine Platform, WSL) und lädt Ubuntu 22.04 herunter.*
2. 👤 **[BENUTZER]** Starten Sie den Computer neu, wenn Sie dazu aufgefordert werden.
3. 👤 **[BENUTZER]** Nach dem Neustart öffnet sich automatisch ein Ubuntu-Terminalfenster. Falls nicht, suchen Sie im Startmenü nach **Ubuntu 22.04** und starten Sie es.
4. 👤 **[BENUTZER]** Vergeben Sie im Terminal einen **Linux-Benutzernamen** und ein **Passwort** (dieses Passwort wird bei `sudo`-Befehlen benötigt; die Passworteingabe wird nicht visualisiert).
5. 🔐 **[ADMINISTRATOR ERFORDERLICH]** (Optional) Stellen Sie in einer administrativen PowerShell sicher, dass WSL2 als Standardversion definiert ist:
   ```powershell
   wsl --set-default-version 2
   ```

⚙️ Zusatzschritt: WSL2-Ressourcen optimieren (.wslconfig)
- **Warum:** Das Training von 3D Gaussian Splatting (STS, SuGaR) benötigt viel System-RAM. WSL2 limitiert standardmäßig die RAM-Nutzung auf 50% des Host-RAMs. Um Out-Of-Memory-Abstürze (OOM) zu verhindern, sollten Sie WSL2 explizit mehr RAM zuweisen.
- **Vorgehensweise (👤 [BENUTZER]):**
  1. Drücken Sie Windows-Taste + R, geben Sie `%USERPROFILE%` ein und drücken Sie Enter.
  2. Erstellen Sie in diesem Ordner eine Textdatei namens `.wslconfig` (achten Sie darauf, dass keine `.txt` Endung angehängt ist).
  3. Fügen Sie folgenden Inhalt ein (Beispiel für ein System mit 64 GB RAM; passen Sie die Werte an Ihr System an):
     ```ini
     [wsl2]
     memory=48GB  # Reserviert 48 GB RAM für Linux
     processors=8 # Nutzt 8 CPU-Kerne
     ```
  4. Um die Konfiguration zu übernehmen, öffnen Sie eine Windows-Eingabeaufforderung und beenden Sie WSL mit `wsl --shutdown`. Beim nächsten Start von WSL greifen die neuen Limits.

---

### Schritt 3: Docker Desktop installieren & konfigurieren
Docker Desktop verwaltet die Container auf Windows und nutzt das WSL2-Linux als Rechenkern.

1. 👤 **[BENUTZER]** Laden Sie **Docker Desktop für Windows** von der offiziellen [Docker-Website](https://www.docker.com/products/docker-desktop/) herunter.
2. 🔐 **[ADMINISTRATOR ERFORDERLICH]** Führen Sie den Installer aus. Treffen Sie folgende Einstellungen bei den Checkboxen:
   - **Aktivieren (Häkchen setzen):** `Use WSL 2 instead of Hyper-V (recommended)` (Sehr wichtig, da unsere Linux-Container WSL2 benötigen!).
   - **Deaktivieren (KEIN Häkchen setzen):** `Allow Windows containers` (Unsere Pipeline basiert auf Linux/Ubuntu-Containern. Wenn Windows-Container aktiviert sind, funktioniert die Pipeline nicht!).
   - **Installationstyp:** Wählen Sie die stabile **All-users installation** (nicht die Beta Per-user installation).
3. 👤 **[BENUTZER]** Starten Sie den PC nach der Installation neu.
4. 👤 **[BENUTZER]** Starten Sie Docker Desktop über das Startmenü und akzeptieren Sie die Nutzungsbedingungen.
5. 👤 **[BENUTZER]** **WSL2-Integration aktivieren (Sehr wichtig!):**
   - Klicken Sie in Docker Desktop oben rechts auf das Zahnrad-Symbol (**Settings**).
   - Navigieren Sie zu **Resources > WSL Integration**.
   - Aktivieren Sie den Schalter **"Enable integration with my default WSL distro"** und aktivieren Sie zusätzlich den Schalter bei **Ubuntu-22.04**.
   - Klicken Sie auf **Apply & Restart**.

---

### Schritt 4: Projekt-Setup in WSL2
Für maximale Schreib-/Lesegeschwindigkeit (I/O) und um Berechtigungskonflikte zu vermeiden, sollte das Projekt direkt im Linux-Dateisystem abgelegt werden.

> [!WARNING]
> Speichern Sie Ihr Projekt **nicht** unter `/mnt/c/Users/...` (Windows-Laufwerk in WSL), da die Dateiübertragung zwischen Windows und Linux über diese Schnittstelle extrem verlangsamt wird. Nutzen Sie stattdessen den Linux-Home-Pfad (`~/`).

1. 👤 **[BENUTZER]** Öffnen Sie Ihr Ubuntu 22.04 Terminal.
2. 👤 **[BENUTZER]** Klonen Sie Ihr Git-Repository in Ihr Linux-Benutzerverzeichnis:
   ```bash
   cd ~
   git clone <repository-url> Projektarbeit
   cd Projektarbeit
   ```
3. 👤 **[BENUTZER]** Erstellen Sie die für die Pipeline benötigten Datenordner:
   ```bash
   mkdir -p data/01_raw data/02_frames data/03_masks data/04_sfm data/05_3dgs data/06_mesh data/07_centerline data/08_gis data/09_evaluation
   ```

---

### Schritt 5: GPU-Zugriff in Docker testen
Bevor Sie zeitaufwendige Images bauen, prüfen Sie, ob Docker die Grafikkarte über WSL2 ansteuern kann.

1. 👤 **[BENUTZER]** Führen Sie im Ubuntu-Terminal folgenden Test-Container aus:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi
   ```
2. **Ergebnis:** Wenn Sie die gleiche GPU-Tabelle wie in Schritt 1 auf Windows sehen, funktioniert die GPU-Weiterleitung über WSL2 und Docker Desktop fehlerfrei!
   *(Der Container lädt das minimale CUDA-Image herunter, führt `nvidia-smi` aus und löscht sich danach selbst).*

---

### Schritt 6: Pipeline-Images bauen
Bauen Sie nun die in [docker-compose.yml](docker-compose.yml) definierten 5 Container-Dienste auf.

1. 👤 **[BENUTZER]** Führen Sie im Projektverzeichnis (`~/Projektarbeit`) den Build-Befehl aus:
   ```bash
   docker compose build
   ```
   *Dieser Vorgang kann je nach Internetleitung und Systemgeschwindigkeit 15–30 Minuten dauern, da Bibliotheken wie PyTorch, COLMAP, SuGaR und DGtal kompiliert und installiert werden.*

---

### Schritt 7: Pipeline ausführen
Die Ausführung erfolgt über das Master-Skript [run_pipeline.sh](run_pipeline.sh).

1. 👤 **[BENUTZER]** Kopieren Sie Ihre Videodatei (`video.mp4`) und die GCP-Koordinatendateien in den Ordner `data/01_raw/`.
2. 👤 **[BENUTZER]** Machen Sie das Skript ausführbar und starten Sie es:
   ```bash
   chmod +x run_pipeline.sh
   ./run_pipeline.sh
   ```

> [!NOTE]
> Das SAM-Preprocessing in [run_sam3.sh](run_sam3.sh) erkennt jetzt automatisch ein Bild aus `data/01_raw` (`.jpg`, `.jpeg`, `.png`) und nutzt dafür die SAM-3.1-Bildsegmentierung. Wenn stattdessen ein Video vorhanden ist, wird weiter der Video-Flow verwendet.

#### 📌 Der manuelle Breakpoint (CloudCompare)
Nach **Schritt 2 (SfM - COLMAP)** pausiert das Skript automatisch:
1. 👤 **[BENUTZER]** Öffnen Sie **CloudCompare** auf Ihrem Windows-System.
2. 👤 **[BENUTZER]** Laden Sie die Datei `data/04_sfm/points3D.ply` in CloudCompare.
3. 👤 **[BENUTZER]** Führen Sie das Point Picking anhand Ihrer GCPs durch, berechnen Sie die 4x4-Transformationsmatrix (relative Georeferenzierung) und speichern Sie diese als Textdatei in `data/04_sfm/matrix.txt`.
4. 👤 **[BENUTZER]** Gehen Sie zurück ins Ubuntu-Terminal und drücken Sie **[Enter]**, um das Training (STS) und Meshing (SuGaR) fortzusetzen.

---

## 📝 Hinweis zu SAM 3.1

Die offiziellen SAM-3.1-Release-Notes zeigen, dass das Modell inzwischen auf **Python 3.12**, **PyTorch 2.7+** und eine **CUDA-12.6+-fähige GPU-Umgebung** ausgelegt ist. Zusätzlich ist für die Checkpoints ein freigeschalteter Hugging-Face-Zugriff nötig.

Für diese Pipeline heißt das: Container A sollte nicht nur GPU-Zugriff haben, sondern auch tatsächlich auf einer CUDA-tauglichen Basis laufen, bevor die SAM-3.1-Modelle produktiv eingesetzt werden. Die restlichen Container können ihre jeweiligen, getrennten CUDA-Runtimes behalten.

---

## 🔍 Problemlösungen (Troubleshooting)

* **Fehler: `docker: Client.Timeout exceeded while awaiting headers`**
  * *Lösung:* Starten Sie Docker Desktop auf Windows neu.
* **Fehler: `Error response from daemon: could not select device driver "" with capabilities: [[gpu]]`**
  * *Lösung:* Die Integration in Docker Desktop ist fehlerhaft. Stellen Sie sicher, dass in Docker Desktop unter Settings > Resources > WSL Integration die Checkbox für Ihre Ubuntu-Distribution aktiv ist und starten Sie Docker neu.
* **Sehr langsames Dateihandling unter WSL2**
  * *Lösung:* Stellen Sie sicher, dass Ihr Projektverzeichnis im Linux-Dateisystem liegt (`/home/<user>/...` oder `~/...`) und **nicht** auf dem Windows-Mount `/mnt/c/...`.
