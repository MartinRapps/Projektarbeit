#!/usr/bin/env bash
set -euo pipefail

# Object-only SuGaR pipeline. It keeps the original STS checkpoint untouched,
# stages a private checkpoint with the high-opacity geometry input, trains the
# local mask-aware SuGaR fork, and exports a compact refined model separately.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# A plain terminal invocation is guided. Reproducible commands that provide at
# least one configuration variable keep the previous non-interactive behavior.
CONFIGURATION_WAS_PROVIDED=0
for config_variable in \
        ITERATIONS REGULARIZATION REFINEMENT_TIME MASK_LEVEL NORMAL_MASK_LEVEL \
        TEXTURE_MASK_LEVEL MASK_DILATION_PX TEXTURE_MASK_DILATION_PX \
        MESH_VERTICES SURFACE_SAMPLE_COUNT COARSE_ITERATIONS SUGAR_RUN_TAG \
        STOP_AFTER_COARSE_MESH RUN_CONSENSUS_CROP FILTERED_PLY \
        SUGAR_MESH_EXPORT_NAME FILTER_MIN_OPACITY FILTER_BLACK_THRESHOLD \
        SUGAR_INPUT_ALPHA; do
        if [[ -v $config_variable ]]; then
                CONFIGURATION_WAS_PROVIDED=1
                break
        fi
done

INTERACTIVE_SETTING="${MASKED_SUGAR_INTERACTIVE:-auto}"
case "$INTERACTIVE_SETTING" in
        auto)
                if [[ -t 0 && "$CONFIGURATION_WAS_PROVIDED" == "0" ]]; then
                        INTERACTIVE=1
                else
                        INTERACTIVE=0
                fi
                ;;
        1|true|TRUE|yes|YES)
                INTERACTIVE=1
                ;;
        0|false|FALSE|no|NO)
                INTERACTIVE=0
                ;;
        *)
                echo "Error: MASKED_SUGAR_INTERACTIVE must be auto, 0, or 1." >&2
                exit 2
                ;;
esac

explain_checkpoint_iteration() {
        cat <<'EOF'

    ITERATIONS selects the existing STS checkpoint and geometry input PLY.
    It must match point_cloud_filtered_opacity999999.ply and cameras.json from
    the same STS run. The source point_cloud_filtered.ply is retained separately
    with its original opacity values.
    The current object experiment uses 7000.
EOF
}

explain_regularization() {
        cat <<'EOF'

    dn_consistency : Current object route. Uses masked RGB supervision plus
                                     density/SDF terms and a depth-normal consistency term.
    density        : Density/SDF regularization without the DN-specific schedule.
    sdf            : Alternative upstream regularization route.
    Keep dn_consistency for comparisons with the current reference run.
EOF
}

explain_coarse_iterations() {
        cat <<'EOF'

    COARSE_ITERATIONS is the final counter of the local dn_consistency trainer,
    not simply an independent number of new optimizer updates. Because the model
    starts from the STS checkpoint, its counter begins at 6999.

    The current local schedule is:
        7000-9000 : masked RGB optimization; entropy regularization is active.
        >9000     : depth-normal consistency and SDF-related geometric terms start.

    9001 is the current geometry-oriented standard. It retains the STS-derived
    surface support and adds the first DN/SDF update after the hard pruning
    boundary. Longer runs remain separate comparisons because they can improve
    thin temples while also consolidating contact-region artifacts.
EOF
}

explain_mesh_vertices() {
        cat <<'EOF'

    MESH_VERTICES is the target after Poisson reconstruction and mesh decimation.
    It controls the resolution of the coarse mesh handed to refinement. It does
    not reduce the preceding camera-based surface sampling or Poisson solve by
    the same factor. 25k-100k is useful for a visual screening mesh; 1,000,000
    is the current detailed reference. Do not compare their fine geometry as if
    they had identical resolution.
EOF
}

