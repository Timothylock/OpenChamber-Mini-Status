#!/bin/bash
# Stops the widget and removes the installed copy, login item and saved settings.
set -euo pipefail

TARGET="$HOME/Applications/OpenChamber Mini Status.app"
AGENT="$HOME/Library/LaunchAgents/dev.openchamber.mini-status.plist"

pkill -f "mini-status" 2>/dev/null || true
launchctl bootout "gui/$UID/dev.openchamber.mini-status" 2>/dev/null || true
rm -f "$AGENT"
rm -rf "$TARGET"

defaults delete dev.openchamber.mini-status 2>/dev/null || true

echo "removed: $TARGET"
echo "if it still shows in System Settings > General > Login Items, remove it there"
