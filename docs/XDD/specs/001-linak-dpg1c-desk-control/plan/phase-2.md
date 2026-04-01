---
title: "Phase 2: BLE Connection & Desk Management"
status: pending
version: "1.0"
phase: 2
---

# Phase 2: BLE Connection & Desk Management

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: SDD/Implementation Examples/DPG1C Handshake Sequence]` — Full handshake with byte sequences
- `[ref: SDD/Implementation Examples/Move-to-Preset Control Loop]` — Position control loop
- `[ref: SDD/Runtime View/Wake from Sleep Reconnection]` — Reconnection sequence diagram
- `[ref: SDD/Runtime View/Error Handling]` — All error scenarios
- `[ref: SDD/Runtime View/Complex Logic: Heartbeat]` — Keep-alive algorithm

**Key Decisions**:
- ADR-3: Swift Actor — DeskManager serializes all state access
- ADR-4: Hardware Presets — read from firmware on every connection, never cache

**Dependencies**:
- Phase 1 complete (BLE constants, DeskProtocol, DeskState, ConfigStore)

---

## Tasks

Establishes BLE connectivity, the DeskManager actor (central state coordinator), and all desk control operations. After this phase, the app can scan, connect, move the desk, and handle disconnection — but has no UI or CLI yet.

- [ ] **T2.1 BLEController — CoreBluetooth Wrapper** `[activity: build-feature]`

  1. Prime: Read SDD BLE architecture and CoreBluetooth lifecycle `[ref: SDD/Implementation Examples/DPG1C Handshake Sequence]` `[ref: SDD/Building Block View/Components]`
  2. Test: BLEController initializes CBCentralManager on a dedicated serial queue (not MainActor); state transitions fire through AsyncStream (poweredOff → poweredOn → scanning → connected); `scanForPeripherals` filters by Control service UUID `99fa0001`; `connect()` stores peripheral reference; delegate callbacks bridge to async/await via continuations
  3. Implement: Create `Sources/BLE/BLEControllerProtocol.swift` defining the protocol with all async methods. Create `Sources/BLE/BLEController.swift` conforming to the protocol, wrapping CBCentralManager and CBPeripheralDelegate. Create `Sources/BLE/MockBLEController.swift` with pre-scripted responses and write capture for tests. Expose async methods: `scan() -> AsyncStream<DiscoveredDesk>`, `connect(peripheralId:)`, `disconnect()`, `write(data:to:type:)`, `read(_:) async throws -> Data`, `notifications(for:) -> AsyncStream<Data>`. Use a dedicated `DispatchQueue(label: "com.linakcontrol.ble")`. Add `DESK_MOCK_BLE=1` env var check at startup to swap implementation for integration tests.
  4. Validate: Unit tests with MockBLEController; state transitions correct; delegate bridging works; mock captures written bytes for assertion
  5. Success: BLE scanning discovers desks filtered by LINAK service UUID `[ref: PRD/Feature 1/AC-1]`; connection completes `[ref: PRD/Feature 1/AC-2]`; MockBLEController enables all downstream testing without hardware

- [ ] **T2.2 DPG1C Handshake** `[activity: build-feature]`

  1. Prime: Read SDD handshake sequence step-by-step `[ref: SDD/Implementation Examples/DPG1C Handshake Sequence]`
  2. Test: Handshake enables notifications on characteristics 0003, 0011, 0021; reads mask 0029 (expects 0x01); sends capability queries in correct order (7F 80, 7F 86, 7F 81, 7F 88, 7F 89-8C); parses capability response byte (preset count, autoUp/Down flags); extracts 4 preset heights from 7F 89-8C responses; fails gracefully if mask value is unexpected
  3. Implement: Add `performHandshake()` method to BLEController. Parse capabilities byte. Return `HandshakeResult` with capabilities and preset heights. Use the exact byte sequences from SDD. Create `Tests/Fixtures/HandshakeFixtures.swift` with static `Data` arrays representing each handshake notification response (captured from real hardware, document source in fixture comments).
  4. Validate: Test with fixture data via MockBLEController; all 8 capability queries sent in order; preset heights parsed correctly
  5. Success: Handshake completes within 5 seconds; all 4 presets read from firmware `[ref: PRD/Feature 1/AC-2]` `[ref: PRD/Feature 5/AC-1]`

- [ ] **T2.3 DeskManager Actor** `[activity: domain-modeling]`

  1. Prime: Read SDD DeskManager role and state management pattern `[ref: SDD/Building Block View/Components]` `[ref: SDD/Cross-Cutting Concepts/Pattern Documentation]`
  2. Test: DeskManager initializes with `.disconnected` state; `scan()` transitions to `.scanning`; `connect()` runs handshake, transitions to `.connected`, populates preset heights; `disconnect()` cleans up and transitions to `.disconnected`; state changes are observable (AsyncStream or @Observable); concurrent access from multiple callers is serialized (no data races)
  3. Implement: Create `Sources/Core/DeskManager.swift` as a Swift `actor`. Owns BLEController and ConfigStore. Exposes: `scan()`, `connect(peripheralId:)`, `disconnect()`, `moveUp(mode:)`, `moveDown(mode:)`, `stop()`, `goToPreset(index:)`, `savePreset(index:)`, `updateSettings(_:)`. Publishes `DeskState` changes via `AsyncStream<DeskState>` or `@Observable`.
  4. Validate: Unit tests with mock BLEController; state transitions correct; concurrent access safe
  5. Success: DeskManager serializes state; BLE ↔ state transitions match SDD state diagram `[ref: SDD/Cross-Cutting Concepts/User Interface & UX/State Management]`

- [ ] **T2.4 Movement Control (Up/Down/Stop)** `[activity: build-feature]`

  1. Prime: Read SDD movement protocol and PRD up/down requirements `[ref: SDD/Glossary/BLE Commands]` `[ref: PRD/Feature 4]`
  2. Test: Manual mode: sends `47 00` (up) or `46 00` (down) every 100ms while active; stops sending on `stop()`; sends `FF 00` twice on stop. Auto mode: sends move-to with max/min height as target; stop sends `FF 00` twice. Height notifications update DeskState at 5-10 Hz during movement. State shows `isMoving = true` with correct direction.
  3. Implement: Add movement methods to DeskManager. Manual mode uses a repeating `Task` that writes command bytes every 100ms. Auto mode uses the move-to-height control loop from SDD. Height notification stream updates `DeskState.heightMM` and `speedMMS`.
  4. Validate: Mock BLE verifies correct bytes written at correct intervals; state transitions between idle ↔ moving
  5. Success: Desk moves within 500ms of command; stops within 500ms of release `[ref: PRD/Feature 4/AC-1,2,3,4]`

- [ ] **T2.5 Preset Recall (Go-To)** `[activity: build-feature]`

  1. Prime: Read SDD move-to-preset control loop `[ref: SDD/Implementation Examples/Move-to-Preset Control Loop]` `[ref: PRD/Feature 5]`
  2. Test: `goToPreset(2)` reads preset 2 height, writes preflight `00 00` to 0002, then writes target to `0031` every 100ms; stops when height is within 5mm of target; sets `targetPreset = 2` during movement; sets `activePreset = 2` on arrival; new preset command cancels in-flight move; unset preset (heightMM = nil) returns error
  3. Implement: Add `goToPreset(index:)` to DeskManager. Uses `moveToHeight(targetMM:)` from SDD example. Cancels existing movement task before starting new one. Sets `targetPreset` during movement, `activePreset` on completion.
  4. Validate: Test all 5 preset matching walkthrough rows from SDD; cancellation works; error on unset preset
  5. Success: Desk moves to preset within 1 second of tap; active preset highlighted on arrival `[ref: PRD/Feature 5/AC-2,3]`

- [ ] **T2.6 Preset Save** `[activity: build-feature]`

  1. Prime: Read SDD save preset BLE commands `[ref: SDD/Glossary/BLE Commands]` `[ref: PRD/Feature 5/AC-5]`
  2. Test: `savePreset(2)` writes `7F 8A 80 01 [lo] [hi]` to 0011 with current height; re-reads preset to confirm write; updates DeskState.presets; fails gracefully if write rejected
  3. Implement: Add `savePreset(index:)` to DeskManager. Write save command, re-read to verify.
  4. Validate: Mock BLE verifies correct save bytes; re-read confirms height
  5. Success: Preset saved to desk firmware and confirmed `[ref: PRD/Feature 5/AC-5]`

- [ ] **T2.7 Reconnection & Wake-Up** `[activity: build-feature]`

  1. Prime: Read SDD reconnection and wake-up sequences `[ref: SDD/Runtime View/Wake from Sleep Reconnection]` `[ref: SDD/Runtime View/Error Handling]` `[ref: SDD/Runtime View/Complex Logic: Heartbeat]`
  2. Test: On `didDisconnect`, DeskManager calls `connect()` with exponential backoff (1s, 2s, 4s, 8s, max 60s); on `NSWorkspace.didWakeNotification`, waits for `.poweredOn` then reconnects; wake-up sends `FE 00`, waits 200ms, sends `FF 00`, waits 200ms, then handshakes; retries up to 3 times; heartbeat writes `01 80` to 0031 every 1 second while connected; heartbeat failure (3x) triggers reconnect
  3. Implement: Inject a `Clock` protocol into DeskManager (use Swift 5.7+ `Clock` API or custom protocol with `TestClock` for deterministic time advancement in tests). Add reconnection logic with exponential backoff. Add wake observer (`NSWorkspace.shared.notificationCenter`). Add `wakeUpDesk()` method. Add conditional heartbeat that pauses after 10 min idle (per SDD). Add transparent wake-up: when a command is issued and desk is sleeping, auto-run wake-up sequence before executing the command (within 1.5s total).
  4. Validate: Test with TestClock — advance time explicitly to verify backoff intervals (1s, 2s, 4s, 8s) without real sleeping; verify heartbeat pauses after 10 min idle; verify transparent wake+command within 1.5s using TestClock; verify wake-up byte sequences via MockBLEController
  5. Success: Reconnects within 8 seconds after sleep `[ref: PRD/Feature 2/AC-1,2,3]`; wake-up recovers sleeping desk within 1.5s `[ref: PRD/Feature 11/AC-1,2]`; heartbeat pauses after 10 min idle `[ref: SDD/Runtime View/Complex Logic: Conditional Heartbeat]`

- [ ] **T2.8 Phase Validation** `[activity: validate]`

  - Run all Phase 2 tests. Verify: BLEController state machine, handshake sequence, DeskManager actor safety, movement control, preset recall/save, reconnection with backoff, wake-up sequence, heartbeat. All tests pass, SwiftLint clean.
