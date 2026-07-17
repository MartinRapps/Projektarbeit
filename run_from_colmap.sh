#!/bin/bash
set -e

echo "=== Starting Scan-to-BIM Reconstruction Pipeline FROM COLMAP ONWARDS ==="

# Autopilot Prompt configuration directly at the beginning
read -p "Moechten Sie die Pipeline im Autopilot-Modus ausfuehren? (Alle Standardvorgaben automatisch waehlen) (y/n) [Default: n]: " USER_AUTOPILOT
if [[ "$USER_AUTOPILOT" =~ ^[Yy]$ ]]; then
    AUTOPILOT="true"
    echo "Autopilot-Modus AKTIVIERT. Interaktive Abfragen werden mit Standardwerten beantwortet."
else
    AUTOPILOT="false"
fi

# Step 2: SfM (COLMAP camera poses & sparse point cloud)
echo "[Step 2/5] Running COLMAP Structure from Motion..."
docker compose run --rm colmap-sfm /app/src/scripts/run_sfm.sh

echo "=========================================================="
echo "BREAKPOINT: Please open the sparse point cloud in CloudCompare"
echo "on the host system. Pick the GCP coordinate points, compute"
echo "the 4x4 transformation matrix, and save it in data/04_sfm/matrix.txt"
echo "=========================================================="
read -p "Once you have saved the transformation matrix, press [Enter] to continue..."

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

# Step 3.5: Preserve the full STS cloud and prepare the geometry-oriented
# object input for mask-aware SuGaR without replacing point_cloud.ply.
echo "[Step 3.5/5] Preparing the standard SuGaR geometry input..."
docker compose run --rm sts-training python3 -c "import os, shutil; base='/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'; src=f'{base}/point_cloud.ply'; dst=f'{base}/point_cloud_full_scene.ply'; os.path.exists(src) or (_ for _ in ()).throw(FileNotFoundError(src)); shutil.copy2(src, dst)"
FILTER_MIN_OPACITY="${FILTER_MIN_OPACITY:-0.01}"
FILTER_BLACK_THRESHOLD="${FILTER_BLACK_THRESHOLD:-0.08}"
SUGAR_INPUT_ALPHA="${SUGAR_INPUT_ALPHA:-0.999999}"
ITERATIONS="$ITERATIONS" \
FILTER_MIN_OPACITY="$FILTER_MIN_OPACITY" \
FILTER_BLACK_THRESHOLD="$FILTER_BLACK_THRESHOLD" \
SUGAR_INPUT_ALPHA="$SUGAR_INPUT_ALPHA" \
./prepare_sugar_input.sh

REGULARIZATION="${REGULARIZATION:-dn_consistency}"
REFINEMENT_TIME="${REFINEMENT_TIME:-medium}"
MESH_VERTICES="${MESH_VERTICES:-200000}"
SURFACE_SAMPLE_COUNT="${SURFACE_SAMPLE_COUNT:-5000000}"
MASK_LEVEL="${MASK_LEVEL:-default}"
MASK_DILATION_PX="${MASK_DILATION_PX:-0}"
NORMAL_MASK_LEVEL="${NORMAL_MASK_LEVEL:-default}"
TEXTURE_MASK_LEVEL="${TEXTURE_MASK_LEVEL:-default}"
TEXTURE_MASK_DILATION_PX="${TEXTURE_MASK_DILATION_PX:-0}"
STOP_AFTER_COARSE_MESH="${STOP_AFTER_COARSE_MESH:-0}"
RUN_CONSENSUS_CROP="${RUN_CONSENSUS_CROP:-0}"
if [[ "$REGULARIZATION" == "dn_consistency" ]]; then
    COARSE_ITERATIONS="${COARSE_ITERATIONS:-9001}"
else
    COARSE_ITERATIONS=""
fi
SUGAR_RUN_TAG="${SUGAR_RUN_TAG:-colmap_i${ITERATIONS}_${REGULARIZATION}_${REFINEMENT_TIME}}"
SUGAR_MESH_EXPORT_NAME="${SUGAR_MESH_EXPORT_NAME:-$SUGAR_RUN_TAG}"

# Step 4: Run the local mask-aware SuGaR route.
echo "[Step 4/5] Running mask-aware SuGaR (Coarse Training -> Mesh Extraction -> Refinement)..."
MASKED_SUGAR_INTERACTIVE=0 \
ITERATIONS="$ITERATIONS" \
REGULARIZATION="$REGULARIZATION" \
COARSE_ITERATIONS="$COARSE_ITERATIONS" \
REFINEMENT_TIME="$REFINEMENT_TIME" \
MESH_VERTICES="$MESH_VERTICES" \
SURFACE_SAMPLE_COUNT="$SURFACE_SAMPLE_COUNT" \
MASK_LEVEL="$MASK_LEVEL" \
MASK_DILATION_PX="$MASK_DILATION_PX" \
NORMAL_MASK_LEVEL="$NORMAL_MASK_LEVEL" \
TEXTURE_MASK_LEVEL="$TEXTURE_MASK_LEVEL" \
TEXTURE_MASK_DILATION_PX="$TEXTURE_MASK_DILATION_PX" \
STOP_AFTER_COARSE_MESH="$STOP_AFTER_COARSE_MESH" \
RUN_CONSENSUS_CROP="$RUN_CONSENSUS_CROP" \
SUGAR_RUN_TAG="$SUGAR_RUN_TAG" \
SUGAR_MESH_EXPORT_NAME="$SUGAR_MESH_EXPORT_NAME" \
FILTERED_PLY="data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_filtered_opacity999999.ply" \
./run_masked_sugar.sh

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm -e INPUT_MESH="/data/06_mesh/${SUGAR_MESH_EXPORT_NAME}/refined.obj" post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline (COLMAP to Georeferencing) Completed Successfully. Final outputs saved in data/08_gis/ ==="
