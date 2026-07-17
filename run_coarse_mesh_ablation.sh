#!/usr/bin/env bash
set -euo pipefail

# Re-extract a coarse mesh from an existing mask-aware SuGaR checkpoint. This
# deliberately skips coarse optimization, refinement, texture baking, and crop.
# Every ablation writes to a separate directory below its source run.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# A plain terminal invocation is guided. Commands with configuration variables
# remain non-interactive for reproducible ablations.
CONFIGURATION_WAS_PROVIDED=0
for config_variable in \
    ITERATIONS SUGAR_RUN_TAG SOURCE_RUN_TAG MESH_VERTICES SURFACE_SAMPLE_COUNT \
    SURFACE_LEVEL POISSON_DEPTH VERTICES_DENSITY_QUANTILE \
    PROJECT_MESH_ON_SURFACE_POINTS LOW_OPACITY_GAUSSIAN_THRESHOLD \
    COARSE_MESH_ABLATION_TAG COARSE_MODEL GPU; do
    if [[ -v $config_variable ]]; then
        CONFIGURATION_WAS_PROVIDED=1
        break
    fi
done

INTERACTIVE_SETTING="${COARSE_MESH_ABLATION_INTERACTIVE:-auto}"
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
        echo "Error: COARSE_MESH_ABLATION_INTERACTIVE must be auto, 0, or 1." >&2
        exit 2
        ;;
esac

explain_source_run() {
    cat <<'EOF'

  SOURCE_RUN_TAG identifies an existing completed mask-aware SuGaR run. This
  script loads its coarse .pt checkpoint and does not start coarse training,
  refinement, UV texture baking, or semantic cropping. SUGAR_RUN_TAG remains a
  backwards-compatible alias for SOURCE_RUN_TAG in non-interactive commands.
EOF
}

explain_mesh_vertices() {
    cat <<'EOF'

  MESH_VERTICES is the target after Poisson reconstruction and quadric
  decimation. This script outputs only a coarse PLY, not a refined mesh.
  Fewer vertices simplify the saved mesh but do not reduce the preceding
  camera-based surface sampling and Poisson solve proportionally.
EOF
}

explain_surface_sample_count() {
    cat <<'EOF'

  SURFACE_SAMPLE_COUNT is the total target number of surface samples collected
    across the training cameras before Poisson reconstruction. With --eval=True,
    the current source uses 611 training views while 88 of 699 registered views
    remain held out for evaluation. The reference uses 10,000,000. Lower values,
    such as 2,000,000, can accelerate a screening extraction but may create
    holes, aliasing, or unstable thin structures. Do not treat a reduced-sample
    result as a final-quality mesh.
EOF
}

explain_surface_level() {
    cat <<'EOF'

  SURFACE_LEVEL selects the Gaussian density/surface isolevel sampled before
  Poisson reconstruction. The reference is 0.3. Changing it shifts which
  rendered density contour becomes the input point cloud. Keep 0.3 initially;
  vary it only after isolating Poisson depth, density cleanup, and projection.
EOF
}

explain_poisson_depth() {
    cat <<'EOF'

  POISSON_DEPTH is the octree resolution of Open3D Poisson reconstruction.
  Higher values retain smaller features and generate a denser, slower mesh;
  they can also preserve small erroneous sheets. Lower values produce a
  coarser, smoother surface and can remove small artifacts, but may erase thin
  glasses parts. The reference uses 10; depth 8 is a diagnostic variant, not a
  guaranteed repair.
EOF
}

explain_density_quantile() {
    cat <<'EOF'

  VERTICES_DENSITY_QUANTILE removes the lowest-density Poisson vertices after
  reconstruction. 0.1 removes the bottom 10 percent, which is the reference.
  A higher value can remove sparsely supported sheets but can also remove real
  thin geometry. Change it only after observing a Poisson-depth result.
EOF
}

explain_projection() {
    cat <<'EOF'

  PROJECT_MESH_ON_SURFACE_POINTS=True moves each decimated mesh vertex to its
  nearest sampled Gaussian surface point. It restores detail after decimation,
  but it can also transfer local sampling noise. False keeps the raw Poisson
  vertex positions. This is a separate extraction test, not refinement.
EOF
}

explain_low_opacity_threshold() {
        cat <<'EOF'

    LOW_OPACITY_GAUSSIAN_THRESHOLD removes coarse-checkpoint Gaussians with a
    sigmoid opacity at or below this value before camera surface sampling. The
    reference is 0.5. A value of 0.0 retains every Gaussian with finite positive
    sigmoid opacity. This changes extraction only: it does not retrain or modify
    the source checkpoint.
EOF
}

