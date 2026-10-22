#!/bin/bash
# Renders the icon and packs the sizes the Dock, Finder and Finder previews ask for.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swiftc -O scripts/make-icon.swift -o build/make-icon
./build/make-icon build/icon-1024.png

SET=build/AppIcon.iconset
rm -rf "$SET"
mkdir -p "$SET"

for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" build/icon-1024.png --out "build/icon-${size}.png" >/dev/null
done

cp build/icon-16.png "$SET/icon_16x16.png"
cp build/icon-32.png "$SET/icon_16x16@2x.png"
cp build/icon-32.png "$SET/icon_32x32.png"
cp build/icon-64.png "$SET/icon_32x32@2x.png"
cp build/icon-128.png "$SET/icon_128x128.png"
cp build/icon-256.png "$SET/icon_128x128@2x.png"
cp build/icon-256.png "$SET/icon_256x256.png"
cp build/icon-512.png "$SET/icon_256x256@2x.png"
cp build/icon-512.png "$SET/icon_512x512.png"
cp build/icon-1024.png "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o build/AppIcon.icns
echo "icon: build/AppIcon.icns"
