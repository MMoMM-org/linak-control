---
title: "Phase 3: IPC Layer"
status: pending
version: "1.0"
phase: 3
---

# Phase 3: IPC Layer

## Phase Context

**GATE**: Read all referenced files before starting this phase.

**Specification References**:
- `[ref: SDD/Interface Specifications/IPC Protocol]` — Socket path, framing, request/response format
- `[ref: SDD/Interface Specifications/IPC Methods]` — All 8 methods with params and results
- `[ref: SDD/Interface Specifications/IPC Error Codes]` — Error code table
- `[ref: SDD/Runtime View/Primary Flow: CLI Preset Command]` — CLI → IPC → DeskManager flow

**Key Decisions**:
- ADR-2: Unix Domain Socket with length-prefixed JSON

**Dependencies**:
- Phase 2 complete (DeskManager actor with all desk operations)

---

## Tasks

Establishes the IPC communication layer between the menu bar app and external CLI clients. After this phase, external processes can control the desk via Unix socket.

- [ ] **T3.1 IPC Message Types** `[activity: domain-modeling]`

  1. Prime: Read SDD IPC protocol specification `[ref: SDD/Interface Specifications/IPC Protocol]` `[ref: SDD/Interface Specifications/IPC Methods]`
  2. Test: `IPCRequest` encodes/decodes with id, method, params fields; `IPCResponse` encodes/decodes with id, result, error fields; `IPCEvent` encodes/decodes with event, data fields; `IPCError` encodes with code and message; all 8 methods serialize correctly; unknown methods produce error code 10
  3. Implement: Create `Sources/IPC/IPCProtocol.swift` with Codable structs: `IPCRequest`, `IPCResponse`, `IPCEvent`, `IPCError`. Include framing helpers: `frame(message:) -> Data` (prepend 4-byte big-endian length), `deframe(data:) -> (message: Data, remaining: Data)?` (extract length-prefixed message from buffer).
  4. Validate: Round-trip encode/decode tests for all message types; framing handles partial reads
  5. Success: All IPC message types match SDD specification `[ref: SDD/Interface Specifications/IPC Protocol]`

- [ ] **T3.2 IPCServer** `[activity: build-feature]`

  1. Prime: Read SDD IPC server role and CLI flow `[ref: SDD/Runtime View/Primary Flow: CLI Preset Command]` `[ref: SDD/Interface Specifications/IPC Error Codes]`
  2. Test: Server creates socket at `~/Library/Application Support/LinakControl/linakcontrol.sock`; startup checks for stale socket (try connect → unlink if ECONNREFUSED → bind); socket mode 0600, directory mode 0700; accepts client connections; routes `getStatus` to DeskManager and returns status JSON; routes `goPreset` with index param; returns error code 10 for unknown methods; handles client disconnect gracefully; cleans up socket on shutdown (atexit/signal handler); rejects payloads > 64KB
  3. Implement: Create `Sources/IPC/IPCServer.swift`. Use POSIX socket API (socket/bind/listen/accept). Listen on AF_UNIX. Accept connections in a `Task`. Read length-prefixed messages (reject > 64KB). Route to DeskManager methods via typed IPCMethod enum. Write responses. Socket lifecycle: stale socket detection on startup, unlink on SIGTERM/SIGINT/atexit.
  4. Validate: Integration test: create socket, connect, send request, receive response; verify file permissions; multiple client test
  5. Success: CLI can query status and control desk via socket `[ref: PRD/Feature 6/AC-1,2,3]`; socket permissions are 0600 `[ref: SDD/Cross-Cutting Concepts/System-Wide Patterns/Security]`

- [ ] **T3.3 IPCClient (CLI-only)** `[activity: build-feature]`

  1. Prime: Read SDD IPC protocol and error codes `[ref: SDD/Interface Specifications/IPC Protocol]` `[ref: SDD/Interface Specifications/IPC Error Codes]`
  2. Test: Client connects to socket path; sends length-prefixed JSON request; receives and decodes typed response; throws typed error on connection refused (maps to exit code 2); throws typed error on IPC error response (maps to correct exit code)
  3. Implement: Create `Sources/deskctl/IPCClient.swift` (CLI target only — the app uses DeskManager directly, not IPC). Methods: `send(_ request: IPCRequest) async throws -> IPCResponse`. Handle socket not found → `.daemonNotRunning` error.
  4. Validate: Unit tests with mock socket; error mapping tests (ECONNREFUSED → code 2, ENOENT → code 2)
  5. Success: Client reliably communicates with server; errors map to correct exit codes `[ref: SDD/Interface Specifications/IPC Error Codes]` `[ref: PRD/Feature 6/AC-4,5]`

- [ ] **T3.4 Phase Validation** `[activity: validate]`

  - Run all Phase 3 tests. Integration test: start IPCServer with mock DeskManager, connect IPCClient, send getStatus, verify response. Send goPreset, verify DeskManager called. Verify socket cleanup on server shutdown. Verify stale socket detection. SwiftLint clean.
