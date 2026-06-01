#!/bin/bash
set -e

echo "=== Starting Scan-to-BIM Reconstruction Pipeline ==="

# Step 0: GCP Coordinate Preparation (Relative Coordinates)
echo "[Step 0/5] Preparing relative GCP coordinates..."
docker compose run --rm sam3-preprocess python3 /app/src/python/prepare_gcp.py

# Load environment variables if .env exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# HuggingFace Token Check for SAM 3.1
if [ -z "$HF_TOKEN" ]; then
    echo "=========================================================="
    echo "HINWEIS: SAM 3.1 ist ein geschütztes (gated) Modell auf HuggingFace."
    echo "Dein Token wird sicher in der .env-Datei gespeichert."
    echo "=========================================================="
    read -p "Bitte HuggingFace Token eingeben (oder Enter drücken, falls bereits gespeichert): " INPUT_TOKEN
    if [ ! -z "$INPUT_TOKEN" ]; then
        echo "HF_TOKEN=$INPUT_TOKEN" >> .env
        export HF_TOKEN=$INPUT_TOKEN
        echo "Token erfolgreich in .env gespeichert!"
    fi
fi

read -p "Geben Sie den Begriff ein, der maskiert werden soll (z.B. 'cable', 'pipe'): " TEXT_PROMPT

# Step 1: Pre-processing (SAM 3 Tracking)
echo "[Step 1/5] Extracting frames and generating SAM 3 masks for: $TEXT_PROMPT ..."
docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks.py --prompt "$TEXT_PROMPT"

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
echo "[Step 3/5] Starting Segment-then-Splat (STS) Object Training..."
docker compose run --rm sts-training python3 train.py --eval --iterations 40000

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "[Step 4/5] Running SuGaR Mesh Reconstruction..."
docker compose run --rm sugar-meshing python3 extract_mesh.py --regularization dn_consistency

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline Completed Successfully. Final outputs saved in data/08_gis/ ==="
