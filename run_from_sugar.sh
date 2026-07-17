#!/bin/bash
set -e

echo "=== Starting Scan-to-BIM Reconstruction Pipeline FROM SUGAR ONWARDS ==="
echo "(Uses the unfiltered standard point_cloud.ply with full-image stock-SuGaR supervision.)"
echo "For the object-only mask-aware workflow, run ./run_masked_sugar.sh instead."

# Explanations for SuGaR configuration options (invoked via the 'EXPLAIN' keyword at the prompts)
explain_regularization() {
    echo ""
    echo "  dn_consistency : (EMPFOHLEN) Kombiniert Dichte- und Normalen-Konsistenz-Regularisierung."
    echo "                   Erzwingt, dass die Gaussians sich flach an echte Oberflaechen anschmiegen und"
    echo "                   ihre Normalen mit der lokalen Tiefenkarte uebereinstimmen. Liefert laut SuGaR-Autoren"
    echo "                   die beste Mesh-Qualitaet, besonders fuer duenne/zylindrische Objekte wie Kabel."
    echo "  density        : Nutzt nur eine Dichte-basierte Regularisierung (SDF ueber Gaussian-Dichtefunktion)."
    echo "                   Schneller, aber tendenziell 'wolkigere', weniger scharfe Oberflaechen."
    echo "  sdf            : Nutzt eine reine Signed-Distance-Function-Regularisierung. Historisch aeltester Ansatz"
    echo "                   von SuGaR, in der Praxis meist von dn_consistency in der Qualitaet uebertroffen."
    echo ""
}

explain_refinement_time() {
    echo ""
    echo "  short  : ~2000 Refinement-Iterationen. Schnell (Minuten), ideal zum Testen der Pipeline/Parameter."
    echo "  medium : ~7000 Refinement-Iterationen. Guter Kompromiss aus Qualitaet und Rechenzeit."
    echo "  long   : ~15000 Refinement-Iterationen. Hoechste Detailtreue, aber deutlich laengere Trainingszeit."
    echo ""
}

# Autopilot Prompt configuration directly at the beginning
read -p "Moechten Sie die Pipeline im Autopilot-Modus ausfuehren? (Alle Standardvorgaben automatisch waehlen) (y/n) [Default: n]: " USER_AUTOPILOT
if [[ "$USER_AUTOPILOT" =~ ^[Yy]$ ]]; then
    AUTOPILOT="true"
    echo "Autopilot-Modus AKTIVIERT. Interaktive Abfragen werden mit Standardwerten beantwortet."
else
    AUTOPILOT="false"
fi

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "=========================================================="
echo "SuGaR Mesh Reconstruction Configuration"
echo "=========================================================="
if [[ "$AUTOPILOT" == "true" ]]; then
    ITERATIONS=7000
    REGULARIZATION="dn_consistency"
    REFINEMENT_TIME="short"
    echo "Autopilot aktiv: Iteration=7000, Regularisierung=dn_consistency, Refinement-Dauer=short (2000 Iterationen)."
else
    read -p "Which STS/3DGS checkpoint iteration should be loaded? [Default: 7000]: " USER_ITERATIONS
    ITERATIONS=${USER_ITERATIONS:-7000}

    while true; do
        read -p "Regularization type (sdf/density/dn_consistency, oder 'EXPLAIN' fuer Erklaerung) [Default: dn_consistency]: " USER_REG
        if [[ "${USER_REG,,}" == "explain" ]]; then
            explain_regularization
            continue
        fi
        REGULARIZATION=${USER_REG:-dn_consistency}
        break
    done

    while true; do
        read -p "Refinement time (short/medium/long, oder 'EXPLAIN' fuer Erklaerung) [Default: short]: " USER_REFTIME
        if [[ "${USER_REFTIME,,}" == "explain" ]]; then
            explain_refinement_time
            continue
        fi
        REFINEMENT_TIME=${USER_REFTIME:-short}
        break
    done
fi
echo "--------------------------------------------------------"
echo "Active Configuration:"
echo " - Vanilla 3DGS Checkpoint Iteration: $ITERATIONS"
echo " - Regularization Type: $REGULARIZATION"
echo " - Refinement Time: $REFINEMENT_TIME"
echo "--------------------------------------------------------"

# NOTE: extract_mesh.py alone cannot regularize a coarse SuGaR model - it only extracts a mesh
# from an already-trained coarse checkpoint. The '-r/--regularization_type' flag belongs to the
# root-level train.py, which runs: coarse SuGaR training (regularized) -> mesh extraction -> refinement.
echo "[Step 4/5] Running SuGaR Full Pipeline (Coarse Training -> Mesh Extraction -> Refinement)..."
# Make sure the checkpoint path has a trailing slash because SuGaR simply concatenates 'cameras.json' to it!
docker compose run --rm sugar-meshing python3 train.py \
    -s /data/05_3dgs \
    -c /data/05_3dgs/output/ \
    -i "$ITERATIONS" \
    -r "$REGULARIZATION" \
    --refinement_time "$REFINEMENT_TIME" \
    --eval True

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline (SuGaR to Georeferencing) Completed Successfully. Final outputs saved in data/08_gis/ ==="
