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

echo "4. Export point cloud to PLY..."
if [ -d "$WORKSPACE_PATH/sparse/0" ]; then
    colmap model_converter \
        --input_path $WORKSPACE_PATH/sparse/0 \
        --output_path $WORKSPACE_PATH/points3D.ply \
        --output_type PLY
else
    colmap model_converter \
        --input_path $WORKSPACE_PATH/sparse \
        --output_path $WORKSPACE_PATH/points3D.ply \
        --output_type PLY
fi

echo "COLMAP SfM completed."