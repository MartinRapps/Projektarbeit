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
        if [[ "$AUTOPILOT" == "true" ]]; then
            echo "Autopilot aktiv: Verwende standardmaessig das komprimierte Video."
            SELECTED_VIDEO="$compressed_video"
            return
        fi
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

    if [[ "$AUTOPILOT" == "true" ]]; then
        echo "Autopilot aktiv: Erzeuge komprimiertes Arbeitsvideo mit Standard-Vorgaben..."
        CREATE_COMPRESSED="y"
    else
        echo "Optional kann vor SAM3 ein komprimiertes Arbeitsvideo erzeugt werden."
        echo "Warum das sinnvoll ist: kleinere Aufloesung/FPS sparen VRAM, I/O und Laufzeit; das Rohvideo bleibt unveraendert erhalten."
        echo "Empfohlene Defaults: transpose=0 (keine Rotation), fps=10, codec=libx264, crf=23, preset=medium"
        echo "Hinweis: Die Skalierung erhaelt das Seitenverhaeltnis und fuellt mit schwarzem Rand auf."
        if [[ "$orientation_hint" == "portrait" ]]; then
            echo "WICHTIG: Das Eingabevideo wirkt wie Hochkant. Bitte nur drehen, wenn das Bild sichtbar falsch ausgerichtet ist."
        fi
        read -p "Komprimiertes Arbeitsvideo erzeugen, falls keines vorhanden ist? (y/n) [Default: y]: " CREATE_COMPRESSED
    fi

    if [[ -z "$CREATE_COMPRESSED" || "$CREATE_COMPRESSED" =~ ^[Yy]$ ]]; then
        local default_width=1920
        local default_height=1080
        if [[ "$orientation_hint" == "portrait" ]]; then
            default_width=1080
            default_height=1920
        fi

        local transpose_value=0
        local target_width=$default_width
        local target_height=$default_height
        local target_fps=10
        local target_crf=23
        local target_preset="medium"

        if [[ "$AUTOPILOT" != "true" ]]; then
            read -p "Transpose anwenden? 0 = keine Rotation, 1 = 90 Grad CW, 2 = 90 Grad CCW [Default: 0]: " USER_TRANSPOSE
            transpose_value=${USER_TRANSPOSE:-0}

            read -p "Zielbreite [Default: ${default_width}]: " USER_WIDTH
            target_width=${USER_WIDTH:-$default_width}

            read -p "Zielhoehe [Default: ${default_height}]: " USER_HEIGHT
            target_height=${USER_HEIGHT:-$default_height}

            read -p "Ziel-FPS [Default: 10]: " USER_FPS
            target_fps=${USER_FPS:-10}

            read -p "CRF Qualitaet (kleiner = bessere Qualitaet, groesser = kleinere Datei) [Default: 23]: " USER_CRF
            target_crf=${USER_CRF:-23}

            read -p "x264 Preset (ultrafast ... placebo) [Default: medium]: " USER_PRESET
            target_preset=${USER_PRESET:-medium}
        fi

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

# Explanations for SuGaR configuration options (invoked via the 'EXPLAIN' keyword at the prompts)
explain_regularization() {
    echo ""
    echo "  dn_consistency : (EMPFOHLEN) Kombiniert Dichte- und Normalen-Konsistenz-Regularisierung."
    echo "                   Erzwingt, dass die Gaussians sich flach an echte Oberflaechen anschmiegen und"
    echo "                   ihre Normalen mit der lokalen Tiefenkarte uebereinstimmen. Liefert laut SuGaR-Autoren"
    echo "                   die beste Mesh-Qualitaet, besonders fuer duenne/zylindrische Objekte wie Kabel."
    echo "  density        : Nutzt nur eine Dichte-basierte Regularisierung (SDF ueber Gaussian-Dichtefunktion)."
    echo "                   Schneller, aber tendenziell 'wolkigere', weniger scharfe Oberflaechen."
    echo "  sdf            : Nutzt eine reine Signed-Distance-Function-Regularisierung. Historisch aeltester Ansatz"
    echo "                   von SuGaR, in der Praxis meist von dn_consistency in der Qualitaet uebertroffen."
    echo ""
}

explain_refinement_time() {
    echo ""
    echo "  short  : ~2000 Refinement-Iterationen. Schnell (Minuten), ideal zum Testen der Pipeline/Parameter."
    echo "  medium : ~7000 Refinement-Iterationen. Guter Kompromiss aus Qualitaet und Rechenzeit."
    echo "  long   : ~15000 Refinement-Iterationen. Hoechste Detailtreue, aber deutlich laengere Trainingszeit."
    echo ""
}

