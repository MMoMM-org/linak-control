---
title: "Phase 6: First-Run, Settings & Polish"
status: pending
version: "1.0"
phase: 6
---

# Phase 6: First-Run, Settings & Polish

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: mockups.md/First-Run — Welcome]` — Welcome screen mockup
- `[ref: mockups.md/First-Run — Scanning]` — Scanning view with signal strength
- `[ref: mockups.md/First-Run — Connected]` — Setup complete screen
- `[ref: mockups.md/Settings Panel]` — Full settings panel mockup
- `[ref: PRD/Feature 7]` — First-run experience acceptance criteria
- `[ref: PRD/Feature 9]` — Settings configuration acceptance criteria
- `[ref: PRD/Feature 12]` — Global hotkeys (Should Have)
- `[ref: PRD/Feature 13]` — Notification Center integration (Should Have)
- `[ref: SDD/Architecture Decisions/ADR-5]` — SMAppService for login item

**Key Decisions**:
- ADR-5: SMAppService for login item registration

**Dependencies**:
- Phase 4 complete (MenuBarController, PopoverView, DeskViewModel)
- Phase 5 complete (CLI provides alternative verification path)

---

## Tasks

Completes the user experience with first-run onboarding, settings panel, and "Should Have" features (notifications, hotkeys, login item). After this phase, the app is feature-complete.

- [ ] **T6.1 FirstRunView — Welcome & Scanning** `[activity: build-feature]`

  1. Prime: Read first-run mockups and PRD acceptance criteria `[ref: mockups.md/First-Run — Welcome]` `[ref: mockups.md/First-Run — Scanning]` `[ref: PRD/Feature 7]`
  2. Test: Welcome screen shows on launch when no paired desk in config. "Get Started" button triggers BLE scan. macOS Bluetooth permission dialog appears (requires `NSBluetoothAlwaysUsageDescription`). Scanning view shows discovered desks with name and signal strength bars. Desks appear within 10 seconds.
  3. Implement: Create `Sources/UI/FirstRunView.swift`. States: welcome → scanning → selecting → connecting → complete. Welcome shows app name, description, "Get Started" button. Scanning shows spinner + list of discovered desks with RSSI-based signal bars. Bind to DeskViewModel's discovered desks stream.
  4. Validate: SwiftUI preview for each state; verify Bluetooth permission prompt fires
  5. Success: First-run guides from launch to scan within 2 taps `[ref: PRD/Feature 7/AC-1,2,3]`

- [ ] **T6.2 FirstRunView — Connect & Complete** `[activity: build-feature]`

  1. Prime: Read first-run completion mockup `[ref: mockups.md/First-Run — Connected]` `[ref: PRD/Feature 7/AC-4,5]`
  2. Test: Selecting a desk triggers connection + handshake. Connection success shows "Connected!" with current height and desk name. Tip about saving presets is displayed. "Done" button dismisses first-run and shows normal popover. Config is updated with paired desk UUID and name. Subsequent launches skip first-run and auto-connect.
  3. Implement: Extend FirstRunView with connecting (spinner) and complete states. On success, call `ConfigStore.savePairedDesk()`. Set a flag to skip first-run on next launch.
  4. Validate: Full flow: welcome → scan → select → connect → done → normal popover
  5. Success: Setup complete within 30 seconds; future launches auto-connect `[ref: PRD/Feature 7/AC-4,5]` `[ref: PRD/Feature 1/AC-3]`

- [ ] **T6.3 SettingsView** `[activity: build-feature]`

  1. Prime: Read settings panel mockup and PRD settings requirements `[ref: mockups.md/Settings Panel]` `[ref: PRD/Feature 9]`
  2. Test: Settings opens as push navigation within popover (Back button returns to main view). Display unit: segmented control (cm/inch), changes update all displays immediately. Movement mode: segmented controls for up and down (hold/auto). Presets section: shows 4 presets with height and "Save current" button for each. Connection section: shows paired desk name with "Forget & Re-scan" button. Start at login toggle. About section with version and Quit button.
  3. Implement: Create `Sources/UI/SettingsView.swift`. Bind to DeskViewModel and ConfigStore. Unit change calls `DeskManager.updateSettings()`. Preset save calls `DeskManager.savePreset()`. Forget calls `DeskManager.disconnect()` + clears config.
  4. Validate: Each setting persists via ConfigStore; unit change reflects immediately in popover height
  5. Success: Settings changes persist across restarts; unit change is instant `[ref: PRD/Feature 9/AC-1,2,3,4]`

- [ ] **T6.4 Login Item (SMAppService)** `[activity: build-feature]`

  1. Prime: Read SDD SMAppService approach `[ref: SDD/Architecture Decisions/ADR-5]` `[ref: SDD/Deployment View]`
  2. Test: Toggle "Start at login" in settings calls `SMAppService.mainApp.register()` / `.unregister()`. Setting persists in config. App appears in System Settings > Login Items when enabled.
  3. Implement: Add SMAppService calls to settings toggle handler. Store preference in ConfigStore.
  4. Validate: Toggle on → app in login items; toggle off → app removed; survives restart
  5. Success: App starts at login when enabled `[ref: PRD/Feature 8/AC-1]`

- [ ] **T6.5 Notification Center Integration** `[activity: build-feature]`

  1. Prime: Read PRD notification requirements `[ref: PRD/Feature 13]`
  2. Test: Unexpected disconnect → macOS notification "Desk Disconnected — Reconnecting...". Successful reconnect → notification "Desk Connected". Notifications use UNUserNotificationCenter. No notification on intentional disconnect (user-initiated).
  3. Implement: Add notification posting to DeskManager's connection state observer. Request notification permission on first-run. Only notify on unexpected state changes (not during scanning or intentional disconnect).
  4. Validate: Test notification posted on disconnect; not posted on intentional disconnect; permission request works
  5. Success: Connection state changes produce macOS notifications `[ref: PRD/Feature 13/AC-1,2]`

- [ ] **T6.6 Global Hotkeys** `[activity: build-feature]`

  1. Prime: Read PRD hotkey requirements `[ref: PRD/Feature 12]`
  2. Test: When enabled in settings, Ctrl+Opt+1-4 activates presets without opening popover. Ctrl+Opt+Up/Down moves desk. Hotkeys can be enabled/disabled in settings. Hotkeys do not conflict with system shortcuts.
  3. Implement: Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` or Carbon `RegisterEventHotKey` API. Register configurable key combos. Route to DeskManager methods.
  4. Validate: Test hotkey registration; preset activation without popover; enable/disable toggle
  5. Success: Keyboard shortcuts control desk without opening popover `[ref: PRD/Feature 12/AC-1,2]`

- [ ] **T6.7 Phase Validation** `[activity: validate]`

  - Run all Phase 6 tests. Full flow: first-run → pair → use → settings → quit → relaunch → auto-connect. Verify notifications fire on disconnect/reconnect. Verify hotkeys work. Verify login item registration. SwiftLint clean.
