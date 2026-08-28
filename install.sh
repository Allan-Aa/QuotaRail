#!/bin/bash
# One-command install: builds a universal binary, installs it to
# /Applications, and launches it. Works on both Apple Silicon and Intel Macs.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Install Xcode or the Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

./build-app.sh

DEST="/Applications/Throttle.app"
if [ -w "/Applications" ]; then
  rm -rf "$DEST"
  cp -R "Throttle.app" "$DEST"
else
  echo "No write access to /Applications, installing to ~/Applications instead."
  mkdir -p "$HOME/Applications"
  DEST="$HOME/Applications/Throttle.app"
  rm -rf "$DEST"
  cp -R "Throttle.app" "$DEST"
fi

echo ""
echo "Installed to $DEST"
echo "Launching…"
open "$DEST"

echo ""
echo "Done. Look for the gauge icon in your menu bar and the floating pill on"
echo "the right edge of your screen. Click either one, then the gear icon, to"
echo "turn on \"Launch at login\" so it starts automatically from now on."
