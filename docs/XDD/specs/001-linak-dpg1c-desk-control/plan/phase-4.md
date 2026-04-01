---
title: "Phase 4: Menu Bar UI"
status: pending
version: "1.0"
phase: 4
---

# Phase 4: Menu Bar UI

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: mockups.md]` — All approved UI mockups (two-zone menu bar, popover states, movement states)
- `[ref: SDD/Building Block View/Components]` — MenuBarController, PopoverView, PresetDropdown, DeskViewModel
- `[ref: SDD/Cross-Cutting Concepts/User Interface & UX]` — Interaction patterns, state management
- `[ref: SDD/Runtime View/Primary Flow: Preset Quick-Switch]` — Zone 2 → dropdown → preset → move sequence
- `[ref: SDD/Acceptance Criteria/Menu Bar & UI]` — All UI acceptance criteria

**Key Decisions**:
- ADR-6: Two-zone menu bar — two separate NSStatusItems
- ADR-1: Single process — UI directly accesses DeskManager actor (no IPC for UI path)

**Dependencies**:
- Phase 2 complete (DeskManager with all desk operations)
- Phase 3 complete (IPCServer running for event streaming)
- Can run in parallel with Phase 5 (CLI)

---

## Tasks

Builds the complete menu bar user interface. After this phase, the user can control the desk from the menu bar with all popover views working.

- [ ] **T4.1 DeskViewModel** `[activity: build-feature]`

  1. Prime: Read SDD DeskViewModel role and state management `[ref: SDD/Building Block View/Components]` `[ref: SDD/Cross-Cutting Concepts/User Interface & UX/State Management]`
  2. Test: ViewModel exposes @Published properties for: connectionState, heightMM, heightDisplay (formatted string), isMoving, moveDirection, presets (array of 4), activePreset, targetPreset, unit. Methods: `goToPreset(index:)`, `moveUp()`, `moveDown()`, `stop()`, `savePreset(index:)`. ViewModel updates from DeskManager state stream. Height display updates at ≤10 Hz during movement (throttled).
  3. Implement: Create `Sources/UI/DeskViewModel.swift` as `@Observable` class (macOS 14+) or `ObservableObject`. Subscribe to DeskManager's state stream. Throttle height updates using `Task.sleep` or Combine `.throttle`. Format height display using HeightConverter.
  4. Validate: Unit tests: mock DeskManager, verify ViewModel updates on state changes; verify throttling; verify formatted display strings
  5. Success: ViewModel reflects desk state changes within 100ms `[ref: SDD/Quality Requirements/Performance]`

- [ ] **T4.2 MenuBarController — Two-Zone Setup** `[activity: build-feature]`

  1. Prime: Read mockups for menu bar zones and SDD two-zone design `[ref: mockups.md/Menu Bar — Two Zones]` `[ref: SDD/Architecture Decisions/ADR-6]`
  2. Test: Two NSStatusItems created: Zone 1 (desk icon, fixed length) and Zone 2 (preset text, variable length). Zone 1 click toggles NSPopover. Zone 2 click shows NSMenu with 4 preset items. Zone 1 icon changes based on connection state (solid = connected, dimmed+slash = disconnected). Zone 2 text shows active preset number + height or "—" if disconnected.
  3. Implement: Create `Sources/UI/MenuBarController.swift`. Create two `NSStatusItem` instances via `NSStatusBar.system.statusItem(withLength:)`. Zone 1: configure button with desk glyph SF Symbol, attach NSPopover. Zone 2: configure button with preset text, attach NSMenu. Bind both to DeskViewModel.
  4. Validate: Visual test: two items appear in menu bar; Zone 1 toggles popover; Zone 2 shows menu
  5. Success: Two menu bar zones with correct click behavior `[ref: SDD/Acceptance Criteria/Menu Bar & UI]` `[ref: PRD/Feature 3/AC-1,2]`

- [ ] **T4.3 PresetDropdownView (Zone 2 Menu)** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockups for preset quick-switch dropdown `[ref: mockups.md/Preset Quick-Switch Dropdown]`
  2. Test: NSMenu shows 4 items, each with preset number and height. Active preset has checkmark. During movement, target preset shows "→" indicator. Clicking a preset calls `DeskViewModel.goToPreset(index:)`. Unset presets show "—" for height.
  3. Implement: Create `Sources/UI/PresetDropdownView.swift`. Build NSMenu dynamically from ViewModel presets. Update menu items on state changes. Handle menu item actions.
  4. Validate: Test: menu shows correct items; checkmark on active; click triggers goToPreset
  5. Success: Preset switch is a 2-click operation from menu bar `[ref: mockups.md/Preset Quick-Switch Dropdown]`

- [ ] **T4.4 PopoverView — Main View** `[activity: build-feature]`

  1. Prime: Read mockups for all popover states `[ref: mockups.md/Main Popover — Connected, Idle]` `[ref: mockups.md/Main Popover — During Movement]` `[ref: mockups.md/Main Popover — Disconnected]` `[ref: mockups.md/Main Popover — Desk Busy]`
  2. Test: Popover shows height display (hero element, large font) at top. Shows directional indicator (↑/↓) during movement. Shows "Disconnected — Reconnecting..." when disconnected. Shows "Desk Busy" with guidance when desk is occupied. Contains MovementControlView and PresetGridView. Contains footer with Settings button and profile name.
  3. Implement: Create `Sources/UI/PopoverView.swift` as SwiftUI view. Bind to DeskViewModel. Switch content based on connectionState. Host in NSPopover (280pt wide).
  4. Validate: SwiftUI preview for each state (connected idle, moving, disconnected, busy)
  5. Success: Popover displays correct state for all connection scenarios `[ref: PRD/Feature 3/AC-1,2,3,4]`

- [ ] **T4.5 MovementControlView (Up/Down Buttons)** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockups for up/down buttons and PRD movement requirements `[ref: mockups.md/Main Popover — Auto Mode Up]` `[ref: PRD/Feature 4]` `[ref: SDD/Cross-Cutting Concepts/User Interface & UX/Interaction Design]`
  2. Test: Manual mode: button shows "(hold)" indicator; press-and-hold for ≥150ms triggers moveUp/moveDown; release triggers stop; taps <150ms are ignored. Auto mode: button shows "(auto)" indicator; tap triggers moveUp/moveDown (auto); button transforms to "Stop" while moving; second tap triggers stop. Dimmed when disconnected. Shows "Desk at max/min" tooltip at limits.
  3. Implement: Create `Sources/UI/MovementControlView.swift`. Use `.onLongPressGesture(minimumDuration: 0.15)` for manual mode hold detection. Use `.onTapGesture` for auto mode. Show mode indicator text below arrow. Transform to Stop button during auto movement.
  4. Validate: Test hold timing; mode switching; disabled state
  5. Success: Hold threshold of 150ms works; stop within 500ms `[ref: PRD/Feature 4/AC-1,2,3,4,5]`

- [ ] **T4.6 PresetGridView (2x2 Grid in Popover)** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockups for preset grid `[ref: mockups.md/Main Popover — Connected, Idle]` `[ref: PRD/Feature 5]`
  2. Test: 2x2 grid shows 4 preset buttons. Each shows index number and height (e.g., "1 / 73.0 cm"). Active preset highlighted with accent color. Target preset pulses during movement. Unset presets show "—". Tapping a preset calls goToPreset. Tapping an unset preset shows toast message.
  3. Implement: Create `Sources/UI/PresetGridView.swift`. LazyVGrid with 2 columns. Bind to ViewModel presets, activePreset, targetPreset. Highlight logic from SDD preset matching.
  4. Validate: Preview all states: all set, some unset, one active, one target
  5. Success: Preset buttons show correct heights and highlight active `[ref: PRD/Feature 5/AC-1,3,4]`

- [ ] **T4.7 App Entry Point** `[activity: build-feature]`

  1. Prime: Read SDD app lifecycle `[ref: SDD/Solution Strategy]` `[ref: SDD/Deployment View]`
  2. Test: App starts with `LSUIElement = YES` (no Dock icon). Creates DeskManager, IPCServer, MenuBarController on launch. If paired desk exists in config, auto-connects on launch. If no paired desk, shows first-run view (Phase 6 — for now just show popover).
  3. Implement: Create `Sources/App/DeskControlApp.swift` with `@main`. Initialize DeskManager, start IPCServer, create MenuBarController. Read config for paired desk. Trigger auto-connect if paired.
  4. Validate: App launches without Dock icon; menu bar items appear; auto-connects if configured
  5. Success: App runs as invisible background process with menu bar presence `[ref: PRD/Feature 8/AC-1]` `[ref: PRD/Feature 1/AC-3]`

- [ ] **T4.8 Phase Validation** `[activity: validate]`

  - Run all Phase 4 tests. Visual verification: app launches, two menu bar zones appear, popover opens, preset dropdown works, up/down buttons respond to hold and tap. SwiftLint clean.