echo "=== Starting Scan-to-BIM Reconstruction Pipeline ==="

# Step 0: GCP Coordinate Preparation (Relative Coordinates)
echo "[Step 0/5] Preparing relative GCP coordinates..."
while true; do
    if [ -f "data/01_raw/gcp_relative.csv" ]; then
        echo "Hinweis: Es existieren bereits relative GCP-Koordinaten (gcp_relative.csv) im raw-Verzeichnis."
        read -p "Moechten Sie diese bestehenden relative Koordinaten weiterverwenden? (y/n) [Default: y]: " USE_EXISTING
        USE_EXISTING=${USE_EXISTING:-y}
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            break
        fi
    elif compgen -G "data/01_raw/*.csv" > /dev/null; then
        echo "Gefunden: Mindestens eine CSV-Datei im raw-Verzeichnis ist hochgeladen."
        break
    fi

    echo "=========================================================="
    echo "SCHRITT ERFORDERLICH: Keine GCP-Passpunktdaten gefunden!"
    echo "Bitte lade mindestens eine CSV-Datei mit GCP-Koordinaten"
    echo "unter data/01_raw/ hoch (z.B. bequem per Drag & Drop im Dashboard)."
    echo "=========================================================="
    read -p "Sobald die CSV-Datei unter 'data/01_raw/' hochgeladen ist, druecke [Enter]..."
done

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

# Autopilot Prompt configuration
read -p "Moechten Sie die Pipeline im Autopilot-Modus ausfuehren? (Alle Standardvorgaben automatisch waehlen) (y/n) [Default: n]: " USER_AUTOPILOT
if [[ "$USER_AUTOPILOT" =~ ^[Yy]$ ]]; then
    AUTOPILOT="true"
    echo "Autopilot-Modus AKTIVIERT. Interaktive Abfragen werden mit Standardwerten beantwortet."
else
    AUTOPILOT="false"
fi

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
echo "the 4x4 transformation matrix."
echo "=========================================================="

while true; do
    read -p "Moechten Sie die Matrix per OCR aus einem Screenshot einlesen? (y/n) [Default: n]: " USER_OCR
    if [[ "$USER_OCR" =~ ^[Yy]$ ]]; then
        echo ""
        echo "--> Anleitung fuer OCR-Einlesen:"
        echo "    1. Mache einen Screenshot von dem gesamten Matrix-Ausgabefeld in CloudCompare."
        echo "    2. Speichere das Bild als PNG oder JPG unter dem Namen:"
        echo "       data/01_raw/matrix_screenshot.png (oder .jpg)"
        echo ""
        
        while true; do
            read -p "Haben Sie den Screenshot unter 'data/01_raw/matrix_screenshot.png' abgelegt? (y/n): " SCREENSHOT_OK
            if [[ "$SCREENSHOT_OK" =~ ^[Yy]$ ]]; then
                echo "Starte OCR-Einlesevorgang mit Tesseract in Container A..."
                # Run OCR in Container A and write output directly to data/04_sfm/matrix.txt
                if docker compose run --rm sam3-preprocess python3 /app/src/python/ocr_matrix.py /data/01_raw/matrix_screenshot.png /data/04_sfm/matrix.txt; then
                    echo ""
                    echo "--- Eingelesene Transformationsmatrix ---"
                    cat data/04_sfm/matrix.txt
                    echo "----------------------------------------"
                    echo ""
                    
                    read -p "Ist diese Matrix fehlerfrei erkannt und korrekt eingelesen worden? (y/n): " MATRIX_OK
                    if [[ "$MATRIX_OK" =~ ^[Yy]$ ]]; then
                        echo "Matrix erfolgreich geprueft und uebernommen!"
                        break 2
                    else
                        echo "Schade, OCR war ungenau. Sie koennen das Bild korrigieren/besser zuschneiden und es erneut versuchen, oder die Datei data/04_sfm/matrix.txt jetzt manuell bearbeiten."
                        read -p "Moechten Sie es erneut mit OCR versuchen? (y/n) [Default: y]: " RETRY_OCR
                        if [[ ! "$RETRY_OCR" =~ ^[Nn]$ ]]; then
                            continue
                        fi
                    fi
                else
                    echo "Fehler bei der OCR-Verarbeitung des Screenshots!"
                fi
            fi
            
            # If they don't want to retry or OCR failed and they chose not to retry
            echo "Wechsle zur manuellen Kontrolle..."
            echo "Bitte trage die Transformationsmatrix manuell unter 'data/04_sfm/matrix.txt' ein."
            read -p "Haben Sie die Datei 'data/04_sfm/matrix.txt' kontrolliert/manuell gespeichert? Druecken Sie [Enter] zum Fortfahren..."
            break 2
        done
    else
        echo "Manuelle Eingabe gewaehlt (kein OCR)."
        echo "Bitte speichere die 4x4-Transformationsmatrix aus CloudCompare zeilenweise (kommagetrennt) unter:"
        echo "data/04_sfm/matrix.txt"
        read -p "Sobald die Matrix-Datei gespeichert ist, druecken Sie [Enter] zum Fortfahren..."
        break
    fi
