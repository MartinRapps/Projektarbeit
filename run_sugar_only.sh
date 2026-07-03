#!/bin/bash
set -e

# Pfade definieren
DATA_DIR="data"
STS_OUT_DIR="$DATA_DIR/05_3dgs/output"

echo "=== Initialisiere Datenordner ==="
# Erstelle die gesamte Ordnerstruktur, falls noch nicht vorhanden
mkdir -p "$DATA_DIR/01_raw" \
         "$DATA_DIR/02_frames" \
         "$DATA_DIR/03_masks" \
         "$DATA_DIR/04_sfm" \
         "$DATA_DIR/05_3dgs" \
         "$DATA_DIR/05_3dgs/output" \
         "$DATA_DIR/06_mesh" \
         "$DATA_DIR/07_centerline" \
         "$DATA_DIR/08_gis" \
         "$DATA_DIR/09_evaluation"

echo "Ordnerstruktur unter '$DATA_DIR/' wurde überprüft/erstellt."

# Iterations-Variable für STS-Output definieren (Standard: 7000)
ITERATIONS=${1:-7000}
PLY_PATH="$STS_OUT_DIR/point_cloud/iteration_${ITERATIONS}/point_cloud.ply"
CFG_PATH="$STS_OUT_DIR/cfg_args"

echo "=== Überprüfe Eingabedaten für SuGaR ==="
echo "Erwarte Punktwolke unter: $PLY_PATH"
echo "Erwarte Konfiguration unter: $CFG_PATH"

MISSING=0

if [ ! -f "$PLY_PATH" ]; then
    echo "❌ Fehler: Punktwolke '$PLY_PATH' wurde nicht gefunden!"
    MISSING=1
fi

if [ ! -f "$CFG_PATH" ]; then
    echo "❌ Fehler: Konfigurationsdatei '$CFG_PATH' wurde nicht gefunden!"
    MISSING=1
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "Bitte kopiere deine bereits vorhandenen 3DGS/STS-Ergebnisse in folgende Verzeichnisse:"
    echo "  1. Die point_cloud.ply nach: $DATA_DIR/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/"
    echo "  2. Die cfg_args nach: $DATA_DIR/05_3dgs/output/"
    echo "  3. Die Kameras/Eingabedaten (z.B. cameras.json) nach: $DATA_DIR/05_3dgs/"
    echo ""
    exit 1
fi

echo "✅ Alle benötigten Eingabedaten sind vorhanden."
echo ""
echo "=== Starte SuGaR Mesh Rekonstruktion (Schritt 4/5) ==="

docker compose run --rm sugar-meshing python3 extract_mesh.py --regularization dn_consistency

echo ""
echo "=== SuGaR erfolgreich beendet! ==="
echo "Die Ergebnisse wurden unter '$DATA_DIR/06_mesh/' bzw. im SuGaR-Ausgabeverzeichnis gespeichert."
