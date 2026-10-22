#!/bin/bash
# Copies the app to ~/Applications and launches it. The app registers its own login
# item from Settings, so nothing is written to LaunchAgents from here.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

SOURCE="build/OpenChamber Mini Status.app"
TARGET="$HOME/Applications/OpenChamber Mini Status.app"

mkdir -p "$HOME/Applications"

# Older builds used a hand written LaunchAgent; drop it so only one copy starts.
launchctl bootout "gui/$UID/dev.openchamber.hud" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/dev.openchamber.hud.plist"
launchctl bootout "gui/$UID/dev.openchamber.mini-status" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/dev.openchamber.mini-status.plist"
rm -rf "$HOME/Applications/OpenChamber HUD.app"

pkill -f "mini-status" 2>/dev/null || true
sleep 1

rm -rf "$TARGET"
cp -R "$SOURCE" "$TARGET"

open "$TARGET"

echo "installed: $TARGET"
