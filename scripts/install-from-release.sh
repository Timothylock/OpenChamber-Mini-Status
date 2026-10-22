#!/bin/bash
# Downloads the latest release build and installs it to ~/Applications. curl does not
# set the quarantine flag a browser download would, so the app opens without the
# Gatekeeper "unverified" detour. Builds are ad hoc signed, as usual for a free app.
set -euo pipefail

REPO="Timothylock/OpenChamber-Mini-Status"
APP_NAME="OpenChamber Mini Status"
TARGET="$HOME/Applications/$APP_NAME.app"
API="https://api.github.com/repos/$REPO/releases/latest"

fail() {
  printf 'install failed: %s\n' "$1" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v ditto >/dev/null 2>&1 || fail "ditto is required"

printf 'Looking up the latest release...\n'
url="${MINI_STATUS_INSTALL_URL:-}"
if [ -z "$url" ]; then
  release_json="$(curl -fsSL "$API")" || fail "cannot reach GitHub"
  url="$(printf '%s' "$release_json" | grep -o 'https://[^"]*\.zip' | head -n 1 || true)"
fi
[ -n "$url" ] || fail "the latest release has no zip asset"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'Downloading %s...\n' "$(basename "$url")"
curl -fsSL "$url" -o "$tmp/app.zip" || fail "download failed"
ditto -x -k "$tmp/app.zip" "$tmp/unpacked" || fail "cannot unzip the download"
source_app="$(find "$tmp/unpacked" -maxdepth 1 -name '*.app' -type d | head -n 1)"
[ -n "$source_app" ] || fail "the download contains no app"

# Replace the running copy, if any, so the new one can take over.
pkill -f "$APP_NAME.app/Contents/MacOS/mini-status" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
ditto "$source_app" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

open "$TARGET" || printf 'Installed, but could not launch it. Open %s from Applications.\n' "$TARGET"
printf 'Installed %s\n' "$TARGET"
