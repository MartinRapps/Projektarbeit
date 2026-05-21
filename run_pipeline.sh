#!/bin/bash
set -e

echo "=== Starting Scan-to-BIM Reconstruction Pipeline ==="

# Step 1: Pre-processing (SAM 3 Tracking)
echo "[Step 1/5] Extracting frames and generating SAM 3 masks..."
docker compose run --rm sam3-preprocess python3 /app/scripts/extract_masks.py

# Step 2: SfM (COLMAP camera poses & sparse point cloud)
echo "[Step 2/5] Running COLMAP Structure from Motion..."
docker compose run --rm colmap-sfm /app/scripts/run_sfm.sh

echo "=========================================================="
echo "BREAKPOINT: Please open the sparse point cloud in CloudCompare"
echo "on the host system. Pick the GCP coordinate points, compute"
echo "the 4x4 transformation matrix, and save it in data/04_sfm/matrix.txt"
echo "=========================================================="
read -p "Once you have saved the transformation matrix, press [Enter] to continue..."

# Step 3: Object-Specific 3DGS (Segment-then-Splat STS)
echo "[Step 3/5] Starting Segment-then-Splat (STS) Object Training..."
docker compose run --rm sts-training python3 train.py --eval --iterations 40000

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "[Step 4/5] Running SuGaR Mesh Reconstruction..."
docker compose run --rm sugar-meshing python3 extract_mesh.py --regularization dn_consistency

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm post-processing /app/scripts/postprocess.sh

echo "=== Pipeline Completed Successfully. Final outputs saved in data/08_gis/ ==="
