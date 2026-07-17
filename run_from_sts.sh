#!/bin/bash
set -e

echo "=== Starting Scan-to-BIM Reconstruction Pipeline FROM STS ONWARDS ==="

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

# Step 3: Object-Specific 3DGS (Segment-then-Splat STS)
echo "[Step 3/5] Setting up Segment-then-Splat (STS) workspace structure..."
docker compose run --rm sam3-preprocess python3 /app/src/python/prep_sts_scene.py

echo "[Step 3/5] Running STS object-specific 3D point cloud initialization..."
docker compose run --rm sts-training python3 helpers/object_specific_initialization.py --scene_root /data/05_3dgs

echo "=========================================================="
echo "STS Gaussian Splatting Training Configuration"
echo "=========================================================="
if [[ "$AUTOPILOT" == "true" ]]; then
    ITERATIONS=7000
    DEFAULT_STAGE2=5000
    STAGE2_ITERS=5000
    ON_THE_FLY=""
    echo "Autopilot aktiv: Setze standardmaessig 7000 Iterationen (Stage 2: 5000) ohne On-The-Fly-Laden."
else
    read -p "Enter total training iterations (recommended: 7000 to 15000) [Default: 7000]: " USER_ITERATIONS
    ITERATIONS=${USER_ITERATIONS:-7000}

    # Suggest Stage 2 iteration limit based on total iterations
    DEFAULT_STAGE2=$(( ITERATIONS * 5 / 7 )) # Scales stage 2 to be roughly 5/7th of total iterations (like 5000/7000)
    read -p "Enter Stage 2 fine-tuning iterations [Default: $DEFAULT_STAGE2]: " USER_STAGE2
    STAGE2_ITERS=${USER_STAGE2:-$DEFAULT_STAGE2}

    # Densification coordinates and scaling
    read -p "Enable GPU-saving 'on-the-fly' image loading? (y/n) [Default: n]: " USER_LY
    if [[ "$USER_LY" =~ ^[Yy]$ ]]; then
        ON_THE_FLY="--load2gpu_on_the_fly"
    else
        ON_THE_FLY=""
    fi
fi

echo "--------------------------------------------------------"
echo "Active Configurations:"
echo " - Total Optimization Iterations: $ITERATIONS"
echo " - Stage 2 Fine-Tuning Iterations: $STAGE2_ITERS"
echo " - GPU On-The-Fly Mode: ${ON_THE_FLY:-Disabled}"
echo "--------------------------------------------------------"

echo "[Step 3/5] Starting Segment-then-Splat (STS) Object-Specific 3DGS Training..."
docker compose run --rm sts-training python3 train.py \
    -s /data/05_3dgs \
    -m /data/05_3dgs/output \
    --eval \
    --iterations "$ITERATIONS" \
    --stage2_iters "$STAGE2_ITERS" \
    --save_iterations "$ITERATIONS" \
    --test_iterations "$ITERATIONS" \
    $ON_THE_FLY

# Step 3.5: Export an object-only STS cloud without mutating the standard
# full-scene checkpoint. Stock SuGaR uses full RGB supervision, so replacing
# point_cloud.ply here would recreate an object-cloud/full-image mismatch.
echo "[Step 3.5/5] Preserving the full STS cloud and exporting a filtered object cloud..."
docker compose run --rm sts-training python3 -c "import os, shutil; base='/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'; src=f'{base}/point_cloud.ply'; dst=f'{base}/point_cloud_full_scene.ply'; os.path.exists(src) or (_ for _ in ()).throw(FileNotFoundError(src)); shutil.copy2(src, dst)"
docker compose run --rm sts-training python3 /app/src/python/filter_cable_pc.py \
    --input_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" \
    --output_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_cable.ply" \
    --level m \
    --object_id 0

echo "[Step 3.5/5] Standard point_cloud.ply remains full-scene for a consistent stock-SuGaR baseline."
echo "              Run ./run_masked_sugar.sh for the object-only, mask-aware SuGaR workflow."

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "=========================================================="
echo "SuGaR Mesh Reconstruction Configuration"
echo "=========================================================="
if [[ "$AUTOPILOT" == "true" ]]; then
    REGULARIZATION="dn_consistency"
    REFINEMENT_TIME="short"
    echo "Autopilot aktiv: Regularisierung=dn_consistency, Refinement-Dauer=short (2000 Iterationen)."
else
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
echo " - Regularization Type: $REGULARIZATION"
echo " - Refinement Time: $REFINEMENT_TIME"
echo " - Vanilla 3DGS Checkpoint Iteration: $ITERATIONS"
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

echo "=== Pipeline (STS to Georeferencing) Completed Successfully. Final outputs saved in data/08_gis/ ==="