explain_surface_sample_count() {
        cat <<'EOF'

    SURFACE_SAMPLE_COUNT is the total target number of Gaussian surface samples
    collected across the training cameras before Poisson reconstruction. With
    --eval=True, the current 699 registered views become 611 training views and
    88 held-out evaluation views. The current screening target is 5,000,000;
    the upstream detailed reference is 10,000,000. This is a direct
    runtime/quality trade-off in mesh extraction: fewer samples can accelerate
    a screening run but can make thin structures or artifacts less reliable.
EOF
}

explain_refinement_time() {
        cat <<'EOF'

    short  : 2000 refinement updates; use for a pipeline or runtime screen.
    medium : 7000 refinement updates; current reference setting.
    long   : 15000 refinement updates.

    Refinement is bound to the extracted coarse mesh. It can improve the surface
    appearance but cannot prove that an already incorrect coarse sheet was valid.
EOF
}

explain_stop_after_coarse_mesh() {
    cat <<'EOF'

    STOP_AFTER_COARSE_MESH=1 runs Coarse optimization and Coarse mesh extraction,
    then exits before refinement, UV texture baking, and semantic crop. It is the
    focused mode for a full-training RGB-dilation test when only the first
    visible artifact stage matters.

    STOP_AFTER_COARSE_MESH=0 is the complete pipeline. It preserves the saved
    Coarse PLY, then uses that PLY as input for refinement and writes refined
    outputs separately. A stopped run is intentionally not resumed by changing
    this value on the same tag; use a fresh tag for a complete comparison run.
EOF
}

explain_mask_levels() {
        cat <<'EOF'

    default : original SAM foreground mask.
    middle  : one 5x5 erosion; conservative inner object region.
    small   : two 5x5 erosions; strict inner core.

    RGB uses MASK_LEVEL in coarse and refinement. DN uses NORMAL_MASK_LEVEL only
    in coarse training and has no additional dilation. UV uses TEXTURE_MASK_LEVEL
    only while collecting colors for the final texture atlas.
EOF
}

explain_mask_dilation() {
        cat <<'EOF'

    RGB dilation expands the selected RGB mask before masked L1+DSSIM supervision
    in coarse training and refinement. Its standard value is 0 pixels. It can include
    uncertain silhouette/background pixels, so it remains a testable cause of
    geometry changes. Set it to 0 for the controlled no-dilation experiment.

    UV dilation is separate. It expands only the pixels accepted while baking
    colors into the texture atlas; it is not a geometry loss and cannot change
    the coarse mesh or refined PLY. Set it to 0 alongside RGB dilation so the
    rendered appearance does not obscure a geometric comparison.
EOF
}

export_refined_model() {
    local source_mtl
    local texture_reference
    local source_texture

    REFINED_PLY="$(find "$OUTPUT_HOST_DIR/refined_ply" -type f -name '*.ply' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
    FINAL_MESH="$(find "$OUTPUT_HOST_DIR/refined_mesh" -type f -name '*.obj' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
    if [[ -z "$REFINED_PLY" || ! -f "$REFINED_PLY" || -z "$FINAL_MESH" || ! -f "$FINAL_MESH" ]]; then
        echo "Error: The mask-aware SuGaR run completed without both refined PLY and textured OBJ outputs." >&2
        exit 2
    fi

    MESH_EXPORT_DIR="data/06_mesh/$MESH_EXPORT_NAME"
    if [[ -e "$MESH_EXPORT_DIR" ]]; then
        if [[ "${REPLACE:-0}" != "1" ]]; then
            echo "Error: Short refined-model export already exists: $MESH_EXPORT_DIR" >&2
            echo "Set SUGAR_MESH_EXPORT_NAME to a new name, or set REPLACE=1 to replace it deliberately." >&2
            exit 2
        fi
        rm -rf "$MESH_EXPORT_DIR"
    fi
    mkdir -p "$MESH_EXPORT_DIR"

    EXPORTED_REFINED_PLY="$MESH_EXPORT_DIR/refined.ply"
    EXPORTED_OBJ="$MESH_EXPORT_DIR/refined.obj"
    cp "$REFINED_PLY" "$EXPORTED_REFINED_PLY"
    cp "$FINAL_MESH" "$EXPORTED_OBJ"

    source_mtl="${FINAL_MESH%.*}.mtl"
    if [[ -f "$source_mtl" ]]; then
        cp "$source_mtl" "$MESH_EXPORT_DIR/refined.mtl"
        sed -i -E 's|^[[:space:]]*mtllib[[:space:]].*$|mtllib refined.mtl|' "$EXPORTED_OBJ"
        texture_reference="$(awk '$1 == "map_Kd" { print $2; exit }' "$source_mtl")"
        source_texture="$(dirname "$source_mtl")/$texture_reference"
        if [[ -n "$texture_reference" && -f "$source_texture" ]]; then
            cp "$source_texture" "$MESH_EXPORT_DIR/texture.png"
            sed -i -E 's|^[[:space:]]*map_Kd[[:space:]].*$|map_Kd texture.png|' "$MESH_EXPORT_DIR/refined.mtl"
        fi
    fi
}

