#!/bin/bash
set -euo pipefail

# Creates a DMG with a drag-to-Applications layout from an exported .app bundle.
#
# Usage:
#   ./scripts/create-dmg.sh [path-to-Commonplace.app]
#
# If no path is given, looks for the most recent Xcode export on the Desktop.

APP_NAME="Commonplace"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
BUILD_DIR="$(mktemp -d)"
STAGING="${BUILD_DIR}/staging"

# Find the .app
if [[ -n "${1:-}" ]]; then
    APP_PATH="$1"
else
    # Find most recent Xcode export folder on Desktop
    EXPORT_DIR=$(find ~/Desktop -maxdepth 1 -name "Commonplace*" -type d | sort -r | head -1)
    if [[ -z "$EXPORT_DIR" ]]; then
        echo "Error: No Commonplace export found on Desktop. Pass the .app path as an argument."
        exit 1
    fi
    APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: ${APP_PATH} not found"
    exit 1
fi

echo "==> Packaging ${APP_PATH}"

# Output location
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DMG="${OUTPUT_DIR}/${DMG_NAME}"
rm -f "$OUTPUT_DMG"

# Detach any stale volumes from previous runs
hdiutil detach "/Volumes/${VOLUME_NAME}" 2>/dev/null || true

# Create staging folder with app + Applications symlink
mkdir -p "$STAGING"
cp -R "$APP_PATH" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"

echo "==> Creating DMG..."

# Create compressed read-only DMG directly
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$OUTPUT_DMG"

# Clean up
rm -rf "$BUILD_DIR"

# Show result
DMG_SIZE=$(du -sh "$OUTPUT_DMG" | cut -f1)
echo ""
echo "==> Done: ${OUTPUT_DMG} (${DMG_SIZE})"
echo "    Users open this, drag Commonplace to Applications, done."
