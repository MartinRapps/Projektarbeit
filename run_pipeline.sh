#!/bin/bash
set -e

RAW_DIR="data/01_raw"
DEFAULT_SAM3_FRAME_MAX_SIDE=768

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

explain_sam3_frame_resolution() {
    echo ""
    echo "  SAM3_FRAME_MAX_SIDE begrenzt die laengere Bildkante nach dem Frame-Export."
    echo "  Default 768 ist der aktuelle VRAM-/Laufzeit-Standard."
    echo "  Bei gleicher Seitenratio steigt die Pixelzahl mit dem Quadrat der Kantenlaenge:"
    echo "    pixels ~ side^2"
    echo "  Deshalb ist 1920 gegenueber 768 etwa 6.25x so viele Pixel"
    echo "  (2,073,600 vs 331,776 bei 16:9)."
    echo "  Die Laufzeit steigt in der Praxis meist naehlinear bis leicht superlinear"
    echo "  zur Pixelzahl, aber nicht exponentiell."
    echo ""
}

print_sam3_resolution_estimate() {
    local side="$1"
    local base="$DEFAULT_SAM3_FRAME_MAX_SIDE"
    local percent
    local multiplier

    percent=$(( side * side * 100 / (base * base) ))
    multiplier=$(awk "BEGIN {printf \"%.2f\", $percent / 100}")

    echo "SAM3_FRAME_MAX_SIDE=$side"
    echo "Geschaetzte Pixellast ggü. ${base}: ${multiplier}x (~${percent}% bei gleicher Seitenratio)."
    echo "Richtwert Laufzeit: meist naehlinear bis leicht superlinear zur Pixelzahl, nicht exponentiell."
}

