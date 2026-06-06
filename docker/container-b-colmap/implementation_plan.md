# Implementation Plan: COLMAP Container Integration (Container B)

Dieses Dokument beschreibt den Implementierungsplan für die Bereitstellung des hochperformanten, GPU-beschleunigten **COLMAP Containers (Container B)** innerhalb unseres Scan-to-BIM-Workflows.

---

## 1. IST-Zustand und Problemanalyse
Der aktuelle Zustand von Container B weist zwei signifikante Schwachstellen auf, die eine produktive Ausführung verhindern:

1. **CPU-Flaschenhals im aktuellen Standard-Dockerfile:**
   Das bisherige Dockerfile (`docker/container-b-colmap/Dockerfile`) baut auf einem rohen Ubuntu-Image auf und installiert COLMAP via `apt-get install -y colmap`. Dies resultiert in einem veralteten Release des Ubuntu-Paketmanagers, das **keinerlei CUDA- bzw. GPU-Beschleunigung** besitzt. Die Berechnungen für Structure from Motion (SfM) würden rein auf der CPU laufen und Stunden statt Minuten dauern.

2. **Fehlender Quellcode bei lokalem Buildversuch (`Dockerfile.txt`):**
   Das im Ordner enthaltene `Dockerfile.txt` orientiert sich am offiziellen Build-Rezept des COLMAP-Repositories und versucht, den Quellcode mittels `COPY . /colmap` zu kopieren und per `cmake` und `ninja` selbst zu kompilieren. Da sich dieses Dockerfile in unserem Projekt-Workspace und nicht im echten COLMAP-Software-Repository befindet, kopiert der Build-Kontext unsere georeferenzierten Daten und Python-Skripte statt des C++ Quellcodes von COLMAP. Ein Buildversuch scheitert somit sofort.
   Zusätzlich führt das lokale Kompilieren von COLMAP (mit seinen komplexen Abhängigkeiten wie Ceres Solver, Boost, Qt6 und FreeImage) zu extrem langen Build-Zeiten (30–45 Minuten) und droht bei weniger als 32\,GB RAM regelmäßig durch Compiler-OOM-Crashs abzustürzen.

---

## 2. Der Lösungsansatz (Warum dieser Plan funktioniert)
Anstatt das Rad neu zu erfinden und COLMAP mühsam und fehleranfällig lokal im Container aus den Quellen zu übersetzen, nutzen wir das offizielle, von den Maintainern optimierte und bereits vorkompilierte **offizielle Docker-Image `colmap/colmap:latest`**, das vollständig für NVIDIA CUDA und GPU-Hardwarezugriff vorkonfiguriert ist.

### Der Plan im Detail:
1. **Modernisierung des Dockerfiles (`docker/container-b-colmap/Dockerfile`):**
   Wir ersetzen das bisherige CPU-Dockerfile durch ein schlankes, hochmodernes Rezept, das direkt auf `colmap/colmap:latest` aufsetzt.
   Dieses Image bringt standardmäßig:
   - Eine extrem optimierte, CUDA-aktivierte Version von COLMAP mit GPU-Support.
   - Alle benötigten Grafik- und Rendering-Bibliotheken (EGL/GLX für Headless GPU und GUI).
   - Hervorragende Stabilität ohne lokale Kompilierschleifen.

2. **Optimierung der Docker-Compose Integration (`docker-compose.yml`):**
   Der Service `colmap-sfm` ist bereits korrekt mit der GPU-Freigabe (`gpus: all` und Device-Reservations) definiert. Mit dem neuen Dockerfile dockt das System nun direkt an die CUDA-Kerne der RTX A4000 Grafikkarte an.

3. **Verifizierung des SfM-Scripts (`src/scripts/run_sfm.sh`):**
   Das bestehende Skript läuft nahtlos, da es die Standard-CLI-Befehle von `colmap` aufruft, welche im offiziellen Image global verfügbar sind.

---

## 3. Was noch fehlt / Mögliche Blocker im Auge behalten
- **NVIDIA Container Toolkit auf dem Host:**
  Damit der Container auf die physikalischen CUDA-Kerne zugreifen kann, muss das `nvidia-container-toolkit` auf dem Host-Betriebssystem installiert sein. (In unserem Pipeline-Setup ist dies für `sam3-preprocess` bereits erfolgreich im Einsatz, weshalb es auch hier sofort funktionieren wird).
- **GUI vs. Headless im Terminal:**
  Das interaktive GUI von COLMAP verlangt ein funktionierendes X11-Forwarding (`DISPLAY`-Variable). Für automatisierte Pipeline-Aufrufe (z.B. unser `run_sfm.sh`) läuft COLMAP jedoch rein über das CLI im Headless-Modus (ohne grafische Oberfläche), was hochgradig robust und fehlerresistent ist.

---

## 4. Konkrete Umsetzungsschritte
1. **Anpassung der `Dockerfile`:** Aktualisierung des Inhalts auf die performante `colmap/colmap:latest` Basis.
2. **Build-Prozess anstoßen:** Ausführung von `docker compose build colmap-sfm`.
3. **Verifikation:** Testen der CUDA-Verfügbarkeit innerhalb des frisch generierten Containers.
