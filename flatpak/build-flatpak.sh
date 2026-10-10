#!/bin/sh
set -eu
cd "$(dirname "$0")"
MANIFEST=com.tee215.VBANDeck.yml
if command -v flatpak-builder >/dev/null 2>&1; then
  flatpak-builder --user --install --force-clean build-dir "$MANIFEST"
elif flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || flatpak info org.flatpak.Builder >/dev/null 2>&1; then
  flatpak run org.flatpak.Builder --user --install --force-clean build-dir "$MANIFEST"
else
  echo "Flatpak Builder is missing. Install: flatpak install --user flathub org.flatpak.Builder" >&2
  exit 1
fi
