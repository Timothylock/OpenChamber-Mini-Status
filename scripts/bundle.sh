#!/bin/bash
# Assembles the .app bundle around the compiled binary and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

make build >/dev/null
./scripts/make-icon.sh >/dev/null

APP="build/OpenChamber Mini Status.app"
VERSION="${VERSION:-1.0.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/mini-status "$APP/Contents/MacOS/mini-status"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>mini-status</string>
  <key>CFBundleIdentifier</key><string>dev.openchamber.mini-status</string>
  <key>CFBundleName</key><string>OpenChamber Mini Status</string>
  <key>CFBundleDisplayName</key><string>OpenChamber Mini Status</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad hoc signing failed, the app still runs locally"
echo "built: $APP"
