#!/bin/bash
# Render the app icon (IconView) and slice it into AppIcon.icns.
# Requires the built binary + sips + iconutil (all ship with macOS Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> building (release)"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/AgentsElements"

SRC="$(mktemp -t agentselements_icon).png"
echo "==> rendering 1024² icon"
"${BIN}" --render-icon "${SRC}"

ICONSET="AppIcon.iconset"
rm -rf "${ICONSET}"; mkdir "${ICONSET}"
gen() { sips -z "$1" "$1" "${SRC}" --out "${ICONSET}/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "${SRC}" "${ICONSET}/icon_512x512@2x.png"   # 1024

iconutil -c icns "${ICONSET}" -o AppIcon.icns
rm -rf "${ICONSET}" "${SRC}"
echo "==> built AppIcon.icns"
