#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.2.1"
NAME="VBANDeck"

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: Node.js/npm is required to build the Decky frontend."
  echo "Build on a PC with Node.js 16.14+ or install Node.js in your dev environment."
  exit 1
fi

# Use pnpm 9 without requiring a global install.
if command -v pnpm >/dev/null 2>&1; then
  PNPM=(pnpm)
else
  PNPM=(npx --yes pnpm@9)
fi

echo "==> Installing frontend dependencies"
"${PNPM[@]}" install

echo "==> Building Decky frontend"
"${PNPM[@]}" run build

mkdir -p bin

if pkg-config --exists libpipewire-0.3 2>/dev/null; then
  echo "==> Building native PipeWire sender on host"
  make -C backend
  cp backend/out/vban-pipewire bin/vban-pipewire
elif flatpak info org.gnome.Sdk//49 >/dev/null 2>&1; then
  echo "==> Host PipeWire headers missing; building sender inside GNOME SDK 49"
  ABS="$(pwd)"
  flatpak run --command=sh --filesystem="$ABS" org.gnome.Sdk//49 -c \
    "cd '$ABS/backend' && mkdir -p out && cc -O2 -std=gnu11 -Wall -Wextra src/vban-pipewire.c -o out/vban-pipewire \$(pkg-config --cflags --libs libpipewire-0.3) -pthread"
  cp backend/out/vban-pipewire bin/vban-pipewire
else
  echo "ERROR: libpipewire development files are unavailable."
  echo "Install a development environment with libpipewire-0.3 headers, or GNOME SDK 49 Flatpak."
  exit 1
fi
chmod +x bin/vban-pipewire

if [ ! -f dist/index.js ]; then
  echo "ERROR: frontend build did not produce dist/index.js"
  exit 1
fi

rm -rf release
mkdir -p release/VBANDeck/{dist,bin,assets}
cp dist/index.js release/VBANDeck/dist/index.js
cp bin/vban-pipewire release/VBANDeck/bin/vban-pipewire
cp main.py plugin.json package.json LICENSE README.md release/VBANDeck/
cp ../assets/vban-deck-logo.svg release/VBANDeck/assets/vban-deck-logo.svg

mkdir -p release
(
  cd release
  rm -f "${NAME}-${VERSION}.zip"
  zip -qr "${NAME}-${VERSION}.zip" VBANDeck
)

echo
echo "Built: $(pwd)/release/${NAME}-${VERSION}.zip"
echo "Install that ZIP in Decky Loader using Install Plugin from ZIP/URL (developer mode if required)."