explain_ablation_tag() {
    cat <<'EOF'

  COARSE_MESH_ABLATION_TAG names a new output directory below the source run.
  It must be unique. Existing ablation outputs are never overwritten, so use a
  tag that records the one variable being tested, for example depth8_v50000.
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
SOURCE_RUN_TAG="${SOURCE_RUN_TAG:-${SUGAR_RUN_TAG:-masked_7000_dn_consistency_medium}}"
MESH_VERTICES="${MESH_VERTICES:-50000}"
SURFACE_SAMPLE_COUNT="${SURFACE_SAMPLE_COUNT:-10000000}"
SURFACE_LEVEL="${SURFACE_LEVEL:-0.3}"
POISSON_DEPTH="${POISSON_DEPTH:-10}"
VERTICES_DENSITY_QUANTILE="${VERTICES_DENSITY_QUANTILE:-0.1}"
PROJECT_MESH_ON_SURFACE_POINTS="${PROJECT_MESH_ON_SURFACE_POINTS:-True}"
LOW_OPACITY_GAUSSIAN_THRESHOLD="${LOW_OPACITY_GAUSSIAN_THRESHOLD:-0.5}"
GPU="${GPU:-0}"
ABLATION_TAG="${COARSE_MESH_ABLATION_TAG:-}"

if [[ "$INTERACTIVE" == "1" ]]; then
    echo "=== Guided coarse mesh ablation ==="
    echo "Enter EXPLAIN at any prompt for the parameter rationale."
    ask_value SOURCE_RUN_TAG \
        "Source run tag with existing coarse checkpoint (or EXPLAIN)" "$SOURCE_RUN_TAG" explain_source_run
    ask_value MESH_VERTICES \
        "Coarse mesh vertex target (or EXPLAIN)" "$MESH_VERTICES" explain_mesh_vertices
    ask_value SURFACE_SAMPLE_COUNT \
        "Total camera surface samples (or EXPLAIN)" "$SURFACE_SAMPLE_COUNT" explain_surface_sample_count
    ask_value SURFACE_LEVEL \
        "Gaussian surface level (or EXPLAIN)" "$SURFACE_LEVEL" explain_surface_level
    ask_value POISSON_DEPTH \
        "Poisson octree depth (or EXPLAIN)" "$POISSON_DEPTH" explain_poisson_depth
    ask_value VERTICES_DENSITY_QUANTILE \
        "Poisson density cleanup quantile (or EXPLAIN)" "$VERTICES_DENSITY_QUANTILE" explain_density_quantile
    ask_value PROJECT_MESH_ON_SURFACE_POINTS \
        "Project vertices to sampled surface points? True/False (or EXPLAIN)" "$PROJECT_MESH_ON_SURFACE_POINTS" explain_projection
    ask_value LOW_OPACITY_GAUSSIAN_THRESHOLD \
        "Low-opacity Gaussian threshold (or EXPLAIN)" "$LOW_OPACITY_GAUSSIAN_THRESHOLD" explain_low_opacity_threshold
fi

DEFAULT_ABLATION_TAG="depth${POISSON_DEPTH}_v${MESH_VERTICES}_samples${SURFACE_SAMPLE_COUNT}_level${SURFACE_LEVEL//./}_q${VERTICES_DENSITY_QUANTILE//./}_proj${PROJECT_MESH_ON_SURFACE_POINTS,,}_opacity${LOW_OPACITY_GAUSSIAN_THRESHOLD//./}"
if [[ "$INTERACTIVE" == "1" ]]; then
    ask_value ABLATION_TAG \
        "New ablation output tag (or EXPLAIN)" "${ABLATION_TAG:-$DEFAULT_ABLATION_TAG}" explain_ablation_tag
fi
ABLATION_TAG="${ABLATION_TAG:-$DEFAULT_ABLATION_TAG}"

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: ITERATIONS must be a positive integer." >&2
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
if ! [[ "$SURFACE_LEVEL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: SURFACE_LEVEL must be a non-negative decimal number." >&2
    exit 2
fi
if ! [[ "$POISSON_DEPTH" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: POISSON_DEPTH must be a positive integer." >&2
    exit 2
fi
if ! [[ "$VERTICES_DENSITY_QUANTILE" =~ ^(0|0\.[0-9]+)$ ]]; then
    echo "Error: VERTICES_DENSITY_QUANTILE must be in [0, 1)." >&2
    exit 2
fi
if ! [[ "$LOW_OPACITY_GAUSSIAN_THRESHOLD" =~ ^0(\.[0-9]+)?$ ]]; then
    echo "Error: LOW_OPACITY_GAUSSIAN_THRESHOLD must be in [0, 1)." >&2
    exit 2
fi
case "${PROJECT_MESH_ON_SURFACE_POINTS,,}" in
    1|true|yes|y)
        PROJECT_MESH_ON_SURFACE_POINTS="True"
        ;;
    0|false|no|n)
        PROJECT_MESH_ON_SURFACE_POINTS="False"
        ;;
    *)
        echo "Error: PROJECT_MESH_ON_SURFACE_POINTS must be True or False." >&2
        exit 2
        ;;
esac
if ! [[ "$SOURCE_RUN_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: SOURCE_RUN_TAG may contain only letters, digits, dots, underscores, and hyphens." >&2
    exit 2
fi
if ! [[ "$ABLATION_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: COARSE_MESH_ABLATION_TAG may contain only letters, digits, dots, underscores, and hyphens." >&2
    exit 2
fi

SOURCE_OUTPUT_HOST_DIR="data/sugar_output/${SOURCE_RUN_TAG}"
CHECKPOINT_HOST_DIR="data/05_3dgs/masked_sugar_input/${SOURCE_RUN_TAG}"
COARSE_MODEL_HOST_PATH="${COARSE_MODEL:-}"
if [[ -z "$COARSE_MODEL_HOST_PATH" ]]; then
    COARSE_MODEL_HOST_PATH="$(find "$SOURCE_OUTPUT_HOST_DIR/coarse" -type f -name '*.pt' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
fi
OUTPUT_HOST_DIR="$SOURCE_OUTPUT_HOST_DIR/coarse_mesh_ablation/$ABLATION_TAG"

if [[ ! -d "$CHECKPOINT_HOST_DIR" ]]; then
    echo "Error: Private mask-aware checkpoint directory does not exist:" >&2
    echo "  $CHECKPOINT_HOST_DIR" >&2
    exit 2
fi
if [[ -z "$COARSE_MODEL_HOST_PATH" || ! -f "$COARSE_MODEL_HOST_PATH" ]]; then
    echo "Error: No coarse SuGaR .pt checkpoint was found below:" >&2
    echo "  $SOURCE_OUTPUT_HOST_DIR/coarse" >&2
    exit 2
fi
if [[ -e "$OUTPUT_HOST_DIR" ]]; then
    echo "Error: Coarse mesh ablation output already exists: $OUTPUT_HOST_DIR" >&2
    echo "Choose a new COARSE_MESH_ABLATION_TAG; existing outputs are never replaced." >&2
    exit 2
fi

case "$COARSE_MODEL_HOST_PATH" in
    data/*)
        COARSE_MODEL_CONTAINER_PATH="/$COARSE_MODEL_HOST_PATH"
        ;;
    "$PROJECT_ROOT"/data/*)
        COARSE_MODEL_CONTAINER_PATH="/data/${COARSE_MODEL_HOST_PATH#"$PROJECT_ROOT"/data/}"
        ;;
    *)
        echo "Error: COARSE_MODEL must be below this project's data/ directory." >&2
        exit 2
        ;;
esac

mkdir -p "$(dirname "$OUTPUT_HOST_DIR")"
OUTPUT_CONTAINER_DIR="/data/${OUTPUT_HOST_DIR#data/}"
CHECKPOINT_CONTAINER_DIR="/data/05_3dgs/masked_sugar_input/${SOURCE_RUN_TAG}/"

echo "=== Coarse mesh ablation ==="
echo "Source run       : $SOURCE_RUN_TAG"
echo "Coarse checkpoint: $COARSE_MODEL_HOST_PATH"
echo "Output directory : $OUTPUT_HOST_DIR"
echo "Output type      : coarse mesh only; no refinement, UV texture, or crop"
echo "Mesh vertices    : $MESH_VERTICES"
echo "Surface samples  : $SURFACE_SAMPLE_COUNT"
echo "Surface level    : $SURFACE_LEVEL"
echo "Poisson depth    : $POISSON_DEPTH"
echo "Density quantile : $VERTICES_DENSITY_QUANTILE"
echo "Project vertices : $PROJECT_MESH_ON_SURFACE_POINTS"
echo "Low-opacity threshold: $LOW_OPACITY_GAUSSIAN_THRESHOLD"

docker compose -f docker-compose.yml -f docker-compose.sugar-dev.yml run --rm sugar-meshing \
    python3 extract_mesh.py \
    -s /data/05_3dgs \
    -c "$CHECKPOINT_CONTAINER_DIR" \
    -i "$ITERATIONS" \
    -m "$COARSE_MODEL_CONTAINER_PATH" \
    -l "$SURFACE_LEVEL" \
    -d "$MESH_VERTICES" \
    -o "$OUTPUT_CONTAINER_DIR" \
    --surface-sample-count "$SURFACE_SAMPLE_COUNT" \
    --project_mesh_on_surface_points "$PROJECT_MESH_ON_SURFACE_POINTS" \
    --poisson-depth "$POISSON_DEPTH" \
    --vertices-density-quantile "$VERTICES_DENSITY_QUANTILE" \
    --low-opacity-gaussian-threshold "$LOW_OPACITY_GAUSSIAN_THRESHOLD" \
    --eval True \
    --gpu "$GPU"

echo "=== Coarse mesh ablation completed ==="
echo "Mesh output: $OUTPUT_HOST_DIR"