explain_consensus_crop() {
        cat <<'EOF'

    RUN_CONSENSUS_CROP=1 runs a post-export semantic mesh crop. It is not part of
    coarse training, refinement, or texture baking. Set it to 0 for diagnostics
    so the exported mesh is inspected before any crop removes faces.
EOF
}

explain_run_tag() {
        cat <<'EOF'

    SUGAR_RUN_TAG names both a private staged input checkpoint and an output
    directory. A new tag preserves every prior run. The runner refuses a reused
    tag unless REPLACE=1 is explicitly set; do not use REPLACE=1 for comparisons.
EOF
}

ask_value() {
        local variable_name="$1"
        local prompt="$2"
        local default_value="$3"
        local explain_function="$4"
        local answer

        while true; do
                read -r -p "$prompt [Default: $default_value]: " answer
                if [[ "${answer,,}" == "explain" ]]; then
                        "$explain_function"
                        continue
                fi
                printf -v "$variable_name" '%s' "${answer:-$default_value}"
                return
        done
}

ITERATIONS="${ITERATIONS:-7000}"
REGULARIZATION="${REGULARIZATION:-dn_consistency}"
REFINEMENT_TIME="${REFINEMENT_TIME:-medium}"
MASK_LEVEL="${MASK_LEVEL:-default}"
NORMAL_MASK_LEVEL="${NORMAL_MASK_LEVEL:-default}"
TEXTURE_MASK_LEVEL="${TEXTURE_MASK_LEVEL:-default}"
MASK_DILATION_PX="${MASK_DILATION_PX:-0}"
TEXTURE_MASK_DILATION_PX="${TEXTURE_MASK_DILATION_PX:-0}"
MASK_SSIM_WINDOW="${MASK_SSIM_WINDOW:-11}"
MESH_VERTICES="${MESH_VERTICES:-200000}"
SURFACE_SAMPLE_COUNT="${SURFACE_SAMPLE_COUNT:-5000000}"
COARSE_ITERATIONS="${COARSE_ITERATIONS:-}"
if [[ "$REGULARIZATION" == "dn_consistency" && -z "$COARSE_ITERATIONS" ]]; then
    COARSE_ITERATIONS=9001
fi
STOP_AFTER_COARSE_MESH="${STOP_AFTER_COARSE_MESH:-0}"
RUN_CONSENSUS_CROP="${RUN_CONSENSUS_CROP:-0}"
RUN_TAG="${SUGAR_RUN_TAG:-}"

