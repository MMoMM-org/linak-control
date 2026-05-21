#!/bin/bash
# scripts/take-screenshots.sh -- regenerate documentation screenshots.
# Runs the LinakControlUITests scheme, exports XCUITest attachments to docs/screenshots/.
# Requires a real desk powered on and paired (no demo BLE mode).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

RESULT_BUNDLE="/tmp/linak-screenshots.xcresult"
OUT_DIR="docs/screenshots"
EXPORT_DIR="$(mktemp -d)"

for tool in xcodebuild xcodegen xcrun; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Error: $tool not found." >&2
        exit 1
    }
done

mkdir -p "$OUT_DIR"
rm -rf "$RESULT_BUNDLE"

echo ">>> regenerating Xcode project"
xcodegen generate

echo ">>> running UI test target"
xcodebuild test \
    -project LinakControl.xcodeproj \
    -scheme LinakControlApp \
    -only-testing:LinakControlUITests \
    -resultBundlePath "$RESULT_BUNDLE" \
    -destination 'platform=macOS' \
    2>&1 | tail -40

echo ">>> exporting attachments"
xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$EXPORT_DIR"

echo ">>> copying PNGs into $OUT_DIR/"
# Attachment filenames from xcresulttool look like:
#   $EXPORT_DIR/<test-run-id>/<attachment-name>_<uuid>.png
# Strip the appended _<uuid> suffix so README links remain stable.
find "$EXPORT_DIR" -name "*.png" -print0 | while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    clean="$(echo "$base" | sed -E 's/_[0-9A-F-]{36}\.png$/.png/i')"
    cp -v "$f" "$OUT_DIR/$clean"
done

echo ""
echo "Done. Screenshots in $OUT_DIR/:"
ls -lh "$OUT_DIR/"
