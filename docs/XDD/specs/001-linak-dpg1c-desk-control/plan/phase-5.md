---
title: "Phase 5: CLI Tool (deskctl)"
status: pending
version: "1.0"
phase: 5
---

# Phase 5: CLI Tool (deskctl)

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: SDD/Interface Specifications/IPC Methods]` — All 8 IPC methods
- `[ref: SDD/Interface Specifications/IPC Error Codes]` — Error code → exit code mapping
- `[ref: SDD/Runtime View/Primary Flow: CLI Preset Command]` — CLI → IPC → DeskManager flow
- `[ref: mockups.md/CLI Output Examples]` — Approved CLI output formats
- `[ref: PRD/Feature 6]` — CLI acceptance criteria
- `[ref: PRD/Feature 8]` — Daemon lifecycle management
- `[ref: PRD/Feature 14]` — Exit codes and structured errors

**Key Decisions**:
- ADR-2: Unix Domain Socket — CLI connects via IPCClient

**Dependencies**:
- Phase 3 complete (IPCClient, IPCServer)
- Can run in parallel with Phase 4 (UI)

---

## Tasks

Builds the complete `deskctl` CLI tool. After this phase, all desk operations are available from the command line with proper exit codes and JSON output.

- [ ] **T5.1 Root Command & Argument Parsing** `[activity: build-feature]`

  1. Prime: Read PRD CLI spec and mockup CLI output `[ref: PRD/Feature 6]` `[ref: mockups.md/CLI Output Examples]`
  2. Test: `deskctl --help` prints usage with all subcommands. `deskctl --version` prints version. Unknown subcommands print error and usage. Root command (no args) prints help.
  3. Implement: Create `Sources/deskctl/DeskctlCommand.swift` using Swift ArgumentParser. Define root `Deskctl` ParsableCommand with subcommands: `StatusCommand`, `HeightCommand`, `MoveCommand` (up/down), `PresetCommand`, `ServiceCommand`. Add `--version` flag.
  4. Validate: `deskctl --help` output matches PRD structure; unknown commands error correctly
  5. Success: All subcommands registered and discoverable via --help `[ref: PRD/Feature 6/AC-6]`

- [ ] **T5.2 Status Command** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockup CLI status output `[ref: mockups.md/CLI Output Examples/deskctl status]`
  2. Test: `deskctl status` sends `getStatus` via IPC; prints table with: daemon status, connection state, desk name, height, profile, presets (with * for active). `deskctl status --json` prints full JSON response.
  3. Implement: Create `Sources/deskctl/StatusCommand.swift`. Connect IPCClient, send getStatus, format response as table or JSON.
  4. Validate: Test output format matches mockup; JSON is valid; handles daemon-not-running (exit 2) and disconnected states
  5. Success: Status output matches approved mockup format `[ref: PRD/Feature 6/AC-1,2]`

- [ ] **T5.3 Height Command** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockup JSON output `[ref: mockups.md/CLI Output Examples/deskctl height --json]`
  2. Test: `deskctl height` prints human-readable height (e.g., "110.5 cm"). `deskctl height --json` prints `{"height_mm": 1105, "height_display": "110.5", "unit": "cm"}`. Exit code 2 when daemon not running. Exit code 3 when desk not connected.
  3. Implement: Create `Sources/deskctl/HeightCommand.swift`. Send getStatus, extract height fields.
  4. Validate: JSON output is valid and matches SDD schema; error exit codes correct
  5. Success: JSON output contains height_mm, height_display, unit `[ref: PRD/Feature 6/AC-2]`

- [ ] **T5.4 Move Commands (up/down)** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read PRD movement requirements `[ref: PRD/Feature 4]`
  2. Test: `deskctl up` sends move(direction: up, mode: configured default). `deskctl up --auto` overrides to auto mode. `deskctl up --manual` overrides to manual mode. `deskctl down` works symmetrically. `deskctl stop` sends stop command. All return exit code 0 on success. Exit code 3 when desk not connected.
  3. Implement: Create `Sources/deskctl/MoveCommand.swift` with Up and Down subcommands. Each takes optional `--auto`/`--manual` flag. Create separate `StopCommand`. Connect via IPC, send move/stop requests.
  4. Validate: Test flag parsing; IPC requests have correct params; exit codes match SDD table
  5. Success: CLI movement commands work with mode override `[ref: PRD/Feature 6/AC-3]` `[ref: SDD/Interface Specifications/IPC Methods]`

- [ ] **T5.5 Preset Command** `[activity: build-feature]` `[parallel: true]`

  1. Prime: Read mockup preset output `[ref: mockups.md/CLI Output Examples/deskctl preset 2]` `[ref: PRD/Feature 5]`
  2. Test: `deskctl preset 2` sends goPreset(index: 2); prints "Moving to preset 2 (110.5 cm)..."; exits 0. `deskctl preset 2 --save` sends savePreset(index: 2); confirms save. Validates index 1-4; out-of-range prints error. Exit code 3 when not connected.
  3. Implement: Create `Sources/deskctl/PresetCommand.swift`. Takes positional argument (1-4) and optional `--save` flag. Connect via IPC, send goPreset or savePreset.
  4. Validate: Test index validation; save flag; output format; error handling
  5. Success: Preset command triggers desk movement `[ref: PRD/Feature 6/AC-3]` `[ref: PRD/Feature 5/AC-2]`

- [ ] **T5.6 Service Command** `[activity: build-feature]`

  1. Prime: Read PRD daemon lifecycle requirements `[ref: PRD/Feature 8]`
  2. Test: `deskctl service status` reports "running" with uptime and connection state (via getStatus). `deskctl service stop` sends a shutdown signal to the app (via IPC or SIGTERM to PID). `deskctl service install` registers login item (prints instructions). Reports "not running" when socket not found.
  3. Implement: Create `Sources/deskctl/ServiceCommand.swift` with status/stop/install subcommands. Status: connect and query. Stop: send shutdown request or find PID and send SIGTERM. Install: print instructions for SMAppService registration (done via app Settings).
  4. Validate: Test all subcommands; handle daemon-not-running gracefully
  5. Success: Service lifecycle manageable from CLI `[ref: PRD/Feature 8/AC-2,4]`

- [ ] **T5.7 Error Formatting** `[activity: build-feature]`

  1. Prime: Read PRD structured error requirements `[ref: PRD/Feature 14]` `[ref: SDD/Interface Specifications/IPC Error Codes]`
  2. Test: All errors print to stderr. `--json` flag on any command outputs JSON errors: `{"error": 3, "message": "desk not connected"}`. Exit codes match SDD table (0=success, 1=general, 2=daemon not running, 3=not connected, 5=timeout). Plain text errors are actionable (e.g., "error: daemon not running — start LinakControl.app first").
  3. Implement: Create `Sources/deskctl/Formatters.swift` with `formatError(error:json:) -> (stderr: String, exitCode: Int32)`. Map IPCError codes to exit codes and messages. JSON errors use `{"error": <code>, "message": "<text>"}` format to stderr.
  4. Validate: Test all 4 exit codes (1, 2, 3, 5) with both plain and JSON output
  5. Success: Consistent exit codes and structured JSON errors `[ref: PRD/Feature 14/AC-1,2]`

- [ ] **T5.8 Phase Validation** `[activity: validate]`

  - Run all Phase 5 tests. Integration test with mock IPCServer: run each deskctl subcommand, verify output format, exit codes, and error handling. `deskctl --help` shows all commands. SwiftLint clean.