if [[ "$INTERACTIVE" == "1" ]]; then
    echo "=== Guided mask-aware SuGaR configuration ==="
    echo "Enter EXPLAIN at any prompt for the parameter rationale."
    ask_value ITERATIONS \
        "STS checkpoint iteration (or EXPLAIN)" "$ITERATIONS" explain_checkpoint_iteration
    ask_value REGULARIZATION \
        "Regularization (sdf/density/dn_consistency, or EXPLAIN)" "$REGULARIZATION" explain_regularization
    if [[ "$REGULARIZATION" == "dn_consistency" ]]; then
        ask_value COARSE_ITERATIONS \
            "Coarse final iteration counter (or EXPLAIN)" "${COARSE_ITERATIONS:-15000}" explain_coarse_iterations
    else
        COARSE_ITERATIONS=""
    fi
    ask_value MESH_VERTICES \
        "Coarse mesh vertex target (or EXPLAIN)" "$MESH_VERTICES" explain_mesh_vertices
    ask_value SURFACE_SAMPLE_COUNT \
        "Total camera surface samples (or EXPLAIN)" "$SURFACE_SAMPLE_COUNT" explain_surface_sample_count
    ask_value STOP_AFTER_COARSE_MESH \
        "Stop after Coarse mesh? 1=yes, 0=no (or EXPLAIN)" "$STOP_AFTER_COARSE_MESH" explain_stop_after_coarse_mesh
    ask_value REFINEMENT_TIME \
        "Refinement time (short/medium/long, or EXPLAIN)" "$REFINEMENT_TIME" explain_refinement_time
    ask_value MASK_LEVEL \
        "RGB mask level (default/middle/small, or EXPLAIN)" "$MASK_LEVEL" explain_mask_levels
    ask_value MASK_DILATION_PX \
        "RGB mask dilation in pixels (or EXPLAIN)" "$MASK_DILATION_PX" explain_mask_dilation
    ask_value NORMAL_MASK_LEVEL \
        "DN mask level (default/middle/small, or EXPLAIN)" "$NORMAL_MASK_LEVEL" explain_mask_levels
    ask_value TEXTURE_MASK_LEVEL \
        "UV mask level (default/middle/small, or EXPLAIN)" "$TEXTURE_MASK_LEVEL" explain_mask_levels
    ask_value TEXTURE_MASK_DILATION_PX \
        "UV mask dilation in pixels (or EXPLAIN)" "$TEXTURE_MASK_DILATION_PX" explain_mask_dilation
    ask_value RUN_CONSENSUS_CROP \
        "Run final semantic crop? 1=yes, 0=no (or EXPLAIN)" "$RUN_CONSENSUS_CROP" explain_consensus_crop
    ask_value RUN_TAG \
        "New run tag (or EXPLAIN)" "${RUN_TAG:-masked_${ITERATIONS}_${REGULARIZATION}_${REFINEMENT_TIME}}" explain_run_tag
fi

RUN_TAG="${RUN_TAG:-sugar_i${ITERATIONS}_c${COARSE_ITERATIONS:-default}_v${MESH_VERTICES}}"

case "$REGULARIZATION" in
    sdf|density|dn_consistency)
        ;;
    *)
        echo "Error: REGULARIZATION must be sdf, density, or dn_consistency." >&2
        exit 2
        ;;
esac
if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: ITERATIONS must be a positive integer." >&2
    exit 2
fi
case "$REFINEMENT_TIME" in
    short|medium|long)
        ;;
    *)
        echo "Error: REFINEMENT_TIME must be short, medium, or long." >&2
        exit 2
        ;;
esac
for mask_level_variable in MASK_LEVEL NORMAL_MASK_LEVEL TEXTURE_MASK_LEVEL; do
    case "${!mask_level_variable}" in
        default|middle|small)
            ;;
        *)
            echo "Error: $mask_level_variable must be default, middle, or small." >&2
            exit 2
            ;;
    esac
done
for nonnegative_integer_variable in MASK_DILATION_PX TEXTURE_MASK_DILATION_PX; do
    if ! [[ "${!nonnegative_integer_variable}" =~ ^[0-9]+$ ]]; then
        echo "Error: $nonnegative_integer_variable must be a non-negative integer." >&2
        exit 2
    fi
done
if ! [[ "$MASK_SSIM_WINDOW" =~ ^[1-9][0-9]*$ ]] || (( MASK_SSIM_WINDOW < 3 || MASK_SSIM_WINDOW % 2 == 0 )); then
    echo "Error: MASK_SSIM_WINDOW must be an odd integer of at least 3." >&2
    exit 2
