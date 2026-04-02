#!/bin/bash
# install.sh -- Build LinakControl.app in release mode and install to /Applications.
# The app runs as a menu bar utility (no Dock icon).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LinakControl"
INSTALL_DIR="${1:-/Applications}"

echo "Building $APP_NAME (release)..."
cd "$SCRIPT_DIR"
make xcode-build 2>&1 | tail -5

# Resolve the .app path from DerivedData
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/LinakControl-*/Build/Products/Release -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in DerivedData."
    exit 1
fi

# Remove old installation if present
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing old $INSTALL_DIR/$APP_NAME.app..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

echo "Installing to $INSTALL_DIR/$APP_NAME.app..."
cp -R "$APP_PATH" "$INSTALL_DIR/"

echo ""
echo "Done. Launch with:"
echo "  open $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "Or add to Login Items in System Settings for auto-start."
