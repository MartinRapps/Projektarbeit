#!/bin/bash
set -e

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

echo "Starte SAM 3.1 Container..."
echo "Prüfe HuggingFace Identität im Container (sollte deinen HF Benutzernamen anzeigen):"
docker compose run --rm sam3-preprocess hf auth whoami || echo "FEHLER: Der Token ist ungültig oder hat keine Lese-Rechte."

docker compose run --rm sam3-preprocess python3 /app/src/python/extract_masks_notebook_flow.py --prompt "$TEXT_PROMPT"
