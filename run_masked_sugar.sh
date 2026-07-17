#!/usr/bin/env bash
set -euo pipefail

# Object-only SuGaR pipeline. It keeps the original STS checkpoint untouched,
# stages a private checkpoint with the filtered point cloud, trains the local
# mask-aware SuGaR fork, bakes a mask-aware texture, then crops residual faces
# through multi-view semantic consensus.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

ITERATIONS="${ITERATIONS:-7000}"
REGULARIZATION="${REGULARIZATION:-dn_consistency}"
REFINEMENT_TIME="${REFINEMENT_TIME:-medium}"
MASK_LEVEL="${MASK_LEVEL:-default}"
NORMAL_MASK_LEVEL="${NORMAL_MASK_LEVEL:-middle}"
TEXTURE_MASK_LEVEL="${TEXTURE_MASK_LEVEL:-default}"
MASK_DILATION_PX="${MASK_DILATION_PX:-2}"
TEXTURE_MASK_DILATION_PX="${TEXTURE_MASK_DILATION_PX:-2}"
MASK_SSIM_WINDOW="${MASK_SSIM_WINDOW:-11}"
RUN_TAG="${SUGAR_RUN_TAG:-masked_${ITERATIONS}_${REGULARIZATION}_${REFINEMENT_TIME}}"

case "$REGULARIZATION" in
    sdf|density|dn_consistency)
        ;;
    *)
        echo "Error: REGULARIZATION must be sdf, density, or dn_consistency." >&2
        exit 2
        ;;
esac

FILTERED_PLY="${FILTERED_PLY:-data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_cable.ply}"
CAMERAS_JSON="${CAMERAS_JSON:-data/05_3dgs/output/cameras.json}"
MASKS_DIR="${MASKS_DIR:-data/03_masks}"
CHECKPOINT_HOST_DIR="data/05_3dgs/masked_sugar_input/${RUN_TAG}"
CHECKPOINT_CONTAINER_DIR="/data/05_3dgs/masked_sugar_input/${RUN_TAG}/"
OUTPUT_HOST_DIR="data/sugar_output/${RUN_TAG}"
OUTPUT_CONTAINER_ROOT="./output/${RUN_TAG}"

if [[ ! -f "$FILTERED_PLY" ]]; then
    echo "Error: No filtered object point cloud was found:" >&2
    echo "  $FILTERED_PLY" >&2
    echo "Run the STS filter first. The script intentionally refuses to use an unfiltered standard PLY." >&2
    exit 2
fi
if [[ ! -f "$CAMERAS_JSON" || ! -d "$MASKS_DIR" ]]; then
    echo "Error: cameras.json or the source masks are missing." >&2
    exit 2
fi

if [[ -e "$OUTPUT_HOST_DIR" && "${REPLACE:-0}" != "1" ]]; then
    echo "Error: Output directory already exists: $OUTPUT_HOST_DIR" >&2
    echo "Set SUGAR_RUN_TAG to a new value, or set REPLACE=1 to deliberately replace this run." >&2
    exit 2
fi
if [[ "${REPLACE:-0}" == "1" ]]; then
    rm -rf "$OUTPUT_HOST_DIR" "$CHECKPOINT_HOST_DIR"
fi

echo "=== Mask-aware SuGaR object reconstruction ==="
echo "Filtered input : $FILTERED_PLY"
echo "Source masks   : $MASKS_DIR"
echo "Run tag        : $RUN_TAG"
echo "Regularization : $REGULARIZATION"
echo "Refinement     : $REFINEMENT_TIME"
echo "RGB / DN / UV masks: $MASK_LEVEL / $NORMAL_MASK_LEVEL / $TEXTURE_MASK_LEVEL"

# SuGaR can only load point_cloud.ply from a checkpoint root. Stage a private
# copy rather than replacing the original STS checkpoint or its full-scene PLY.
mkdir -p "$CHECKPOINT_HOST_DIR/point_cloud/iteration_${ITERATIONS}"
cp "$CAMERAS_JSON" "$CHECKPOINT_HOST_DIR/cameras.json"
if [[ -f data/05_3dgs/output/cfg_args ]]; then
    cp data/05_3dgs/output/cfg_args "$CHECKPOINT_HOST_DIR/cfg_args"
fi
cp "$FILTERED_PLY" "$CHECKPOINT_HOST_DIR/point_cloud/iteration_${ITERATIONS}/point_cloud.ply"

docker compose -f docker-compose.yml -f docker-compose.sugar-dev.yml run --rm sugar-meshing \
    python3 train.py \
    -s /data/05_3dgs \
    -c "$CHECKPOINT_CONTAINER_DIR" \
    -i "$ITERATIONS" \
    -r "$REGULARIZATION" \
    --refinement_time "$REFINEMENT_TIME" \
    --eval True \
    --masks-dir /data/03_masks \
    --mask-level "$MASK_LEVEL" \
    --normal-mask-level "$NORMAL_MASK_LEVEL" \
    --mask-dilation-px "$MASK_DILATION_PX" \
    --texture-mask-level "$TEXTURE_MASK_LEVEL" \
    --texture-mask-dilation-px "$TEXTURE_MASK_DILATION_PX" \
    --mask-ssim-window "$MASK_SSIM_WINDOW" \
    --output-root "$OUTPUT_CONTAINER_ROOT"

if [[ "${RUN_CONSENSUS_CROP:-1}" != "1" ]]; then
    echo "Mask-aware SuGaR completed. Consensus crop intentionally skipped."
    exit 0
fi

FINAL_MESH="$(find "$OUTPUT_HOST_DIR/refined_mesh" -type f -name '*.obj' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
if [[ -z "$FINAL_MESH" || ! -f "$FINAL_MESH" ]]; then
    echo "Error: The mask-aware SuGaR run completed without a textured OBJ mesh." >&2
    exit 2
fi

FINAL_MESH_BASENAME="$(basename "${FINAL_MESH%.*}")"
CROPPED_MESH="data/06_mesh/${RUN_TAG}_${FINAL_MESH_BASENAME}_multiview.obj"
echo "Starting final multi-view consensus crop..."
MESH_PATH="$FINAL_MESH" \
OUTPUT_PATH="$CROPPED_MESH" \
MASK_LEVEL="$TEXTURE_MASK_LEVEL" \
MASK_DILATION_PX="$TEXTURE_MASK_DILATION_PX" \
RENDER_SCALE="${CROP_RENDER_SCALE:-0.25}" \
MIN_VISIBLE_VIEWS="${CROP_MIN_VISIBLE_VIEWS:-3}" \
MIN_VISIBLE_PIXELS="${CROP_MIN_VISIBLE_PIXELS:-2}" \
MIN_VIEW_MASK_FRACTION="${CROP_MIN_VIEW_MASK_FRACTION:-0.5}" \
MIN_SUPPORT_RATIO="${CROP_MIN_SUPPORT_RATIO:-0.6}" \
OVERWRITE="${REPLACE:-0}" \
./run_multiview_crop.sh

echo "=== Mask-aware SuGaR pipeline completed ==="
echo "Final cropped mesh: $CROPPED_MESH"