fi
if ! [[ "$MESH_VERTICES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MESH_VERTICES must be a positive integer." >&2
    exit 2
fi
if ! [[ "$SURFACE_SAMPLE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: SURFACE_SAMPLE_COUNT must be a positive integer." >&2
    exit 2
fi
if [[ -n "$COARSE_ITERATIONS" && ! "$COARSE_ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: COARSE_ITERATIONS must be a positive integer when supplied." >&2
    exit 2
fi
if [[ -n "$COARSE_ITERATIONS" && "$REGULARIZATION" != "dn_consistency" ]]; then
    echo "Error: COARSE_ITERATIONS is currently supported only with REGULARIZATION=dn_consistency." >&2
    exit 2
fi
if [[ -n "$COARSE_ITERATIONS" && "$COARSE_ITERATIONS" -le 9000 ]]; then
    echo "Error: dn_consistency starts after coarse iteration 9000; COARSE_ITERATIONS must be at least 9001." >&2
    exit 2
fi
if [[ -n "$COARSE_ITERATIONS" && "$COARSE_ITERATIONS" -le 10000 ]]; then
    echo "Notice: This target has at most 1000 DN/SDF-phase updates; c9001 is the selected geometry-first standard." >&2
fi
case "$RUN_CONSENSUS_CROP" in
    0|1)
        ;;
    *)
        echo "Error: RUN_CONSENSUS_CROP must be 0 or 1." >&2
        exit 2
        ;;
esac
case "$STOP_AFTER_COARSE_MESH" in
    0|1)
        ;;
    *)
        echo "Error: STOP_AFTER_COARSE_MESH must be 0 or 1." >&2
        exit 2
        ;;
esac
if ! [[ "$RUN_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: SUGAR_RUN_TAG may contain only letters, digits, dots, underscores, and hyphens." >&2
    exit 2
fi

if [[ "$REGULARIZATION" == "dn_consistency" ]]; then
    COARSE_TARGET="$COARSE_ITERATIONS"
else
    COARSE_TARGET="default"
fi
MESH_EXPORT_NAME="${SUGAR_MESH_EXPORT_NAME:-sugar_i${ITERATIONS}_c${COARSE_TARGET}_v${MESH_VERTICES}_${MASK_LEVEL}_dn${NORMAL_MASK_LEVEL}}"
if ! [[ "$MESH_EXPORT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: SUGAR_MESH_EXPORT_NAME may contain only letters, digits, dots, underscores, and hyphens." >&2
    exit 2
fi

DEFAULT_FILTERED_PLY="data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_filtered_opacity999999.ply"
FILTERED_PLY="${FILTERED_PLY:-$DEFAULT_FILTERED_PLY}"
FILTER_MIN_OPACITY="${FILTER_MIN_OPACITY:-0.01}"
FILTER_BLACK_THRESHOLD="${FILTER_BLACK_THRESHOLD:-0.08}"
SUGAR_INPUT_ALPHA="${SUGAR_INPUT_ALPHA:-0.999999}"
CAMERAS_JSON="${CAMERAS_JSON:-data/05_3dgs/output/cameras.json}"
MASKS_DIR="${MASKS_DIR:-data/03_masks}"
CHECKPOINT_HOST_DIR="data/05_3dgs/masked_sugar_input/${RUN_TAG}"
CHECKPOINT_CONTAINER_DIR="/data/05_3dgs/masked_sugar_input/${RUN_TAG}/"
OUTPUT_HOST_DIR="data/sugar_output/${RUN_TAG}"
OUTPUT_CONTAINER_ROOT="./output/${RUN_TAG}"

if [[ ! -f "$FILTERED_PLY" && "$FILTERED_PLY" == "$DEFAULT_FILTERED_PLY" ]]; then
    echo "Standard high-opacity SuGaR input is missing; preparing it from the STS checkpoint..."
    ITERATIONS="$ITERATIONS" \
    FILTER_MIN_OPACITY="$FILTER_MIN_OPACITY" \
    FILTER_BLACK_THRESHOLD="$FILTER_BLACK_THRESHOLD" \
    SUGAR_INPUT_ALPHA="$SUGAR_INPUT_ALPHA" \
    ./prepare_sugar_input.sh
fi
if [[ ! -f "$FILTERED_PLY" ]]; then
    echo "Error: No filtered object point cloud was found:" >&2
    echo "  $FILTERED_PLY" >&2
    echo "Run ./prepare_sugar_input.sh first, or pass FILTERED_PLY explicitly." >&2
    exit 2
fi
if [[ ! -f "$CAMERAS_JSON" || ! -d "$MASKS_DIR" ]]; then
    echo "Error: cameras.json or the source masks are missing." >&2
    exit 2
fi

if [[ ( -e "$OUTPUT_HOST_DIR" || -e "$CHECKPOINT_HOST_DIR" ) && "${REPLACE:-0}" != "1" ]]; then
    echo "Error: Output or private staged checkpoint already exists for tag: $RUN_TAG" >&2
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
echo "Mesh vertices  : $MESH_VERTICES"
echo "Surface samples: $SURFACE_SAMPLE_COUNT"
echo "Stop after Coarse mesh: $STOP_AFTER_COARSE_MESH"
echo "Short refined-model export: data/06_mesh/$MESH_EXPORT_NAME"
if [[ "$REGULARIZATION" == "dn_consistency" ]]; then
    echo "Coarse target counter: $COARSE_TARGET (starts at 6999; about $((COARSE_TARGET - 6999)) new updates)"
    echo "DN/SDF-phase updates: about $((COARSE_TARGET - 9000)) after activation above 9000"
else
    echo "Coarse iterations: implementation default for $REGULARIZATION"
fi
echo "RGB / DN / UV masks: $MASK_LEVEL / $NORMAL_MASK_LEVEL / $TEXTURE_MASK_LEVEL"

# SuGaR can only load point_cloud.ply from a checkpoint root. Stage a private
# copy rather than replacing the original STS checkpoint or its full-scene PLY.
mkdir -p "$CHECKPOINT_HOST_DIR/point_cloud/iteration_${ITERATIONS}"
cp "$CAMERAS_JSON" "$CHECKPOINT_HOST_DIR/cameras.json"
if [[ -f data/05_3dgs/output/cfg_args ]]; then
    cp data/05_3dgs/output/cfg_args "$CHECKPOINT_HOST_DIR/cfg_args"
fi
cp "$FILTERED_PLY" "$CHECKPOINT_HOST_DIR/point_cloud/iteration_${ITERATIONS}/point_cloud.ply"

COARSE_ARGUMENTS=()
if [[ -n "$COARSE_ITERATIONS" ]]; then
    COARSE_ARGUMENTS+=(--coarse-iterations "$COARSE_ITERATIONS")
fi

docker compose -f docker-compose.yml -f docker-compose.sugar-dev.yml run --rm sugar-meshing \
    python3 train.py \
    -s /data/05_3dgs \
    -c "$CHECKPOINT_CONTAINER_DIR" \
    -i "$ITERATIONS" \
    -r "$REGULARIZATION" \
    -v "$MESH_VERTICES" \
    --surface-sample-count "$SURFACE_SAMPLE_COUNT" \
    --stop-after-coarse-mesh "$STOP_AFTER_COARSE_MESH" \
    "${COARSE_ARGUMENTS[@]}" \
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

if [[ "$STOP_AFTER_COARSE_MESH" == "1" ]]; then
    echo "Mask-aware SuGaR stopped after Coarse mesh. Refinement, UV texture, and consensus crop were intentionally skipped."
    exit 0
fi

export_refined_model
echo "Refined PLY export: $EXPORTED_REFINED_PLY"
echo "Refined OBJ export: $EXPORTED_OBJ"

if [[ "$RUN_CONSENSUS_CROP" != "1" ]]; then
    echo "Mask-aware SuGaR completed. Consensus crop intentionally skipped."
    exit 0
fi

CROPPED_MESH="$MESH_EXPORT_DIR/refined_multiview.obj"
echo "Starting final multi-view consensus crop..."
MESH_PATH="$EXPORTED_OBJ" \
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
echo "Final refined PLY: $EXPORTED_REFINED_PLY"
echo "Final refined OBJ: $EXPORTED_OBJ"
echo "Final cropped mesh: $CROPPED_MESH"