configure_sam3_frame_resolution() {
    SAM3_FRAME_MAX_SIDE="${SAM3_FRAME_MAX_SIDE:-$DEFAULT_SAM3_FRAME_MAX_SIDE}"

    if [[ "$AUTOPILOT" == "true" ]]; then
        echo "Autopilot aktiv: SAM3_FRAME_MAX_SIDE=$SAM3_FRAME_MAX_SIDE."
        print_sam3_resolution_estimate "$SAM3_FRAME_MAX_SIDE"
        return
    fi

    while true; do
        read -r -p "SAM3 Frame-Max-Side (z.B. 768 oder EXPLAIN) [Default: $SAM3_FRAME_MAX_SIDE]: " USER_SAM3_SIDE
        if [[ "${USER_SAM3_SIDE,,}" == "explain" ]]; then
            explain_sam3_frame_resolution
            continue
        fi
        USER_SAM3_SIDE="${USER_SAM3_SIDE:-$SAM3_FRAME_MAX_SIDE}"
        if [[ "$USER_SAM3_SIDE" =~ ^[1-9][0-9]*$ ]]; then
            SAM3_FRAME_MAX_SIDE="$USER_SAM3_SIDE"
            break
        fi
        echo "Bitte eine positive ganze Zahl eingeben (oder EXPLAIN)."
    done

    print_sam3_resolution_estimate "$SAM3_FRAME_MAX_SIDE"
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

explain_object_filtering() {
    echo ""
    echo "  Die STS-Objektfilterung selektiert zuerst nur die Gaussians mit der"
    echo "  Ziel-Objekt-ID. FILTER_MIN_OPACITY und FILTER_BLACK_THRESHOLD wirken"
    echo "  nur auf diese vorbereitete Objektwolke. Danach wird fuer jeden"
    echo "  verbliebenen Gaussian die Opazitaet automatisch auf alpha=$SUGAR_INPUT_ALPHA"
    echo "  gesetzt. SuGaR nutzt damit die vollstaendige geometrische Stuetze"
    echo "  ohne die urspruenglichen Opazitaetswerte als Geometrie-Schranke."
    echo "  FILTER_MIN_OPACITY=0 deaktiviert die Eingangs-Opazitaetsfilterung."
    echo ""
}

explain_coarse_iterations() {
    echo ""
    echo "  Der Coarse-Wert ist der finale lokale SuGaR-Zaehler und startet bei"
    echo "  6999. Bei 9001 wird nach der harten Pruning-Grenze nur der erste"
    echo "  DN/SDF-Schritt ausgefuehrt. Dieser Wert ist der aktuelle"
    echo "  geometrieorientierte Standard; laengere Laeufe bleiben Vergleichslaeufe."
    echo ""
}

explain_mesh_vertices() {
    echo ""
    echo "  MESH_VERTICES ist das Vertexziel des Coarse-Meshes nach Poisson und"
    echo "  Decimation. 200000 ist der aktuelle Kompromiss fuer Geometrie und"
    echo "  Laufzeit; es reduziert nicht proportional das vorherige Surface-Sampling."
    echo ""
}

explain_surface_samples() {
    echo ""
    echo "  SURFACE_SAMPLE_COUNT steuert die Zahl der kamera-basierten Samples"
    echo "  vor Poisson. 5000000 ist der aktuelle Screening-Standard. Weniger"
    echo "  Samples sparen Zeit, koennen aber duenne Buegel und Glasraender schaedigen."
    echo ""
}

explain_mask_levels() {
    echo ""
    echo "  default = urspruengliche SAM-Maske; middle = einmalige 5x5-Erosion;"
    echo "  small = zweimalige Erosion. Der RGB-Loss nutzt MASK_LEVEL, der DN-Loss"
    echo "  NORMAL_MASK_LEVEL und das UV-Baking TEXTURE_MASK_LEVEL."
    echo ""
}

explain_mask_dilation() {
    echo ""
    echo "  Eine RGB-Dilatation kann unsichere Hintergrundpixel in die Geometrie-"
    echo "  supervision einbeziehen. Der aktuelle Standard ist 0 Pixel. Die UV-"
    echo "  Dilatation betrifft nur das Texturbaking und nicht das Coarse-Mesh."
    echo ""
}

explain_sugar_completion() {
    echo ""
    echo "  STOP_AFTER_COARSE_MESH=0 fuehrt Refinement und den kompakten Export aus."
    echo "  RUN_CONSENSUS_CROP=0 bewahrt das unveraenderte Refined-Mesh als Basis."
    echo "  Ein Crop bleibt eine getrennte, optionale Diagnose-/Bereinigungsstufe."
    echo ""
}

explain_run_identity() {
    echo ""
    echo "  SUGAR_RUN_TAG benennt den privaten mask-aware SuGaR-Checkpoint und"
    echo "  sein Ergebnisverzeichnis unter data/sugar_output."
    echo "  SUGAR_MESH_EXPORT_NAME benennt den kompakten Export unter data/06_mesh."
    echo "  Neue Namen bewahren Vergleichslaeufe; vorhandene Namen werden ohne"
    echo "  REPLACE=1 absichtlich nicht ueberschrieben."
    echo ""
}

ask_config_value() {
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

ask_yes_no_default() {
    local prompt="$1"
    local default_value="$2"
    local answer

    while true; do
        read -r -p "$prompt (y/n) [Default: $default_value]: " answer
        answer="${answer:-$default_value}"
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Bitte y oder n eingeben."
                ;;
        esac
    done
}

configure_object_filter() {
    FILTER_MIN_OPACITY="${FILTER_MIN_OPACITY:-0.01}"
    FILTER_BLACK_THRESHOLD="${FILTER_BLACK_THRESHOLD:-0.08}"
    SUGAR_INPUT_ALPHA="${SUGAR_INPUT_ALPHA:-0.999999}"

    if [[ "$AUTOPILOT" == "true" ]]; then
        echo "Autopilot aktiv: Objektfilterung mit min_opacity=$FILTER_MIN_OPACITY und black_threshold=$FILTER_BLACK_THRESHOLD."
        echo "Autopilot aktiv: Setze alle verbleibenden SuGaR-Eingangsopazitaeten auf alpha=$SUGAR_INPUT_ALPHA."
        return
    fi

    echo ""
    echo "=== STS-Objektfilterung und SuGaR-Geometrieeingang ==="
    echo "Vorgabe: min_opacity=$FILTER_MIN_OPACITY, black_threshold=$FILTER_BLACK_THRESHOLD"
    echo "Danach werden alle verbleibenden Opazitaeten automatisch auf alpha=$SUGAR_INPUT_ALPHA gesetzt."
    if ask_yes_no_default "Soll die Objektfilterung mit diesen Vorgabewerten ausgefuehrt werden?" "y"; then
        return
    fi

    ask_config_value FILTER_MIN_OPACITY \
        "Minimale Eingangs-Opazitaet (0 deaktiviert die Opazitaetsfilterung oder EXPLAIN)" \
        "$FILTER_MIN_OPACITY" explain_object_filtering
    ask_config_value FILTER_BLACK_THRESHOLD \
        "Schwarzfilter-Schwelle (oder EXPLAIN)" \
        "$FILTER_BLACK_THRESHOLD" explain_object_filtering
    ask_config_value SUGAR_INPUT_ALPHA \
        "SuGaR-Eingangsopazitaet nach der Filterung (oder EXPLAIN)" \
        "$SUGAR_INPUT_ALPHA" explain_object_filtering
}

configure_sugar_values() {
    REGULARIZATION="${REGULARIZATION:-dn_consistency}"
    COARSE_ITERATIONS="${COARSE_ITERATIONS:-9001}"
    MESH_VERTICES="${MESH_VERTICES:-200000}"
    SURFACE_SAMPLE_COUNT="${SURFACE_SAMPLE_COUNT:-5000000}"
    REFINEMENT_TIME="${REFINEMENT_TIME:-medium}"
    MASK_LEVEL="${MASK_LEVEL:-default}"
    MASK_DILATION_PX="${MASK_DILATION_PX:-0}"
    NORMAL_MASK_LEVEL="${NORMAL_MASK_LEVEL:-default}"
    TEXTURE_MASK_LEVEL="${TEXTURE_MASK_LEVEL:-default}"
    TEXTURE_MASK_DILATION_PX="${TEXTURE_MASK_DILATION_PX:-0}"
    STOP_AFTER_COARSE_MESH="${STOP_AFTER_COARSE_MESH:-0}"
    RUN_CONSENSUS_CROP="${RUN_CONSENSUS_CROP:-0}"
    if [[ "$REGULARIZATION" != "dn_consistency" ]]; then
        COARSE_ITERATIONS=""
    fi
    local default_run_name
    SUGAR_RUN_TAG="${SUGAR_RUN_TAG:-}"
    SUGAR_MESH_EXPORT_NAME="${SUGAR_MESH_EXPORT_NAME:-}"

    if [[ "$AUTOPILOT" == "true" ]]; then
        default_run_name="pipeline_i${ITERATIONS}_c${COARSE_ITERATIONS:-default}_v${MESH_VERTICES}"
        SUGAR_RUN_TAG="${SUGAR_RUN_TAG:-$default_run_name}"
        SUGAR_MESH_EXPORT_NAME="${SUGAR_MESH_EXPORT_NAME:-$default_run_name}"
        echo "Autopilot aktiv: SuGaR-Standard c$COARSE_ITERATIONS, $MESH_VERTICES Vertices, $SURFACE_SAMPLE_COUNT Samples, $REFINEMENT_TIME Refinement."
        echo "Autopilot aktiv: RGB/DN/UV = $MASK_LEVEL/$NORMAL_MASK_LEVEL/$TEXTURE_MASK_LEVEL, Dilatation = $MASK_DILATION_PX/$TEXTURE_MASK_DILATION_PX px."
        echo "Autopilot aktiv: Run-Tag=$SUGAR_RUN_TAG, Mesh-Export=$SUGAR_MESH_EXPORT_NAME."
        return
    fi

    echo ""
    echo "=== Mask-aware SuGaR-Konfiguration ==="
    echo "Vorgabe: $REGULARIZATION, c${COARSE_ITERATIONS:-default}, $MESH_VERTICES Vertices, $SURFACE_SAMPLE_COUNT Samples, $REFINEMENT_TIME Refinement"
    echo "Masken: RGB=$MASK_LEVEL, DN=$NORMAL_MASK_LEVEL, UV=$TEXTURE_MASK_LEVEL; Dilatation RGB/UV=$MASK_DILATION_PX/$TEXTURE_MASK_DILATION_PX px"
    if ask_yes_no_default "Passen die SuGaR-Vorgabewerte fuer diesen Lauf?" "y"; then
        return
    fi

    ask_config_value REGULARIZATION \
        "Regularisierung (sdf/density/dn_consistency oder EXPLAIN)" \
        "$REGULARIZATION" explain_regularization
    if [[ "$REGULARIZATION" == "dn_consistency" ]]; then
        ask_config_value COARSE_ITERATIONS \
            "Coarse-Zielzaehler oder EXPLAIN" "$COARSE_ITERATIONS" explain_coarse_iterations
    else
        COARSE_ITERATIONS=""
    fi
    ask_config_value MESH_VERTICES \
        "Coarse-Mesh-Vertexziel oder EXPLAIN" "$MESH_VERTICES" explain_mesh_vertices
    ask_config_value SURFACE_SAMPLE_COUNT \
        "Surface-Sample-Ziel oder EXPLAIN" "$SURFACE_SAMPLE_COUNT" explain_surface_samples
    ask_config_value REFINEMENT_TIME \
        "Refinement (short/medium/long oder EXPLAIN)" "$REFINEMENT_TIME" explain_refinement_time
    ask_config_value MASK_LEVEL \
        "RGB-Maskenstufe (default/middle/small oder EXPLAIN)" "$MASK_LEVEL" explain_mask_levels
    ask_config_value MASK_DILATION_PX \
        "RGB-Dilatation in Pixeln oder EXPLAIN" "$MASK_DILATION_PX" explain_mask_dilation
    ask_config_value NORMAL_MASK_LEVEL \
        "DN-Maskenstufe (default/middle/small oder EXPLAIN)" "$NORMAL_MASK_LEVEL" explain_mask_levels
    ask_config_value TEXTURE_MASK_LEVEL \
        "UV-Maskenstufe (default/middle/small oder EXPLAIN)" "$TEXTURE_MASK_LEVEL" explain_mask_levels
    ask_config_value TEXTURE_MASK_DILATION_PX \
        "UV-Dilatation in Pixeln oder EXPLAIN" "$TEXTURE_MASK_DILATION_PX" explain_mask_dilation
    ask_config_value STOP_AFTER_COARSE_MESH \
        "Nach Coarse-Mesh stoppen? 1/0 oder EXPLAIN" "$STOP_AFTER_COARSE_MESH" explain_sugar_completion
    ask_config_value RUN_CONSENSUS_CROP \
        "Nachgelagerten Multi-View-Crop ausfuehren? 1/0 oder EXPLAIN" "$RUN_CONSENSUS_CROP" explain_sugar_completion
    default_run_name="pipeline_i${ITERATIONS}_c${COARSE_ITERATIONS:-default}_v${MESH_VERTICES}"
    SUGAR_RUN_TAG="${SUGAR_RUN_TAG:-$default_run_name}"
    SUGAR_MESH_EXPORT_NAME="${SUGAR_MESH_EXPORT_NAME:-$default_run_name}"
    ask_config_value SUGAR_RUN_TAG \
        "SuGaR-Run-Tag oder EXPLAIN" "$SUGAR_RUN_TAG" explain_run_identity
    ask_config_value SUGAR_MESH_EXPORT_NAME \
        "Name des kurzen Mesh-Exports oder EXPLAIN" "$SUGAR_MESH_EXPORT_NAME" explain_run_identity
}

echo "=== Starting Scan-to-BIM Reconstruction Pipeline ==="

# Step 0: GCP Coordinate Preparation (Relative Coordinates)
echo "[Step 0/5] Preparing relative GCP coordinates..."
SKIP_GCP_PREP="false"
while true; do
    if [ -f "data/01_raw/gcp_relative.csv" ]; then
        echo "Hinweis: Es existieren bereits relative GCP-Koordinaten (gcp_relative.csv) im raw-Verzeichnis."
        if [[ "$AUTOPILOT" == "true" ]]; then
            echo "Autopilot mode: reusing existing relative GCP coordinates."
            break
        fi
        read -p "Moechten Sie diese bestehenden relative Koordinaten weiterverwenden? (y/n) [Default: y]: " USE_EXISTING
        USE_EXISTING=${USE_EXISTING:-y}
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            break
        fi
    elif compgen -G "data/01_raw/*.csv" > /dev/null; then
        echo "Gefunden: Mindestens eine CSV-Datei im raw-Verzeichnis ist hochgeladen."
        break
    elif [[ "$AUTOPILOT" == "true" ]]; then
        echo "Autopilot mode: no GCP data found, skipping GCP prep (translation-only fallback will be used at the end)."
        SKIP_GCP_PREP="true"
        break
    fi

    echo "=========================================================="
    echo "SCHRITT ERFORDERLICH: Keine GCP-Passpunktdaten gefunden!"
    echo "Bitte lade mindestens eine CSV-Datei mit GCP-Koordinaten"
    echo "unter data/01_raw/ hoch (z.B. bequem per Drag & Drop im Dashboard)."
    echo "=========================================================="
    read -p "Sobald die CSV-Datei unter 'data/01_raw/' hochgeladen ist, druecke [Enter]..."
done

if [[ "$SKIP_GCP_PREP" != "true" ]]; then
    docker compose run --rm sam3-preprocess python3 /app/src/python/prepare_gcp.py
fi

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
configure_sam3_frame_resolution

# Step 1: Pre-processing (SAM 3 Tracking)
echo "[Step 1/5] Extracting frames and generating SAM 3 masks for: $TEXT_PROMPT ..."
if [[ -n "$SELECTED_VIDEO" ]]; then
    echo "Verwendetes Eingabevideo fuer SAM3: $SELECTED_VIDEO"
    docker compose run --rm -e SAM3_FRAME_MAX_SIDE="$SAM3_FRAME_MAX_SIDE" sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py \
        --prompt "$TEXT_PROMPT" \
        --input-path "/data/01_raw/$(basename "$SELECTED_VIDEO")"
else
    docker compose run --rm -e SAM3_FRAME_MAX_SIDE="$SAM3_FRAME_MAX_SIDE" sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py --prompt "$TEXT_PROMPT"
fi

# Step 2: SfM (COLMAP camera poses & sparse point cloud)
echo "[Step 2/5] Running COLMAP Structure from Motion..."
docker compose run --rm colmap-sfm /app/src/scripts/run_sfm.sh

echo "=========================================================="
echo "BREAKPOINT: Please open the sparse point cloud in CloudCompare"
echo "on the host system. Pick the GCP coordinate points, compute"
echo "the 4x4 transformation matrix."
echo ""
echo "Georeferencing happens at the END of the pipeline (after the"
echo "centerline + GeoJSON). You can provide inputs now or later:"
echo "  - Save the 4x4 matrix to data/04_sfm/matrix.txt, OR drop a"
echo "    screenshot of the matrix as data/01_raw/matrix_screenshot.png"
echo "    (OCR via tesseract runs automatically at the end)."
echo "  - anchor.txt is created by prepare_gcp.py from the GCP CSV."
echo "  - If neither matrix nor anchor is present at the end, a"
echo "    translation-only fallback (UTM 567028.563, 5516784.082, 177)"
echo "    is applied and outputs are named *_fallback_georeferenced."
echo "=========================================================="
if [[ "$AUTOPILOT" == "true" ]]; then
    echo "Autopilot mode: skipping CloudCompare breakpoint (no manual GCP picking)."
    echo "Without matrix.txt/anchor.txt the pipeline will use the translation-only fallback."
else
    read -p "Press [Enter] once the matrix is ready (or to skip and use the fallback)..."
fi

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

# Step 3.5: Prepare the geometry-oriented object input without mutating the
# full-scene STS checkpoint. The remaining object Gaussians receive uniform
# high opacity before they enter the mask-aware SuGaR route.
configure_object_filter
configure_sugar_values

echo "[Step 3.5/5] Preserving the full STS cloud and preparing the standard SuGaR geometry input..."
docker compose run --rm sts-training python3 -c "import os, shutil; base='/data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}'; src=f'{base}/point_cloud.ply'; dst=f'{base}/point_cloud_full_scene.ply'; os.path.exists(src) or (_ for _ in ()).throw(FileNotFoundError(src)); shutil.copy2(src, dst)"

ITERATIONS="$ITERATIONS" \
FILTER_MIN_OPACITY="$FILTER_MIN_OPACITY" \
FILTER_BLACK_THRESHOLD="$FILTER_BLACK_THRESHOLD" \
SUGAR_INPUT_ALPHA="$SUGAR_INPUT_ALPHA" \
./prepare_sugar_input.sh

# Step 4: Run the local mask-aware SuGaR fork using the prepared high-opacity
# object input. It exports refined.ply and refined.obj into a short mesh folder.
echo "[Step 4/5] Running mask-aware SuGaR (Coarse Training -> Mesh Extraction -> Refinement)..."
MASKED_SUGAR_INTERACTIVE=0 \
ITERATIONS="$ITERATIONS" \
REGULARIZATION="$REGULARIZATION" \
COARSE_ITERATIONS="$COARSE_ITERATIONS" \
REFINEMENT_TIME="$REFINEMENT_TIME" \
MESH_VERTICES="$MESH_VERTICES" \
SURFACE_SAMPLE_COUNT="$SURFACE_SAMPLE_COUNT" \
MASK_LEVEL="$MASK_LEVEL" \
MASK_DILATION_PX="$MASK_DILATION_PX" \
NORMAL_MASK_LEVEL="$NORMAL_MASK_LEVEL" \
TEXTURE_MASK_LEVEL="$TEXTURE_MASK_LEVEL" \
TEXTURE_MASK_DILATION_PX="$TEXTURE_MASK_DILATION_PX" \
STOP_AFTER_COARSE_MESH="$STOP_AFTER_COARSE_MESH" \
RUN_CONSENSUS_CROP="$RUN_CONSENSUS_CROP" \
SUGAR_RUN_TAG="$SUGAR_RUN_TAG" \
SUGAR_MESH_EXPORT_NAME="$SUGAR_MESH_EXPORT_NAME" \
FILTERED_PLY="data/05_3dgs/output/point_cloud/iteration_${ITERATIONS}/point_cloud_filtered_opacity999999.ply" \
./run_masked_sugar.sh

# Step 5: Post-Processing & Georeferencing (DGtal & Python & GDAL)
echo "[Step 5/5] Extracting centerline and georeferencing to UTM..."
docker compose run --rm -e INPUT_MESH="/data/06_mesh/${SUGAR_MESH_EXPORT_NAME}/refined.obj" post-processing /app/src/scripts/postprocess.sh

echo "=== Pipeline Completed Successfully. Final outputs saved in data/08_gis/ ==="
