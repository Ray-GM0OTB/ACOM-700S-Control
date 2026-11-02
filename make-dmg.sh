#!/bin/bash
# Packages dist/ACOM Control.app into dist/ACOM-Control.dmg (drag-to-Applications layout).
# Run build-app.sh first. macOS only (uses hdiutil).
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/ACOM Control.app"
DMG="dist/ACOM-Control.dmg"
STAGE="$(mktemp -d)/ACOM Control"
[ -d "$APP" ] || { echo "Build the app first: ./build-app.sh"; exit 1; }

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp icon/AppIcon.icns "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true      # custom volume icon, if Xcode tools present

rm -f "$DMG"
hdiutil create -volname "ACOM Control" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --sign - "$DMG" || true
echo "Built: $DMG"
