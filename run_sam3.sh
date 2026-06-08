#!/bin/bash
set -e

RAW_DIR="data/01_raw"

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

echo "=== Running ONLY SAM 3.1 Pre-processing ==="

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
    read -p "Bitte HuggingFace Token eingeben (fängt mit hf_ an): " INPUT_TOKEN
    if [ ! -z "$INPUT_TOKEN" ]; then
        echo "HF_TOKEN=$INPUT_TOKEN" >> .env
        export HF_TOKEN=$INPUT_TOKEN
        echo "Token erfolgreich in .env gespeichert!"
    fi
fi

read -p "Geben Sie den Begriff ein, der maskiert werden soll (z.B. 'cable', 'pipe'): " TEXT_PROMPT

SELECTED_VIDEO=""
configure_video_input

echo "Starte SAM 3.1 Container..."
echo "Prüfe HuggingFace Identität im Container (sollte deinen HF Benutzernamen anzeigen):"
docker compose run --rm sam3-preprocess hf auth whoami || echo "FEHLER: Der Token ist ungültig oder hat keine Lese-Rechte."

if [[ -n "$SELECTED_VIDEO" ]]; then
    echo "Verwendetes Eingabevideo fuer SAM3: $SELECTED_VIDEO"
    docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py \
        --prompt "$TEXT_PROMPT" \
        --input-path "/data/01_raw/$(basename "$SELECTED_VIDEO")"
else
    docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py --prompt "$TEXT_PROMPT"
fi
