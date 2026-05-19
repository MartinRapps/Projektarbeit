# Step-by-Step Guide: Docker & WSL2 Setup für die 3DGS-Pipeline

Dieses Dokument ist Ihre exakte "Copy & Paste"-Anleitung, um die 3DGS Scan-to-BIM Pipeline (Grounded-SAM, DEVA/Gaussian-Grouping, SuGaR) konfliktfrei auf Ihrem Windows-System zum Laufen zu bringen.

---

## 1. Host-System vorbereiten (Windows)
*Diese Schritte erfordern Administrator-Rechte in Windows.*

### 1.1 Windows Subsystem for Linux (WSL2) installieren
1. Öffnen Sie die **Eingabeaufforderung (CMD) als Administrator**.
2. Führen Sie folgenden Befehl aus:
   ```cmd
   wsl --install
   ```
3. Starten Sie Ihren Computer neu. Es wird sich automatisch ein Fenster öffnen, in dem Sie einen UNIX-Benutzernamen und ein Passwort für Ihre neue Ubuntu-Umgebung vergeben (Merken Sie sich das Passwort, es ist Ihr Linux-Admin-Passwort).

### 1.2 Docker Desktop installieren
1. Laden Sie [Docker Desktop für Windows](https://docs.docker.com/desktop/install/windows-install/) herunter.
2. Installieren Sie das Programm (Admin-Rechte erforderlich).
3. Öffnen Sie Docker Desktop. Gehen Sie in die **Settings (Zahnrad-Icon)** -> **General** und stellen Sie sicher, dass **"Use the WSL 2 based engine"** aktiviert ist.

### 1.3 NVIDIA Treiber aktualisieren
Sie benötigen **keinen** Treiber in Linux/WSL2 zu installieren. Laden Sie einfach den neuesten "NVIDIA Studio" oder "Game Ready" Treiber für Ihre Grafikkarte unter Windows herunter und installieren Sie ihn. WSL2 reicht diesen Treiber automatisch an Linux durch.

---

## 2. Linux-Umgebung & Toolkit (WSL2)
*Ab hier arbeiten Sie ausschließlich in der Ubuntu-App, die Sie gerade installiert haben.*

### 2.1 NVIDIA Container Toolkit installieren
Damit Docker auf Ihre Grafikkarte zugreifen kann, müssen wir das Toolkit in Ubuntu installieren.
1. Öffnen Sie die App **Ubuntu** über das Windows-Startmenü.
2. Führen Sie nacheinander diese Befehle aus (Copy & Paste):
   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
     && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   ```
3. Aktualisieren Sie die Paketquellen und installieren Sie das Toolkit:
   ```bash
   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   ```
4. Starten Sie Docker Desktop in Windows einmal neu.

---

## 3. Die Projekt-Ordnerstruktur anlegen
**WICHTIG:** Legen Sie diese Ordner im Linux-Dateisystem an, niemals auf `C:\`.

Führen Sie im Ubuntu-Terminal aus:
```bash
# Erstellen des Hauptordners und der Unterordner
mkdir -p ~/scan2bim_pipeline/daten
mkdir -p ~/scan2bim_pipeline/vorverarbeitung
mkdir -p ~/scan2bim_pipeline/meshing

# In den Hauptordner wechseln
cd ~/scan2bim_pipeline
```
Kopieren Sie jetzt Ihre originalen Drohnenbilder (und später die COLMAP-Daten) in den Ordner `~/scan2bim_pipeline/daten`. (Sie können von Windows aus über den Explorer via `\\wsl$\Ubuntu\home\IHR_NAME\scan2bim_pipeline\daten` darauf zugreifen).

---

## 4. Dockerfiles und Compose-Setup erstellen

Da fertige GitHub-Images oft veraltet sind, bauen wir unsere eigenen sauberen Umgebungen basierend auf offiziellen NVIDIA Entwickler-Images (`devel`).

### 4.1 Die Vorverarbeitung (Grounded-SAM / DEVA / Gaussian Grouping)
Dieses Image benötigt alte Frameworks (CUDA 11.3, Python 3.8).

Erstellen Sie eine Datei `Dockerfile` im Ordner `~/scan2bim_pipeline/vorverarbeitung/`:
```bash
nano ~/scan2bim_pipeline/vorverarbeitung/Dockerfile
```
Fügen Sie folgenden Code ein (Speichern mit `STRG+O`, `Enter`, Schließen mit `STRG+X`):
```dockerfile
# Basis: CUDA 11.3 mit Compiler (devel)
FROM nvidia/cuda:11.3.1-devel-ubuntu20.04

# Umgebungsvariablen setzen, um interaktive Prompts zu vermeiden
ENV DEBIAN_FRONTEND=noninteractive
ENV TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6+PTX"

# Python 3.8 und git installieren
RUN apt-get update && apt-get install -y \
    python3.8 python3-pip git wget libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1

# PyTorch 1.12.1 passend zu CUDA 11.3 installieren
RUN pip install torch==1.12.1+cu113 torchvision==0.13.1+cu113 torchaudio==0.12.1 --extra-index-url https://download.pytorch.org/whl/cu113

# Arbeitsverzeichnis setzen
WORKDIR /workspace

# Hier könnten Sie per RUN git clone Ihre Repositories klonen
# RUN git clone https://github.com/lkeab/gaussian-grouping.git

CMD ["tail", "-f", "/dev/null"]
```

### 4.2 Das Meshing (SuGaR)
SuGaR erfordert neuere Frameworks (CUDA 11.8).

Erstellen Sie eine Datei `Dockerfile` im Ordner `~/scan2bim_pipeline/meshing/`:
```bash
nano ~/scan2bim_pipeline/meshing/Dockerfile
```
Code einfügen:
```dockerfile
# Basis: CUDA 11.8 mit Compiler (devel)
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0+PTX"

# Python 3.9+ und Abhängigkeiten
RUN apt-get update && apt-get install -y \
    python3-pip python3-dev git wget libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# PyTorch 2.0.1 passend zu CUDA 11.8 installieren
RUN pip install torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cu118

# SuGaR klonen (beispielhaft)
WORKDIR /workspace
RUN git clone https://github.com/Anttwo/SuGaR.git
WORKDIR /workspace/SuGaR
RUN pip install -r requirements.txt || true

CMD ["tail", "-f", "/dev/null"]
```

### 4.3 Die `docker-compose.yml` (Der Bauplan)
Im Hauptordner `~/scan2bim_pipeline/` erstellen Sie die Steuerungsdatei:
```bash
nano ~/scan2bim_pipeline/docker-compose.yml
```
Code einfügen:
```yaml
version: '3.8'

services:
  vorverarbeitung:
    build:
      context: ./vorverarbeitung
      dockerfile: Dockerfile
    container_name: pipeline_vorverarbeitung
    volumes:
      - ./daten:/workspace/daten  # Teilt den Datenordner
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  meshing:
    build:
      context: ./meshing
      dockerfile: Dockerfile
    container_name: pipeline_meshing
    volumes:
      - ./daten:/workspace/daten  # Teilt denselben Datenordner
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

---

## 5. Ausführung & Tägliche Nutzung

### 1. Systeme starten
Im Terminal in WSL2 (im Ordner `~/scan2bim_pipeline/`):
```bash
# Baut die Images (Dauert beim ersten Mal 10-20 Minuten)
docker compose build

# Startet die Container im Hintergrund
docker compose up -d
```

### 2. Vorverarbeitung durchführen
```bash
# Betritt den Vorverarbeitungs-Container
docker exec -it pipeline_vorverarbeitung bash

# -> Sie sind jetzt im Container!
# -> Navigieren Sie zu Ihren Repositories und führen Sie Ihre Python-Skripte aus.
# -> Speichern Sie die schwarzen Masken in /workspace/daten
# -> Verlassen Sie den Container mit 'exit'
```

### 3. Der COLMAP Image Swap (Auf dem Host)
Führen Sie nun COLMAP lokal auf Ihrem Host-System durch, nutzen Sie die Originalbilder, generieren Sie die Punktwolke und kopieren Sie danach die schwarzen Masken (mit denselben Dateinamen) in den `/images/` Ordner Ihres COLMAP-Verzeichnisses innerhalb von `~/scan2bim_pipeline/daten`.

### 4. SuGaR Meshing durchführen
```bash
# Betritt den Meshing-Container
docker exec -it pipeline_meshing bash

# -> Führen Sie die SuGaR Trainingsskripte aus.
# -> Referenzieren Sie auf die bearbeiteten COLMAP-Daten in /workspace/daten
# -> Das finale Mesh wird in /workspace/daten abgelegt.
# -> Verlassen Sie den Container mit 'exit'
```

### 5. Systeme herunterfahren
Wenn Sie fertig sind, stoppen Sie die "Labore", um RAM freizugeben:
```bash
docker compose down
```

**Ergebnis:** Ihr finales `.ply` / `.obj` Mesh liegt sicher im Ordner `~/scan2bim_pipeline/daten` und kann über den Windows Explorer in DGtal, Blender oder CloudCompare geöffnet werden.
