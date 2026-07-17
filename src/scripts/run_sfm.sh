#!/bin/bash
set -e

echo "=== Running COLMAP SfM ==="
WORKSPACE_PATH="/data/04_sfm"
IMAGE_PATH="/data/02_frames"

mkdir -p $WORKSPACE_PATH

echo "1. Feature extraction..."
colmap feature_extractor \
    --database_path $WORKSPACE_PATH/database.db \
    --image_path $IMAGE_PATH \
    --ImageReader.camera_model SIMPLE_PINHOLE \
    --ImageReader.single_camera 1 \
    --SiftExtraction.max_num_features 16384 \
    --SiftExtraction.peak_threshold 0.003

echo "2. Feature matching (Sequential)..."
colmap sequential_matcher \
    --database_path $WORKSPACE_PATH/database.db \
    --SequentialMatching.overlap 20 \
    --FeatureMatching.guided_matching 1

echo "3. Mapper..."
mkdir -p $WORKSPACE_PATH/sparse
colmap mapper \
    --database_path $WORKSPACE_PATH/database.db \
    --image_path $IMAGE_PATH \
    --output_path $WORKSPACE_PATH/sparse \
    --Mapper.abs_pose_min_num_inliers 15 \
    --Mapper.min_num_matches 10

echo "4. Export the largest reconstructed point cloud to PLY..."
LARGEST_DIR=""
MAX_SIZE=0

# Find the numeric sub-directory under sparse/ with the largest points3D.bin or points3D.txt
for dir in "$WORKSPACE_PATH"/sparse/*; do
    if [ -d "$dir" ] && [[ "$(basename "$dir")" =~ ^[0-9]+$ ]]; then
        bin_file="$dir/points3D.bin"
        txt_file="$dir/points3D.txt"
        size=0
        if [ -f "$bin_file" ]; then
            size=$(stat -c%s "$bin_file" 2>/dev/null || stat -f%z "$bin_file" 2>/dev/null || echo 0)
        elif [ -f "$txt_file" ]; then
            size=$(stat -c%s "$txt_file" 2>/dev/null || stat -f%z "$txt_file" 2>/dev/null || echo 0)
        fi
        if (( size > MAX_SIZE )); then
            MAX_SIZE=$size
            LARGEST_DIR="$dir"
        fi
    fi
done

if [ -n "$LARGEST_DIR" ]; then
    echo "Exporting identified largest sub-model: $LARGEST_DIR ($MAX_SIZE bytes)"
    colmap model_converter \
        --input_path "$LARGEST_DIR" \
        --output_path $WORKSPACE_PATH/points3D.ply \
        --output_type PLY
elif [ -d "$WORKSPACE_PATH/sparse" ]; then
    echo "No custom sub-models found. Fallback to base sparse directory..."
    colmap model_converter \
        --input_path $WORKSPACE_PATH/sparse \
        --output_path $WORKSPACE_PATH/points3D.ply \
        --output_type PLY
else
    echo "Warning: No sparse model folders found."
fi

echo "COLMAP SfM completed."