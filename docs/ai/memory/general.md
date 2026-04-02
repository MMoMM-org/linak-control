# General -- linak-control
<!-- Conventions, naming rules, code style, git workflow. Updated: 2026-04-02 -->

## Architecture

- **Clean Architecture**: BLE (transport) -> Core (business logic) -> UI (presentation)
- **DeskManager**: Swift actor, single source of truth for desk state
- **BLEControllerProtocol**: Protocol abstraction over CoreBluetooth for testability
- **DeskViewModel**: @MainActor ObservableObject bridging DeskManager to SwiftUI
- **DeskProtocol**: Static namespace for BLE wire-format parsing/encoding
- **DeskLimits**: Centralised range constants (Single Source of Truth)
- **TimedStreamBuffer**: Actor-isolated async stream consumer with timeout

## Naming

- Heights in state: `heightMM` (raw, relative to desk zero)
- Heights in UI: offset-adjusted via `HeightConverter.display(mm:unit:)`
- BLE UUIDs: `DeskUUID.*` (static CBUUID constants)
- Commands: `DeskCommand.*` (static Data constants)
- Errors: `DeskError.*` and `BLEError.*`

## Patterns

- Continuations: always use `take*()` helpers for atomic nil-and-return
- Fire-and-forget Tasks in ViewModel: log errors, don't `try?` silently
- Config persistence: `persistConfig { $0.field = value }` one-liner pattern
- Movement: wake -> preflight -> loop (100ms interval) -> stop (twice)
- State observation: `for await snapshot in manager.stateStream` in ViewModel
