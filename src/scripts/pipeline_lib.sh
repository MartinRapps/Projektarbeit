#!/bin/bash
# =============================================================================
# pipeline_lib.sh — Shared function library for the Scan-to-BIM Pipeline
# =============================================================================
# Source this file in any pipeline script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/src/scripts/pipeline_lib.sh"
# =============================================================================

# --- Constants ---------------------------------------------------------------
readonly RAW_DIR="data/01_raw"
readonly FRAMES_DIR="data/02_frames"
readonly MASKS_DIR="data/03_masks"
readonly SFM_DIR="data/04_sfm"
readonly _3DGS_DIR="data/05_3dgs"
readonly MESH_DIR="data/06_mesh"
readonly CENTERLINE_DIR="data/07_centerline"
readonly GIS_DIR="data/08_gis"
readonly EVAL_DIR="data/09_evaluation"

# Pipeline state (set by configure_* functions, consumed by run_* functions)
AUTOPILOT="${AUTOPILOT:-false}"
SELECTED_VIDEO=""
TEXT_PROMPT=""
ITERATIONS=7000
STAGE2_ITERS=5000
ON_THE_FLY=""

# --- Logging -----------------------------------------------------------------
_log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*"
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@" >&2; }
log_error() { _log "ERROR" "$@" >&2; }
log_step()  { echo ""; echo "=========================================================="; _log "STEP" "$@"; echo "=========================================================="; }

# --- Validation Helpers ------------------------------------------------------
validate_dir_not_empty() {
    local dir_path="$1"
    local description="$2"
    if [[ ! -d "$dir_path" ]] || [[ -z "$(ls -A "$dir_path" 2>/dev/null)" ]]; then
        log_error "$description: Verzeichnis '$dir_path' existiert nicht oder ist leer."
        return 1
    fi
    local count
    count=$(find "$dir_path" -maxdepth 1 -type f | wc -l)
    log_info "$description: $count Dateien in '$dir_path' gefunden."
    return 0
}

validate_file_exists() {
    local file_path="$1"
    local description="$2"
    if [[ ! -f "$file_path" ]]; then
        log_error "$description: Datei '$file_path' nicht gefunden."
        return 1
    fi
    local size
    size=$(stat --printf="%s" "$file_path" 2>/dev/null || echo "0")
    if [[ "$size" -eq 0 ]]; then
        log_warn "$description: Datei '$file_path' ist leer (0 Bytes)."
        return 1
    fi
    log_info "$description: '$file_path' OK ($(numfmt --to=iec "$size" 2>/dev/null || echo "$size bytes"))"
    return 0
}

validate_masks_quality() {
    # Check that at least some masks are non-empty
    local masks_dir="$1"
    local min_nonempty="${2:-1}"

    if [[ ! -d "$masks_dir" ]]; then
        log_error "Maskenverzeichnis '$masks_dir' existiert nicht."
        return 1
    fi

    local total_masks nonempty_masks
    total_masks=$(find "$masks_dir" -maxdepth 1 -name "frame_*_obj_001.png" -type f | wc -l)
    if [[ "$total_masks" -eq 0 ]]; then
        # Check hierarchical masks
        total_masks=$(find "$masks_dir" -name "middle.png" -type f | wc -l)
    fi

    if [[ "$total_masks" -eq 0 ]]; then
        log_error "Keine Masken in '$masks_dir' gefunden."
        return 1
    fi

    log_info "Masken-Qualitaet: $total_masks Masken-Dateien gefunden."
    return 0
}

