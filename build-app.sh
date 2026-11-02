#!/bin/bash
# Builds "ACOM Control.app" in ./dist. Needs Xcode or the Xcode Command Line Tools
# (xcode-select --install). Produces a universal (Apple silicon + Intel) app.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/ACOM Control.app"
# Universal (Apple silicon + Intel) needs full Xcode; fall back to this Mac's own
# architecture when only the Command Line Tools are installed.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ACOMControl"
else
  echo "Universal build unavailable (needs Xcode) - building for this Mac only."
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/ACOMControl"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ACOMControl"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ACOM Control</string>
    <key>CFBundleDisplayName</key><string>ACOM Control</string>
    <key>CFBundleIdentifier</key><string>uk.gm0otb.acomcontrol</string>
    <key>CFBundleExecutable</key><string>ACOMControl</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Apple silicon will launch it locally.
codesign --force --deep --sign - "$APP"
touch "$APP"   # nudge Finder to refresh the icon
echo "Built: $APP"
echo "First launch: right-click the app → Open (it isn't notarised)."
