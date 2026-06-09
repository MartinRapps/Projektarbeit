#!/bin/bash
# Starte das Pipeline Dashboard
# Nutzung: bash ui/start.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/server.py"
