# Handoff — XCUITest-based Screenshot Tests

> Context dump for a new Claude session continuing the work on branch
> `feat/ui-screenshot-tests`. Read this first, then pick up the open tasks.

## Goal

Generate **reproducible documentation screenshots** of the LinakControl menu bar
app (status item icon, popover, preset menu) via an XCUITest target. PNGs land in
`docs/screenshots/` and are referenced from the README. The user prefers this
over an ad-hoc AppleScript+screencapture script because it scales and survives
UI changes.

## Decision: Option 2-C (hybrid, no demo-BLE mocking)

After surveying the codebase, mocking the full BLE handshake was deemed too
expensive (5-step DPG protocol, ~150 LOC of fragile mock code that has to track
protocol changes). The user chose **Option C**: build the UITest infrastructure
now, run it against a **real desk** powered on and paired. If maintaining "real
desk required" becomes painful later, upgrade to a `DemoBLEController` + env-var
mode in a follow-up branch.

**What this means for now:**
- No new production code paths for demo mode
- No env-var gating
- UI tests assume `~/Library/Application Support/LinakControl/config.json` has a
  valid `paired_desk_uuid` and that the desk is on and reachable
- Tests wait for `.connected` state before screenshotting (timeout 10-15s)

## Branch state at handoff

- Branch: `feat/ui-screenshot-tests` (created from `main` at `8f53e23`)
- No code changes committed yet — only this handoff doc
- All scaffolding work is open

## Open tasks (in order)

### 1. A11y identifiers on status item buttons

`LinakControl/Sources/LinakControlKit/UI/MenuBarController.swift`

Set identifiers right after creating each `NSStatusItem`'s button:

```swift
// in setupZone1(), after item.button?.action = ...
item.button?.setAccessibilityIdentifier("linak.menubar.zone1.icon")

// in setupZone2(), after item.button?.action = ...
item.button?.setAccessibilityIdentifier("linak.menubar.zone2.text")
```

(`setAccessibilityIdentifier(_:)` is available on `NSAccessibility` which
`NSButton` conforms to via `NSAccessibilityElement`.)

### 2. UITest target in xcodegen

Add to `project.yml` under `targets:`:

```yaml
LinakControlUITests:
  type: bundle.ui-testing
  platform: macOS
  deploymentTarget: "13.0"
  sources:
    - path: LinakControl/Sources/UITests
  dependencies:
    - target: LinakControl
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.marcusbreiden.LinakControlUITests
      MACOSX_DEPLOYMENT_TARGET: "13.0"
      SWIFT_VERSION: "5.9"
      TEST_TARGET_NAME: LinakControl
      CODE_SIGN_IDENTITY: "-"
      CODE_SIGN_STYLE: Manual
```

Update `schemes.LinakControlApp.test` (probably need to add a `test:` block):

```yaml
schemes:
  LinakControlApp:
    build:
      targets:
        LinakControl: all
        LinakControlUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - LinakControlUITests
    archive:
      config: Release
```

Then `xcodegen generate` and check the pbxproj diff for the `postGenCommand`
sed regression — may need adjustment if xcodegen output drifts.

### 3. UITest source

Create `LinakControl/Sources/UITests/LinakControlScreenshotTests.swift`:

```swift
import XCTest

final class LinakControlScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Wait for menu bar zone 1 to appear (means app finished launching).
        let zone1 = app.statusItems["linak.menubar.zone1.icon"]
        XCTAssertTrue(zone1.waitForExistence(timeout: 10), "zone1 status item never appeared")
        // Give the connect-on-launch task time to reach .connected.
        // (Polling for a "connected"-state UI element is more reliable; see TODO below.)
        Thread.sleep(forTimeInterval: 4)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func test_screenshot_menubar_popover() throws {
        let zone1 = app.statusItems["linak.menubar.zone1.icon"]
        zone1.click()
        Thread.sleep(forTimeInterval: 0.5) // popover open animation
        attach(name: "menubar-popover", screenshot: XCUIScreen.main.screenshot())
    }

    func test_screenshot_preset_menu() throws {
        let zone2 = app.statusItems["linak.menubar.zone2.text"]
        zone2.click()
        Thread.sleep(forTimeInterval: 0.3) // menu open animation
        attach(name: "menubar-preset-menu", screenshot: XCUIScreen.main.screenshot())
        // dismiss
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private func attach(name: String, screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

**Known unknowns / things to validate on the host:**
- Does `app.statusItems["…"]` resolve correctly for our two `NSStatusItem`s?
  If not, try `app.menuBars.children(matching: .statusItem)` or use
  `Accessibility Inspector` to see what identifier path actually reaches them.
- `XCUIScreen.main.screenshot()` captures the entire physical screen at native
  resolution. PNGs will be large (~5-10 MB on Retina). Two options:
  1. Keep as-is, document that user can crop with `sips` later.
  2. Use `app.windows.firstMatch.screenshot()` for the popover — captures only
     the popover window. Try this first; if it fails, fall back to full-screen.
- The popover is an `NSPopover`-hosted `NSPanel`. It may or may not appear in
  `app.windows`. If not, the popover's `contentViewController.view.window` may
  need an a11y identifier set in `MenuBarController.setupZone1`.

### 4. Extract script

`scripts/take-screenshots.sh`:

```bash
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

