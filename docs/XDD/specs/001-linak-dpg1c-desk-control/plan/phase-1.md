---
title: "Phase 1: Project Foundation & BLE Protocol"
status: pending
version: "1.0"
phase: 1
---

# Phase 1: Project Foundation & BLE Protocol

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: SDD/Constraints]` — Platform, language, signing requirements
- `[ref: SDD/Directory Map]` — Full project structure
- `[ref: SDD/Glossary/BLE UUIDs]` — All service and characteristic UUIDs
- `[ref: SDD/Glossary/BLE Commands]` — Command byte sequences
- `[ref: SDD/Implementation Examples/Height Notification Parsing]` — Byte layout and conversion
- `[ref: SDD/Data Storage Changes]` — config.json and profiles.json schemas

**Key Decisions**:
- ADR-7: No SPM package — shared code via framework target or file inclusion
- ADR-1: Single process — one app target + one CLI target

**Dependencies**:
- None — this is the foundation phase

---

## Tasks

Establishes the Xcode project skeleton, BLE protocol encoding/decoding, and configuration persistence. All subsequent phases build on these foundations.

- [ ] **T1.1 Xcode Project Skeleton** `[activity: build-feature]`

  1. Prime: Read SDD Directory Map for full project structure `[ref: SDD/Directory Map]`
  2. Test: Project builds for macOS (Apple Silicon); both targets (DeskControl app, deskctl CLI) compile; Info.plist contains `NSBluetoothAlwaysUsageDescription` and `LSUIElement = YES`
  3. Implement: Create `LinakControl.xcodeproj` with two targets: `DeskControl` (macOS App) and `deskctl` (Command Line Tool). Add Info.plist with Bluetooth usage description. Configure ad-hoc code signing (`CODE_SIGN_IDENTITY="-"`). Add SwiftLint config. Add Swift ArgumentParser dependency for CLI target.
  4. Validate: `xcodebuild -scheme DeskControl -configuration Debug` succeeds; `xcodebuild -scheme deskctl` succeeds; SwiftLint passes
  5. Success: Both targets build clean on macOS `[ref: SDD/Deployment View]`

- [ ] **T1.2 BLE Characteristic Constants** `[activity: domain-modeling]` `[parallel: true]`

  1. Prime: Read SDD BLE UUID table and command reference `[ref: SDD/Glossary/BLE UUIDs]` `[ref: SDD/Glossary/BLE Commands]`
  2. Test: All 10 characteristic UUIDs are defined; CBUUID instances match expected strings; command byte arrays match documented values
  3. Implement: Create `Sources/BLE/DeskCharacteristics.swift` with CBUUID constants for all services and characteristics. Create command enums with raw byte data for: moveUp, moveDown, stop, wakeUp, preflight, heartbeat, getCapabilities, readPreset(1-4), savePreset(1-4)
  4. Validate: Unit tests verify UUID strings and command byte sequences
  5. Success: All BLE protocol constants are type-safe and documented `[ref: SDD/Glossary/BLE Commands]`

- [ ] **T1.3 DeskProtocol — Encoding & Decoding** `[activity: domain-modeling]` `[parallel: true]`

  1. Prime: Read SDD height parsing example and move-to encoding `[ref: SDD/Implementation Examples/Height Notification Parsing]` `[ref: SDD/Implementation Examples/Move-to-Preset Control Loop]`
  2. Test: `parseHeightNotification` correctly converts 4 bytes → (heightMM, speedMMS) for all traced walkthrough cases; rejects invalid data (too short, out of range); `encodeTargetHeight` converts mm → little-endian uint16 in 0.1mm units; preset response parsing extracts stored height
  3. Implement: Create `Sources/BLE/DeskProtocol.swift` with: `parseHeightNotification(_:)`, `encodeTargetHeight(mm:)`, `parseCapabilities(_:)`, `parsePresetHeight(_:)`
  4. Validate: Unit tests pass for all traced walkthrough rows in SDD; edge cases (zero height, max height, negative speed) handled
  5. Success: Height bytes `52 2B 00 00` → 1109mm; `D2 1C F0 FF` → 737mm moving down `[ref: SDD/Implementation Examples/Height Notification Parsing]` `[ref: PRD/Feature 3/AC-3]`

- [ ] **T1.4 Data Models** `[activity: domain-modeling]` `[parallel: true]`

  1. Prime: Read SDD application data models `[ref: SDD/Application Data Models]`
  2. Test: `DeskState` initializes with disconnected state; `ConnectionState` enum has all 5 cases; `PresetPosition` stores index + optional height + optional label; `activePreset()` returns correct index using 5mm tolerance and movement rules per SDD traced walkthrough
  3. Implement: Create `Sources/Core/DeskState.swift` with `DeskState`, `ConnectionState`, `MoveDirection`, `PresetPosition`. Include the `activePreset(height:presets:isMoving:)` function from SDD.
  4. Validate: Unit tests pass for all 5 traced walkthrough rows in SDD preset matching example
  5. Success: Preset matching: 1103mm matches preset at 1105mm; no match while moving `[ref: SDD/Implementation Examples/Preset Matching Logic]` `[ref: PRD/Feature 5/AC-3,4]`

- [ ] **T1.5 ConfigStore — Settings Persistence** `[activity: domain-modeling]`

  1. Prime: Read SDD data storage schemas `[ref: SDD/Data Storage Changes]`
  2. Test: `ConfigStore` creates default config.json on first access; reads existing config; writes updated settings; validates preset index range (1-4); `ProfileStore` loads profiles.json with owner and default guest; round-trips all fields through encode/decode
  3. Implement: Create `Sources/Config/ConfigModels.swift` with Codable structs matching SDD schema (AppConfig, Profile). Create `Sources/Config/ConfigStore.swift` that reads/writes JSON files in `~/Library/Application Support/DeskControl/`. Create directory if missing.
  4. Validate: Unit tests with temp directory; encode→decode round-trip; default values correct
  5. Success: Config persists across restarts; defaults match SDD (unit=cm, autoRunUp=manual, autoRunDown=manual) `[ref: SDD/Data Storage Changes]` `[ref: PRD/Feature 9/AC-4]`

- [ ] **T1.6 HeightConverter & Logger** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read PRD height display requirements `[ref: PRD/Feature 3]` `[ref: SDD/Cross-Cutting Concepts/System-Wide Patterns]`
  2. Test: `HeightConverter.display(mm: 1105, unit: .cm)` → "110.5 cm"; `.display(mm: 1105, unit: .inch)` → "43.5 in"; Logger writes to os.Logger with correct subsystem and categories
  3. Implement: Create `Sources/Util/HeightConverter.swift` and `Sources/Util/Logger.swift` (os.Logger wrapper with subsystem `com.deskcontrol`, categories: ble, ipc, core, ui)
  4. Validate: Unit tests for conversion edge cases (minimum height, maximum height, rounding)
  5. Success: Height display matches PRD examples `[ref: PRD/Feature 3/AC-4]`

- [ ] **T1.7 Phase Validation** `[activity: validate]`

  - Run all Phase 1 tests. Verify: both Xcode targets build, all BLE protocol constants match SDD glossary, height parsing matches all traced walkthroughs, config round-trips correctly. SwiftLint passes.
