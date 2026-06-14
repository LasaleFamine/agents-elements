#!/bin/bash
# Build AgentsElements and wrap the SwiftPM binary into a .app bundle.
# Works with Command Line Tools only (no full Xcode required).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AgentsElements"
BUNDLE="${APP_NAME}.app"

# Usage: ./build.sh [debug|release] [--dist]
CONFIG="release"
DIST=0
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --dist) DIST=1 ;;
    esac
done

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "error: binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
cp Info.plist "${BUNDLE}/Contents/Info.plist"
cp "${BIN_PATH}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# App icon (run Tools/make-icon.sh to regenerate from IconView).
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
else
    echo "(no AppIcon.icns — run Tools/make-icon.sh)"
fi

# Ad-hoc code signature so macOS is willing to launch the bundle.
echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${BUNDLE}" 2>/dev/null || echo "(codesign skipped)"

echo "==> built ${BUNDLE}"

# Optional: zip the bundle for a GitHub release (preserves bundle metadata via ditto).
if [[ "${DIST}" -eq 1 ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null || echo dev)"
    mkdir -p dist
    ZIP="dist/${APP_NAME}-${VERSION}.zip"
    rm -f "${ZIP}"
    echo "==> packaging ${ZIP}"
    ditto -c -k --keepParent "${BUNDLE}" "${ZIP}"
    echo "==> wrote ${ZIP}"
fi
