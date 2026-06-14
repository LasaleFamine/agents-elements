#!/bin/bash
# Screenshot just the AgentsElements main window (no full-screen capture).
set -uo pipefail
cd "$(dirname "$0")"
OUT="${1:-shot.png}"
WID=$(swift Tools/windowid.swift 2>/dev/null)
if [[ -z "${WID}" ]]; then
    echo "window not found (is the app running?)" >&2
    exit 1
fi
screencapture -x -o -l"${WID}" "${OUT}"
echo "captured window ${WID} -> ${OUT}"
