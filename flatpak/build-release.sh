#!/bin/sh
set -eu

cd "$(dirname "$0")"
APP_ID="com.tee215.VBANDeck"
BRANCH="stable"
MANIFEST="com.tee215.VBANDeck.yml"
BUILD_DIR="build-release"
REPO_DIR="repo"
DIST_DIR="dist"
BUNDLE="$DIST_DIR/VBANDeck-0.2.1.flatpak"

mkdir -p "$DIST_DIR"
rm -rf "$BUILD_DIR" "$REPO_DIR"

if ! command -v flatpak >/dev/null 2>&1; then
  echo "Flatpak is required." >&2
  exit 1
fi

# Build and export to a local repository. Support either native flatpak-builder
# or the org.flatpak.Builder Flatpak used on Steam Deck.
if command -v flatpak-builder >/dev/null 2>&1; then
  flatpak-builder --force-clean --repo="$REPO_DIR" --default-branch="$BRANCH" "$BUILD_DIR" "$MANIFEST"
elif flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || flatpak info org.flatpak.Builder >/dev/null 2>&1; then
  flatpak run org.flatpak.Builder --force-clean --repo="$REPO_DIR" --default-branch="$BRANCH" "$BUILD_DIR" "$MANIFEST"
else
  echo "Flatpak Builder is missing." >&2
  echo "On Steam Deck: flatpak install --user flathub org.flatpak.Builder" >&2
  exit 1
fi

# Create the shareable single-file installer.
flatpak build-bundle "$REPO_DIR" "$BUNDLE" "$APP_ID" "$BRANCH"

echo
echo "Release created: $BUNDLE"
echo "Share that .flatpak file. After installation, VBAN Deck appears in the application launcher."
