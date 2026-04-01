---
title: "Phase 7: Integration & E2E Validation"
status: completed
version: "1.0"
phase: 7
---

# Phase 7: Integration & E2E Validation

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: PRD/Feature Requirements]` — All 48 acceptance criteria
- `[ref: SDD/Quality Requirements]` — Performance, usability, security, reliability targets
- `[ref: SDD/Acceptance Criteria]` — All EARS-format system criteria
- `[ref: SDD/Risks and Technical Debt/Implementation Gotchas]` — Known edge cases

**Key Decisions**:
- All ADRs (1-7) — verify architectural decisions hold up in integration

**Dependencies**:
- All previous phases complete (1-6)

---

## Tasks

Validates the complete system end-to-end. Covers integration testing, performance verification, build/install flow, and full acceptance criteria sign-off. After this phase, the app is ready for use.

- [x] **T7.1 Integration Test: UI ↔ BLE Flow** `[activity: validate]`

  1. Prime: Read SDD runtime view primary flow `[ref: SDD/Runtime View/Primary Flow: Preset Quick-Switch]`
  2. Test: Full flow with mock BLE: launch app → menu bar appears → click Zone 2 → dropdown shows presets → click Preset 2 → DeskManager receives goToPreset(2) → mock BLE receives correct byte sequence (preflight + target writes) → mock height notifications flow back → UI updates live → preset highlighted on arrival
  3. Implement: Integration test that wires real DeskViewModel → DeskManager → mock BLEController. Verify end-to-end data flow from UI action to BLE command and back.
  4. Validate: All data flows correctly; no actor isolation violations; UI updates within 100ms of state change
  5. Success: Complete preset-switch flow works end-to-end `[ref: PRD/Feature 5/AC-2,3]`

- [x] **T7.2 Integration Test: CLI ↔ IPC ↔ BLE Flow** `[activity: validate]`

  1. Prime: Read SDD CLI flow `[ref: SDD/Runtime View/Primary Flow: CLI Preset Command]`
  2. Test: Start app with `DESK_MOCK_BLE=1` env var (uses MockBLEController) and real IPCServer. Run `deskctl status` → receives correct JSON. Run `deskctl preset 2` → DeskManager receives goToPreset(2). Run `deskctl height --json` → valid JSON with correct fields. Run `deskctl` when daemon not running → exit code 2. Run `deskctl preset 1` when disconnected → exit code 3.
  3. Implement: Process-level integration test: launch app process with mock BLE injection seam, run deskctl as subprocess, verify stdout/stderr and exit codes.
  4. Validate: All CLI commands produce correct output and exit codes
  5. Success: CLI controls desk through IPC pipeline `[ref: PRD/Feature 6/AC-1,2,3,4,5]` `[ref: PRD/Feature 14/AC-1,2]`

- [x] **T7.3 Reconnection & Error Recovery Test** `[activity: validate]`

  1. Prime: Read SDD error handling and reconnection flows `[ref: SDD/Runtime View/Error Handling]` `[ref: SDD/Runtime View/Wake from Sleep Reconnection]`
  2. Test: Simulate BLE disconnect → DeskManager transitions to .disconnected → UI shows reconnecting → exponential backoff fires (1s, 2s, 4s) → mock reconnect succeeds → state returns to .connected. Simulate desk busy → UI shows "Desk Busy" message with actionable guidance. Simulate wake from sleep → wait for poweredOn → reconnect → handshake → ready. Simulate disconnect during movement → movement state cleared → no auto-resume after reconnect.
  3. Implement: Integration tests with mock BLEController that simulates failures, delays, and state transitions.
  4. Validate: All error paths tested; UI states match mockups; timing within spec
  5. Success: Reconnection within 8 seconds; desk busy message shown; no unintended movement `[ref: PRD/Feature 2/AC-1,2]` `[ref: PRD/Feature 1/AC-4]`

- [x] **T7.4 Performance Verification** `[activity: validate]`

  1. Prime: Read SDD quality requirements `[ref: SDD/Quality Requirements]`
  2. Test: Idle CPU < 0.1% (measured via `XCTMeasure` with `XCTCPUMetric()`). Idle memory < 20 MB RSS (via `mach_task_basic_info`). Height update latency < 100ms (measure from mock BLE notification to UI property change). Preset move start < 1 second from goToPreset call to first BLE write. CLI command response < 500ms.
  3. Implement: Performance tests using `XCTest.measure(metrics: [XCTCPUMetric(), XCTMemoryMetric()])` for automated, repeatable assertions. No manual `top` sampling.
  4. Validate: All performance targets met; document actual measurements
  5. Success: All quality requirements within budget `[ref: SDD/Quality Requirements/Performance]` `[ref: PRD/Feature 2/AC-4]`

- [x] **T7.5 Build & Install Flow** `[activity: validate]`

  1. Prime: Read SDD deployment view `[ref: SDD/Deployment View]`
  2. Test: `xcodebuild -scheme LinakControl -configuration Release CODE_SIGN_IDENTITY="-"` succeeds. App launches after `xattr -dr com.apple.quarantine`. `deskctl` binary runs standalone. Bluetooth permission dialog appears on first launch. Config directory created automatically.
  3. Implement: Shell script or Makefile that builds both targets, copies to /Applications and /usr/local/bin, strips quarantine. Verify the full install flow.
  4. Validate: Clean build from scratch on a fresh checkout; verify all artifacts
  5. Success: Build-from-source install works for a new user following README `[ref: SDD/Deployment View/Build & Install]`

- [x] **T7.6 PRD Acceptance Criteria Audit** `[activity: validate]`

  1. Prime: Read all PRD acceptance criteria `[ref: PRD/Feature Requirements]` — all 48 criteria across 17 features
  2. Test: Map every PRD acceptance criterion to a passing test or verified behavior. Must-Have features (1-9): all criteria verified. Should-Have features (10-14): implemented features verified, deferred features documented. Could-Have features (15-17): not implemented, documented as future work.
  3. Implement: Create a traceability matrix: PRD criterion → test file/method or manual verification step. Run all tests. Document any gaps.
  4. Validate: Zero uncovered Must-Have criteria; all Should-Have implemented in this plan are verified
  5. Success:
    - [ ] Feature 1 (BLE Discovery): 4/4 AC verified `[ref: PRD/Feature 1]`
    - [ ] Feature 2 (Background Connection): 4/4 AC verified `[ref: PRD/Feature 2]`
    - [ ] Feature 3 (Menu Bar Status): 4/4 AC verified `[ref: PRD/Feature 3]`
    - [ ] Feature 4 (Up/Down Control): 5/5 AC verified `[ref: PRD/Feature 4]`
    - [ ] Feature 5 (Presets): 5/5 AC verified `[ref: PRD/Feature 5]`
    - [ ] Feature 6 (CLI): 6/6 AC verified `[ref: PRD/Feature 6]`
    - [ ] Feature 7 (First-Run): 5/5 AC verified `[ref: PRD/Feature 7]`
    - [ ] Feature 8 (Daemon Lifecycle): 4/4 AC verified (note: AC-3 revised to login-item restart, not 5s crash recovery) `[ref: PRD/Feature 8]`
    - [ ] Feature 9 (Settings): 4/4 AC verified (AC-3 cross-process sync tested: change unit via UI → verify deskctl status reflects new unit) `[ref: PRD/Feature 9]`
    - [ ] Feature 11 (Sleep/Wake Recovery): 2/2 AC verified `[ref: PRD/Feature 11]`
    - [ ] Feature 12 (Global Hotkeys): 2/2 AC verified `[ref: PRD/Feature 12]`
    - [ ] Feature 13 (Notifications): 2/2 AC verified `[ref: PRD/Feature 13]`
    - [ ] Feature 14 (CLI Exit Codes): 2/2 AC verified `[ref: PRD/Feature 14]`

- [x] **T7.7 Phase Validation** `[activity: validate]`

  - All integration tests pass. All performance targets met. Build flow works from clean checkout. All Must-Have PRD criteria mapped to tests. No [NEEDS CLARIFICATION] markers in any spec document. SwiftLint clean. App is ready for daily use.
