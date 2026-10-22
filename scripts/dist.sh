#!/bin/bash
# Builds the drag-to-Applications artifacts: a disk image and a zip of the .app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

VERSION="${VERSION:-1.0.0}"
APP="build/OpenChamber Mini Status.app"
NAME="OpenChamber-Mini-Status-$VERSION"

rm -rf dist
mkdir -p dist

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "OpenChamber Mini Status" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "dist/$NAME.dmg" >/dev/null

rm -rf "$STAGE"

ditto -c -k --keepParent "$APP" "dist/$NAME.zip"

echo "dist/$NAME.dmg"
echo "dist/$NAME.zip"
