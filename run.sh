#!/bin/bash
# run.sh -- Build and launch LinakControl.app in debug mode.
# Kills any running instance first so the new build takes effect.
# Pass --clean to wipe persisted config (first-run / scanning mode).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LinakControl"
CONFIG_DIR="$HOME/Library/Application Support/LinakControl"
CLEAN=false

for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Kill running instance if any
if pgrep -xq "$APP_NAME"; then
    echo "Stopping running $APP_NAME..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.5
fi

# Optionally clear persisted config so the app starts in first-run mode.
if [ "$CLEAN" = true ] && [ -d "$CONFIG_DIR" ]; then
    echo "Clearing config at $CONFIG_DIR..."
    rm -rf "$CONFIG_DIR"
fi

echo "Building $APP_NAME (debug)..."
cd "$SCRIPT_DIR"
make xcode-build-debug 2>&1 | tail -5

# Resolve the .app path from DerivedData
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/LinakControl-*/Build/Products/Debug -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in DerivedData."
    exit 1
fi

echo "Launching $APP_PATH"
open "$APP_PATH"