done

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

# Step 3.5: Export an object-only STS cloud without mutating the standard
# full-scene checkpoint. Stock SuGaR uses full RGB supervision, so replacing
# point_cloud.ply here would recreate an object-cloud/full-image mismatch.
echo "[Step 3.5/5] Preserving the full STS cloud and exporting a filtered object cloud..."
docker compose run --rm sts-training python3 -c "import os, shutil; base='/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'; src=f'{base}/point_cloud.ply'; dst=f'{base}/point_cloud_full_scene.ply'; os.path.exists(src) or (_ for _ in ()).throw(FileNotFoundError(src)); shutil.copy2(src, dst)"
docker compose run --rm sts-training python3 /app/src/python/filter_cable_pc.py \
    --input_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" \
    --output_ply "/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_cable.ply" \
    --level m \
    --object_id 0

echo "[Step 3.5/5] Standard point_cloud.ply remains full-scene for a consistent stock-SuGaR baseline."
echo "              Run ./run_masked_sugar.sh for the object-only, mask-aware SuGaR workflow."

# Step 4: Meshing (SuGaR regularized mesh extraction)
echo "=========================================================="
echo "SuGaR Mesh Reconstruction Configuration"
echo "=========================================================="
if [[ "$AUTOPILOT" == "true" ]]; then
    REGULARIZATION="dn_consistency"
    REFINEMENT_TIME="short"
    echo "Autopilot aktiv: Regularisierung=dn_consistency, Refinement-Dauer=short (2000 Iterationen)."
else
    while true; do
        read -p "Regularization type (sdf/density/dn_consistency, oder 'EXPLAIN' fuer Erklaerung) [Default: dn_consistency]: " USER_REG
        if [[ "${USER_REG,,}" == "explain" ]]; then
            explain_regularization
            continue
        fi
        REGULARIZATION=${USER_REG:-dn_consistency}
        break
    done

    while true; do
        read -p "Refinement time (short/medium/long, oder 'EXPLAIN' fuer Erklaerung) [Default: short]: " USER_REFTIME
        if [[ "${USER_REFTIME,,}" == "explain" ]]; then
            explain_refinement_time
            continue
        fi
        REFINEMENT_TIME=${USER_REFTIME:-short}
        break
    done
fi
echo "--------------------------------------------------------"
echo "Active Configuration:"
echo " - Regularization Type: $REGULARIZATION"
echo " - Refinement Time: $REFINEMENT_TIME"
echo " - Vanilla 3DGS Checkpoint Iteration: $ITERATIONS"
echo "--------------------------------------------------------"

# NOTE: extract_mesh.py alone cannot regularize a coarse SuGaR model - it only extracts a mesh
# from an already-trained coarse checkpoint. The '-r/--regularization_type' flag belongs to the
# root-level train.py, which runs: coarse SuGaR training (regularized) -> mesh extraction -> refinement.
echo "[Step 4/5] Running SuGaR Full Pipeline (Coarse Training -> Mesh Extraction -> Refinement)..."
# Make sure the checkpoint path has a trailing slash because SuGaR simply concatenates 'cameras.json' to it!
docker compose run --rm sugar-meshing python3 train.py \
    -s /data/05_3dgs \
    -c /data/05_3dgs/output/ \
    -i "$ITERATIONS" \
    -r "$REGULARIZATION" \
    --refinement_time "$REFINEMENT_TIME" \
    --eval True

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline Completed Successfully. Final outputs saved in data/08_gis/ ==="
