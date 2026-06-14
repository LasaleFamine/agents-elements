#!/bin/bash
# Render the product tour (from demo data — no real user data) and encode it into
# docs/demo.mp4 (social) and docs/demo.gif (README). Requires ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v ffmpeg >/dev/null || { echo "error: ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

echo "==> building (release)"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/AgentsElements"

FRAMES="$(mktemp -d)/frames"
mkdir -p "$FRAMES"
echo "==> rendering tour frames"
"$BIN" --render-tour "$FRAMES"

FPS=13
mkdir -p docs

echo "==> encoding docs/demo.mp4"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png" \
  -vf "scale=1100:-2:flags=lanczos,format=yuv420p" \
  -c:v libx264 -crf 20 -preset slow -movflags +faststart docs/demo.mp4

echo "==> encoding docs/demo.gif (two-pass palette, README-sized)"
GIF_FPS=10; GIF_W=640
PAL="$(mktemp).png"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png" \
  -vf "fps=$GIF_FPS,scale=$GIF_W:-1:flags=lanczos,palettegen=max_colors=100:stats_mode=diff" "$PAL"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png" -i "$PAL" \
  -lavfi "fps=$GIF_FPS,scale=$GIF_W:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" \
  docs/demo.gif

rm -rf "$(dirname "$FRAMES")" "$PAL"
echo "==> done:"
ls -lh docs/demo.mp4 docs/demo.gif
