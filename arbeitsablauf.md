# Täglicher Arbeitsablauf (WSL & VS Code)

Dieses Dokument beschreibt die täglichen Schritte, um die Entwicklungsumgebung in WSL (Ubuntu) zu starten und die Arbeit am Ende des Tages sauber und sicher zu beenden.

## 🌅 Arbeitsbeginn (Start in den Tag)

1. **Terminal / WSL starten:**
   Öffne dein Windows Terminal und wähle dein Ubuntu-Profil (alternativ: drücke die Windows-Taste, suche nach "Ubuntu" und öffne es).

2. **Zum Projekt navigieren:**
   Wechsle in den Projektordner in deinem WSL-Heimatverzeichnis:
   ```bash
   cd ~/Projektarbeit
   ```

3. **VS Code direkt aus WSL öffnen:**
   Starte Visual Studio Code und öffne direkt den aktuellen Ordner. Das stellt sicher, dass VS Code über das "WSL-Plugin" im korrekten Linux-Kontext läuft!
   ```bash
   code .
   ```

4. **Aktuellen Code vom Server holen:**
   Sichere dich ab, dass du auf dem neuesten Stand bist (besonders wichtig, wenn du mit anderen arbeitest oder von mehreren Geräten):
   ```bash
   git pull
   ```

5. **Docker prüfen (falls für den Tag benötigt):**
   Stelle sicher, dass *Docker Desktop* unter Windows gestartet ist. Um deine Container aus der Pipeline zu starten:
   ```bash
   docker compose up -d
   ```

---

## 🌇 Feierabend (Arbeit beenden)

1. **Arbeit sichern & hochladen (Git):**
   Damit nichts verloren geht, solltest du am Ende des Tages deinen Code speichern und auf GitHub/GitLab pushen. Das kannst du direkt im integrierten Terminal in VS Code machen (`Strg` + `ö`):
   ```bash
   git status                         # Zeigt dir an, welche Dateien geändert wurden
   git add .                          # Fügt alle Änderungen hinzu
   git commit -m "Tagesergebnis: XYZ" # Speichert sie lokal (ersetze XYZ durch deine Aufgaben)
   git push                           # Lädt die Änderungen ins Repository hoch
   ```

2. **Docker Container stoppen (falls gestartet):**
   Um Ressourcen freizugeben und deinen PC nicht auszubremsen:
   ```bash
   docker compose down
   ```

3. **VS Code schließen:**
   Beende einfach das Fenster von Visual Studio Code ganz normal.

4. **WSL-Terminal beenden:**
   Schließe das WSL-Terminal einfach mit dem Befehl:
   ```bash
   exit
   ```
