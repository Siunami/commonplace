#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Commonplace"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
APP="$BUILD_DIR/$SCHEME.app"
DMG="$BUILD_DIR/$SCHEME.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=N446DBNXUC \
  -quiet

echo "==> Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist

echo "==> Creating DMG..."
# Create a temporary writable DMG, copy the app, then convert to read-only
TEMP_DMG="$BUILD_DIR/tmp.dmg"
hdiutil create -size 200m -fs HFS+ -volname "$SCHEME" "$TEMP_DMG" -ov
MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" -nobrowse | tail -1 | awk '{print $3}')
cp -R "$APP" "$MOUNT_DIR/"
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG"
rm -f "$TEMP_DMG"

echo "==> Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "notarytool-profile" \
  --wait

echo "==> Stapling..."
xcrun stapler staple "$DMG"

echo ""
echo "Done! Ready to upload: $DMG"
ls -lh "$DMG"
