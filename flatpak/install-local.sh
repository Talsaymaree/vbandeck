#!/bin/sh
set -eu
cd "$(dirname "$0")"
VERSION="$(tr -d '\r\n' < VERSION)"
BUNDLE="dist/VBANDeck-$VERSION.flatpak"
if [ ! -f "$BUNDLE" ]; then
  echo "Missing $BUNDLE. Run ./build-release.sh first." >&2
  exit 1
fi
flatpak install --user --reinstall "$BUNDLE"
echo "Installed. Launch VBAN Deck from the application menu."