validate_colmap_model() {
    local sparse_dir="$1"
    if [[ ! -d "$sparse_dir" ]]; then
        log_error "COLMAP Sparse-Verzeichnis '$sparse_dir' nicht gefunden."
        return 1
    fi

    # Check for COLMAP output files in any subdirectory
    local found_model=false
    for subdir in "$sparse_dir" "$sparse_dir"/*/; do
        if [[ -f "$subdir/cameras.bin" ]] || [[ -f "$subdir/cameras.txt" ]]; then
            if [[ -f "$subdir/images.bin" ]] || [[ -f "$subdir/images.txt" ]]; then
                if [[ -f "$subdir/points3D.bin" ]] || [[ -f "$subdir/points3D.txt" ]]; then
                    found_model=true
                    log_info "COLMAP-Modell gefunden in: $subdir"
                    break
                fi
            fi
        fi
    done

    if [[ "$found_model" == "false" ]]; then
        log_error "Kein vollstaendiges COLMAP-Modell (cameras + images + points3D) gefunden in '$sparse_dir'."
        return 1
    fi
    return 0
}

# --- Environment Setup -------------------------------------------------------
load_env() {
    if [[ -f .env ]]; then
        # shellcheck disable=SC2046
        export $(grep -v '^#' .env | grep -v '^\s*$' | xargs)
        log_info ".env Datei geladen."
    fi
}

check_hf_token() {
    load_env
    if [[ -z "${HF_TOKEN:-}" ]]; then
        echo "=========================================================="
        echo "HINWEIS: SAM 3.1 ist ein geschuetztes (gated) Modell auf HuggingFace."
        echo "Dein Token wird sicher in der .env-Datei gespeichert."
        echo "=========================================================="
        read -rp "Bitte HuggingFace Token eingeben (faengt mit hf_ an): " INPUT_TOKEN
        if [[ -n "$INPUT_TOKEN" ]]; then
            echo "HF_TOKEN=$INPUT_TOKEN" >> .env
            export HF_TOKEN="$INPUT_TOKEN"
            echo "Token erfolgreich in .env gespeichert!"
        else
            log_warn "Kein HuggingFace Token eingegeben. Gated Modelle schlagen evtl. fehl."
        fi
    else
        log_info "HF_TOKEN ist gesetzt."
    fi
}

# --- Autopilot Configuration -------------------------------------------------
configure_autopilot() {
    if [[ "$AUTOPILOT" == "true" ]]; then
        log_info "Autopilot-Modus bereits aktiviert (via Umgebungsvariable oder Parameter)."
        return
    fi

    read -rp "Pipeline im Autopilot-Modus ausfuehren? (Alle Standardvorgaben automatisch) (y/n) [Default: n]: " USER_AUTOPILOT
    if [[ "$USER_AUTOPILOT" =~ ^[Yy]$ ]]; then
        AUTOPILOT="true"
        log_info "Autopilot-Modus AKTIVIERT."
    else
        AUTOPILOT="false"
    fi
}

# --- Video Input Configuration -----------------------------------------------
configure_video_input() {
    local raw_video=""
    local compressed_video=""
    local detected_width=""
    local detected_height=""
    local orientation_hint="unknown"

    for candidate in "$RAW_DIR"/*; do
        [[ -e "$candidate" ]] || continue
        case "${candidate,,}" in
            *.mp4|*.mov)
                if [[ "$(basename "$candidate")" == "output.mp4" ]]; then
                    compressed_video="$candidate"
                elif [[ -z "$raw_video" ]]; then
                    raw_video="$candidate"
                fi
                ;;
        esac
    done

    if [[ -n "$compressed_video" ]]; then
        log_info "Gefundenes komprimiertes Video: $compressed_video"
        if [[ "$AUTOPILOT" == "true" ]]; then
            log_info "Autopilot: Verwende komprimiertes Video."
            SELECTED_VIDEO="$compressed_video"
            return
        fi
        read -rp "Komprimiertes Video fuer SAM3 verwenden? (y/n) [Default: y]: " USE_COMPRESSED
        if [[ -z "$USE_COMPRESSED" || "$USE_COMPRESSED" =~ ^[Yy]$ ]]; then
            SELECTED_VIDEO="$compressed_video"
            return
        fi
    fi

    if [[ -z "$raw_video" ]]; then
        if [[ -n "$compressed_video" ]]; then
            log_info "Kein weiteres Rohvideo gefunden. Verwende $compressed_video"
            SELECTED_VIDEO="$compressed_video"
            return
        fi
        log_warn "Kein Video in $RAW_DIR gefunden."
        return
    fi

    log_info "Originalvideo erkannt: $raw_video"

    # Detect video resolution
    local probe_output
    probe_output=$(docker compose run --rm sam3-preprocess ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0:s=x \
        "/data/01_raw/$(basename "$raw_video")" 2>/dev/null | tr -d '\r' | head -n 1)
    if [[ "$probe_output" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        detected_width="${BASH_REMATCH[1]}"
        detected_height="${BASH_REMATCH[2]}"
        if (( detected_height > detected_width )); then
            orientation_hint="portrait"
        else
            orientation_hint="landscape"
        fi
        log_info "Erkannte Videoaufloesung: ${detected_width}x${detected_height} (${orientation_hint})"
    else
        log_warn "Konnte Videoorientierung nicht automatisch erkennen."
    fi

    if [[ "$AUTOPILOT" == "true" ]]; then
        log_info "Autopilot: Erzeuge komprimiertes Arbeitsvideo mit Standard-Vorgaben..."
        _create_compressed_video "$raw_video" "$orientation_hint" 0
        return
    fi

    echo "Optional kann vor SAM3 ein komprimiertes Arbeitsvideo erzeugt werden."
    echo "Warum: kleinere Aufloesung/FPS sparen VRAM, I/O und Laufzeit."
    echo "Empfohlene Defaults: transpose=0, fps=10, codec=libx264, crf=23, preset=medium"
    if [[ "$orientation_hint" == "portrait" ]]; then
        echo "WICHTIG: Hochkant erkannt. Bitte nur drehen, wenn das Bild sichtbar falsch ausgerichtet ist."
    fi
    read -rp "Komprimiertes Arbeitsvideo erzeugen? (y/n) [Default: y]: " CREATE_COMPRESSED

    if [[ -z "$CREATE_COMPRESSED" || "$CREATE_COMPRESSED" =~ ^[Yy]$ ]]; then
        _create_compressed_video_interactive "$raw_video" "$orientation_hint"
    else
        SELECTED_VIDEO="$raw_video"
    fi
}

_create_compressed_video() {
    local raw_video="$1"
    local orientation_hint="$2"
    local transpose_value="${3:-0}"
    local target_width=1920
    local target_height=1080
    local target_fps=10
    local target_crf=23
    local target_preset="medium"

    if [[ "$orientation_hint" == "portrait" ]]; then
        target_width=1080
        target_height=1920
    fi

    local vf_chain=""
    if [[ "$transpose_value" != "0" ]]; then
        vf_chain="transpose=${transpose_value},"
    fi
    vf_chain+="scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease,pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:black,fps=${target_fps}"

    log_info "Erzeuge komprimiertes Arbeitsvideo (${target_width}x${target_height}, ${target_fps}fps, crf=${target_crf})..."
    docker compose run --rm sam3-preprocess ffmpeg -y -i "/data/01_raw/$(basename "$raw_video")" \
        -vf "$vf_chain" \
        -c:v libx264 -crf "$target_crf" -preset "$target_preset" \
        -an "/data/01_raw/output.mp4"

    SELECTED_VIDEO="$RAW_DIR/output.mp4"
}

_create_compressed_video_interactive() {
    local raw_video="$1"
    local orientation_hint="$2"
    local default_width=1920
    local default_height=1080

    if [[ "$orientation_hint" == "portrait" ]]; then
        default_width=1080
        default_height=1920
    fi

    read -rp "Transpose? 0=keine, 1=90CW, 2=90CCW [Default: 0]: " USER_TRANSPOSE
    local transpose_value=${USER_TRANSPOSE:-0}

    read -rp "Zielbreite [Default: ${default_width}]: " USER_WIDTH
    local target_width=${USER_WIDTH:-$default_width}

    read -rp "Zielhoehe [Default: ${default_height}]: " USER_HEIGHT
    local target_height=${USER_HEIGHT:-$default_height}

    read -rp "Ziel-FPS [Default: 10]: " USER_FPS
    local target_fps=${USER_FPS:-10}

    read -rp "CRF Qualitaet [Default: 23]: " USER_CRF
    local target_crf=${USER_CRF:-23}

    read -rp "x264 Preset [Default: medium]: " USER_PRESET
    local target_preset=${USER_PRESET:-medium}

    if [[ "$orientation_hint" == "portrait" && "$target_width" -gt "$target_height" ]]; then
        log_warn "Hochkant erkannt, aber Ziel ist Querformat (${target_width}x${target_height})."
    fi

    local vf_chain=""
    if [[ "$transpose_value" != "0" ]]; then
        vf_chain="transpose=${transpose_value},"
    fi
    vf_chain+="scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease,pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:black,fps=${target_fps}"

    log_info "Erzeuge komprimiertes Arbeitsvideo..."
    docker compose run --rm sam3-preprocess ffmpeg -y -i "/data/01_raw/$(basename "$raw_video")" \
        -vf "$vf_chain" \
        -c:v libx264 -crf "$target_crf" -preset "$target_preset" \
        -an "/data/01_raw/output.mp4"

    SELECTED_VIDEO="$RAW_DIR/output.mp4"
}

# --- STS Training Configuration ----------------------------------------------
configure_sts_training() {
    log_step "STS Gaussian Splatting Training Configuration"

    if [[ "$AUTOPILOT" == "true" ]]; then
        ITERATIONS=7000
        STAGE2_ITERS=5000
        ON_THE_FLY=""
        log_info "Autopilot: 7000 Iterationen (Stage 2: 5000) ohne On-The-Fly-Laden."
    else
        read -rp "Total training iterations (7000 to 15000) [Default: 7000]: " USER_ITERATIONS
        ITERATIONS=${USER_ITERATIONS:-7000}

        local DEFAULT_STAGE2=$(( ITERATIONS * 5 / 7 ))
        read -rp "Stage 2 fine-tuning iterations [Default: $DEFAULT_STAGE2]: " USER_STAGE2
        STAGE2_ITERS=${USER_STAGE2:-$DEFAULT_STAGE2}

        read -rp "GPU-saving 'on-the-fly' image loading? (y/n) [Default: n]: " USER_LY
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
}

# --- Pipeline Step Runners ----------------------------------------------------

run_step_gcp() {
    log_step "[Step 0/5] Preparing relative GCP coordinates..."
    docker compose run --rm sam3-preprocess python3 /app/src/python/prepare_gcp.py
}

run_step_sam3() {
    log_step "[Step 1/5] SAM 3.1 Mask Extraction: '$TEXT_PROMPT'"

    if [[ -n "$SELECTED_VIDEO" ]]; then
        log_info "Eingabevideo: $SELECTED_VIDEO"
        docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py \
            --prompt "$TEXT_PROMPT" \
            --input-path "/data/01_raw/$(basename "$SELECTED_VIDEO")"
    else
        docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py \
            --prompt "$TEXT_PROMPT"
    fi

    # Validate output
    validate_masks_quality "$MASKS_DIR" || {
        log_error "Maskenextraktion fehlgeschlagen oder leer. Pipeline stoppt."
        return 1
    }
}

run_step_colmap() {
    log_step "[Step 2/5] Running COLMAP Structure from Motion..."
    docker compose run --rm colmap-sfm /app/src/scripts/run_sfm.sh

    # Validate output
    validate_colmap_model "$SFM_DIR/sparse" || {
        log_error "COLMAP hat kein gueltiges Sparse-Modell erzeugt."
        return 1
    }
}

breakpoint_cloudcompare() {
    echo "=========================================================="
    echo "BREAKPOINT: Bitte oeffne die Sparse Point Cloud in CloudCompare"
    echo "auf dem Host-System. Picke die GCP-Koordinatenpunkte, berechne"
    echo "die 4x4-Transformationsmatrix und speichere sie in data/04_sfm/matrix.txt"
    echo "=========================================================="
    read -rp "Sobald die Transformationsmatrix gespeichert ist, druecke [Enter]..."

    validate_file_exists "$SFM_DIR/matrix.txt" "Transformationsmatrix" || {
        log_warn "matrix.txt nicht gefunden. Fortfahren auf eigene Gefahr."
    }
}

run_step_sts_prep() {
    log_step "[Step 3/5] Setting up Segment-then-Splat (STS) workspace..."
    docker compose run --rm sam3-preprocess python3 /app/src/python/prep_sts_scene.py

    log_info "Running STS object-specific 3D point cloud initialization..."
    docker compose run --rm sts-training python3 helpers/object_specific_initialization.py --scene_root /data/05_3dgs
}

run_step_sts_train() {
    log_step "[Step 3/5] Starting STS Object-Specific 3DGS Training..."
    docker compose run --rm sts-training python3 train.py \
        -s /data/05_3dgs \
        -m /data/05_3dgs/output \
        --eval \
        --iterations "$ITERATIONS" \
        --stage2_iters "$STAGE2_ITERS" \
        --save_iterations "$ITERATIONS" \
        --test_iterations "$ITERATIONS" \
        $ON_THE_FLY
}

run_step_filter_cable() {
    log_step "[Step 3.5/5] Filtering STS point cloud for target cable..."

    docker compose run --rm sts-training python3 /app/src/python/filter_cable_pc.py \
        --input_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" \
        --output_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_cable.ply" \
        --level m \
        --object_id 0

    log_info "Enforcing filtered cable-only point cloud as standard input for SuGaR..."
    docker compose run --rm sts-training python3 -c "
import os, shutil, sys
base = '/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'
src = f'{base}/point_cloud_cable.ply'
orig = f'{base}/point_cloud.ply'
bak = f'{base}/point_cloud_original.ply'
if os.path.exists(src):
    shutil.copy(orig, bak)
    shutil.copy(src, orig)
    print(f'Backup: {bak}')
    print(f'Cable-only point cloud enforced as {orig}')
else:
    print(f'Error: filtered point cloud not found: {src}')
    sys.exit(1)
"
}

run_step_sugar() {
    log_step "[Step 4/5] Running SuGaR Mesh Reconstruction..."
    docker compose run --rm sugar-meshing python3 extract_mesh.py --regularization dn_consistency
}

run_step_postprocess() {
    log_step "[Step 5/5] Extracting centerline and georeferencing to UTM..."
    docker compose run --rm post-processing /app/src/scripts/postprocess.sh
}

# --- Composite Runners -------------------------------------------------------

# Run the complete pipeline from a given starting point
# Usage: run_pipeline_from <step>
# Steps: gcp, sam3, colmap, sts, sugar, postprocess
run_pipeline_from() {
    local start_step="${1:-gcp}"
    local steps_order=(gcp sam3 colmap sts sugar postprocess)
    local started=false

    for step in "${steps_order[@]}"; do
        if [[ "$step" == "$start_step" ]]; then
            started=true
        fi
        [[ "$started" == "false" ]] && continue

        case "$step" in
            gcp)
                run_step_gcp
                ;;
            sam3)
                check_hf_token
                if [[ -z "$TEXT_PROMPT" ]]; then
                    read -rp "Maskierungs-Prompt eingeben (z.B. 'cable', 'pipe'): " TEXT_PROMPT
                fi
                configure_video_input
                run_step_sam3 || return 1
                ;;
            colmap)
                run_step_colmap || return 1
                breakpoint_cloudcompare
                ;;
            sts)
                run_step_sts_prep
                configure_sts_training
                run_step_sts_train
                run_step_filter_cable
                ;;
            sugar)
                run_step_sugar
                ;;
            postprocess)
                run_step_postprocess
                ;;
        esac
    done
}
