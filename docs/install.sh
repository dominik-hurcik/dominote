#!/bin/bash
# Installs the latest Hebdo release into /Applications.
# Usage: curl -fsSL https://hebdo.app/install.sh | bash
#
# Files downloaded with curl do not get the macOS quarantine flag,
# so Gatekeeper does not block this unsigned build.
set -euo pipefail

REPO="dominik-hurcik/hebdo"
URL="https://github.com/$REPO/releases/latest/download/Hebdo.app.zip"
APP="/Applications/Hebdo.app"

if [ "$(uname)" != "Darwin" ]; then
  echo "Hebdo's install.sh is for macOS. On Windows, use install.ps1." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Hebdo..."
curl -fL --progress-bar "$URL" -o "$tmp/Hebdo.app.zip"
ditto -x -k "$tmp/Hebdo.app.zip" "$tmp"
if [ ! -d "$tmp/Hebdo.app" ]; then
  echo "The download did not contain Hebdo.app." >&2
  exit 1
fi

# Close a running copy so it can be replaced. Notes are saved to disk as you type.
osascript -e 'quit app "Hebdo"' >/dev/null 2>&1 || true

SUDO=""
[ -w /Applications ] || SUDO="sudo"
$SUDO rm -rf "$APP"
$SUDO ditto "$tmp/Hebdo.app" "$APP"
$SUDO xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Installed to $APP"
open "$APP"