# Preflight
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
# Xcode 15+: xcrun xcresulttool export attachments --path X --output-path Y
xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$EXPORT_DIR"

echo ">>> copying PNGs into $OUT_DIR/"
# Attachments are named according to XCTAttachment.name set in tests.
# The actual filename layout is something like:
#   $EXPORT_DIR/<test-run-id>/<attachment-name>_<uuid>.png
# We pick the most recent file per logical name.
find "$EXPORT_DIR" -name "*.png" -print0 | while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    # Strip xcresulttool's appended _<uuid> suffix if present.
    clean="$(echo "$base" | sed -E 's/_[0-9A-F-]{36}\.png$/.png/i')"
    cp -v "$f" "$OUT_DIR/$clean"
done

echo ""
echo "Done. Screenshots in $OUT_DIR/:"
ls -lh "$OUT_DIR/"
```

`chmod +x scripts/take-screenshots.sh` after creating.

**Validate on host:** the actual filename pattern from `xcresulttool export
attachments` may differ. Run it once with `set -x` to see the exact paths and
adjust the rename regex if needed.

### 5. README — Screenshots section

Add after `## Quick Start` / before `## Install`:

```md
## Screenshots

<p align="center">
  <img src="docs/screenshots/menubar-popover.png" alt="Menu bar popover" width="320">
  <img src="docs/screenshots/menubar-preset-menu.png" alt="Preset menu" width="320">
</p>

Regenerate from a clean state with the desk powered on and paired:

\`\`\`bash
./scripts/take-screenshots.sh
\`\`\`

This runs the `LinakControlUITests` XCUITest target, which opens each menu bar
zone and captures `XCTAttachment` screenshots. The script extracts the
attachments from the result bundle and writes PNGs into `docs/screenshots/`.

The first run will prompt for **Accessibility permission** for the XCUITest
runner (System Settings → Privacy & Security → Accessibility). Grant it once;
subsequent runs are silent.
```

(Backtick-escape the bash fence properly when actually writing — the markdown
inside this handoff doc uses backslash-escaped fences.)

### 6. Commit / merge / push

Follow the project's established pattern:
1. Commit on `feat/ui-screenshot-tests` (one or more commits — the user prefers
   one logical unit per PR/commit, but multi-commit is fine for clarity).
2. `git checkout main && git merge --ff-only feat/ui-screenshot-tests`
3. `git push origin main`
4. `git branch -d feat/ui-screenshot-tests`

The `main` branch has an edit-blocking PreToolUse hook (`block-main-edits.sh`)
that denies Write/Edit on `main` unless the path is in `.gitignore`. Merge/push
via Bash still works fine — only Write/Edit/NotebookEdit are blocked.

## Constraints / gotchas

- **macOS deployment target is 13.0** per `project.yml`, but README says "14+".
  Pre-existing inconsistency — out of scope.
- **`postGenCommand` sed** in `project.yml` patches the pbxproj for an xcodegen
  2.x quirk with local-package back-references. The UI test target may
  introduce additional similar artifacts; check the diff after first run.
- **Test target needs the host app to be code-signable**. The project already
  uses `CODE_SIGN_IDENTITY: "-"` (ad-hoc) which works for local UITest runs.
- **Status item access in XCUITest**: on macOS 13+ this works for status items
  owned by the app under test, but the test runner needs Accessibility
  permission in System Settings. Document this in the README screenshots
  section.
- **The pre-existing 385 unit tests** in `LinakControl/Tests/LinakControlTests/`
  must not be affected. They run via `swift test` (SPM), not `xcodebuild test`,
  so they're orthogonal — but verify after `xcodegen generate` that they still
  build.

## Open question for the user

The user may want to **crop** screenshots to just the popover region rather than
full-screen. Two approaches:
1. `app.windows.firstMatch.screenshot()` in the test (per-element capture).
2. Post-process with `sips -c` in `take-screenshots.sh`.

Recommend trying #1 first; if popover window isn't queryable, fall back to #2
with hardcoded crop coordinates (the popover content size is 280×400 per
`MenuBarController.setupZone1`).

## After this is done

Remove this handoff file in the same branch — it's transient context, not
durable docs.
