#!/bin/bash
set -e

RAW_DIR="data/01_raw"

configure_video_input() {
    local raw_video=""
    local compressed_video=""
    local input_video=""
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
        echo "Gefundenes komprimiertes Video: $compressed_video"
        read -p "Dieses komprimierte Video fuer SAM3 verwenden? (y/n) [Default: y]: " USE_COMPRESSED
        if [[ -z "$USE_COMPRESSED" || "$USE_COMPRESSED" =~ ^[Yy]$ ]]; then
            SELECTED_VIDEO="$compressed_video"
            return
        fi
    fi

    if [[ -z "$raw_video" ]]; then
        if [[ -n "$compressed_video" ]]; then
            echo "Kein weiteres Rohvideo gefunden. Verwende $compressed_video"
            SELECTED_VIDEO="$compressed_video"
            return
        fi
        return
    fi

    echo "Originalvideo erkannt: $raw_video"

    local probe_output
    probe_output=$(docker compose run --rm sam3-preprocess ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "/data/01_raw/$(basename "$raw_video")" 2>/dev/null | tr -d '\r' | head -n 1)
    if [[ "$probe_output" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        detected_width="${BASH_REMATCH[1]}"
        detected_height="${BASH_REMATCH[2]}"
        if (( detected_height > detected_width )); then
            orientation_hint="portrait"
        else
            orientation_hint="landscape"
        fi
        echo "Erkannte Videoaufloesung: ${detected_width}x${detected_height} (${orientation_hint})"
    else
        echo "Hinweis: Konnte Videoorientierung nicht automatisch erkennen."
    fi

    echo "Optional kann vor SAM3 ein komprimiertes Arbeitsvideo erzeugt werden."
    echo "Warum das sinnvoll ist: kleinere Aufloesung/FPS sparen VRAM, I/O und Laufzeit; das Rohvideo bleibt unveraendert erhalten."
    echo "Empfohlene Defaults: transpose=0 (keine Rotation), fps=10, codec=libx264, crf=23, preset=medium"
    echo "Hinweis: Die Skalierung erhaelt das Seitenverhaeltnis und fuellt mit schwarzem Rand auf."
    if [[ "$orientation_hint" == "portrait" ]]; then
        echo "WICHTIG: Das Eingabevideo wirkt wie Hochkant. Bitte nur drehen, wenn das Bild sichtbar falsch ausgerichtet ist."
    fi
    read -p "Komprimiertes Arbeitsvideo erzeugen, falls keines vorhanden ist? (y/n) [Default: y]: " CREATE_COMPRESSED

    if [[ -z "$CREATE_COMPRESSED" || "$CREATE_COMPRESSED" =~ ^[Yy]$ ]]; then
        local default_width=1920
        local default_height=1080
        if [[ "$orientation_hint" == "portrait" ]]; then
            default_width=1080
            default_height=1920
        fi

        read -p "Transpose anwenden? 0 = keine Rotation, 1 = 90 Grad CW, 2 = 90 Grad CCW [Default: 0]: " USER_TRANSPOSE
        local transpose_value=${USER_TRANSPOSE:-0}

        read -p "Zielbreite [Default: ${default_width}]: " USER_WIDTH
        local target_width=${USER_WIDTH:-$default_width}

        read -p "Zielhoehe [Default: ${default_height}]: " USER_HEIGHT
        local target_height=${USER_HEIGHT:-$default_height}

        read -p "Ziel-FPS [Default: 10]: " USER_FPS
        local target_fps=${USER_FPS:-10}

        read -p "CRF Qualitaet (kleiner = bessere Qualitaet, groesser = kleinere Datei) [Default: 23]: " USER_CRF
        local target_crf=${USER_CRF:-23}

        read -p "x264 Preset (ultrafast ... placebo) [Default: medium]: " USER_PRESET
        local target_preset=${USER_PRESET:-medium}

        if [[ "$orientation_hint" == "portrait" && "$target_width" -gt "$target_height" ]]; then
            echo "Warnung: Hochkant erkannt, aber Ziel ist Querformat (${target_width}x${target_height})."
            echo "Wenn das ungewollt ist, besser 1080x1920 verwenden."
        fi

        local vf_chain=""
        if [[ "$transpose_value" != "0" ]]; then
            vf_chain="transpose=${transpose_value},"
        fi
        vf_chain+="scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease,pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:black,fps=${target_fps}"

        echo "Erzeuge komprimiertes Arbeitsvideo unter $RAW_DIR/output.mp4 ..."
        docker compose run --rm sam3-preprocess ffmpeg -y -i "/data/01_raw/$(basename "$raw_video")" \
            -vf "$vf_chain" \
            -c:v libx264 -crf "$target_crf" -preset "$target_preset" \
            -an "/data/01_raw/output.mp4"

        SELECTED_VIDEO="$RAW_DIR/output.mp4"
        return
    fi

    SELECTED_VIDEO="$raw_video"
}

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

SELECTED_VIDEO=""
configure_video_input

# Step 1: Pre-processing (SAM 3 Tracking)
echo "[Step 1/5] Extracting frames and generating SAM 3 masks for: $TEXT_PROMPT ..."
if [[ -n "$SELECTED_VIDEO" ]]; then
    echo "Verwendetes Eingabevideo fuer SAM3: $SELECTED_VIDEO"
    docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py \
        --prompt "$TEXT_PROMPT" \
        --input-path "/data/01_raw/$(basename "$SELECTED_VIDEO")"
else
    docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py --prompt "$TEXT_PROMPT"
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

# Step 3.5: Filter STS point cloud targeting only the cable (Value=0) on Medium Level (obj_id_m)
echo "[Step 3.5/5] Backing up and filtering STS point cloud for target cable..."
docker compose run --rm sts-training python3 /app/src/python/filter_cable_pc.py \
    --input_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" \
    --output_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_cable.ply" \
    --level m \
    --object_id 0

echo "[Step 3.5/5] Enforcing filtered cable-only point cloud as standard input for SuGaR..."
docker compose run --rm sts-training python3 -c "import os, shutil, sys; base='/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'; src=f'{base}/point_cloud_cable.ply'; orig=f'{base}/point_cloud.ply'; bak=f'{base}/point_cloud_original.ply'; (shutil.copy(orig, bak), shutil.copy(src, orig)) if os.path.exists(src) else (print(f'Error: filtered point cloud not found: {src}'), sys.exit(1))"

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "[Step 4/5] Running SuGaR Mesh Reconstruction..."
docker compose run --rm sugar-meshing python3 extract_mesh.py --regularization dn_consistency

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline Completed Successfully. Final outputs saved in data/08_gis/ ==="
