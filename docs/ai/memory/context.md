# Context -- linak-control
<!-- Current sprint focus, active work, known blockers. Updated: 2026-04-02 -->

## Current State

Feature branch `feat/linak-control-impl` has 65+ commits. Full implementation of:
- BLE connection + DPG1C handshake
- Desk movement (manual + auto + presets)
- Menu bar UI (two zones: popover + preset dropdown)
- Settings panel (unit, offset, movement mode, presets, connection, system)
- First-run pairing flow
- Auto-reconnect with retry + system wake detection
- CLI tool (deskctl) via IPC
- 385 tests
- Code review: all 37 findings addressed

## Known Issues

- 5 timing-flaky movement tests (use real Task.sleep instead of TestClock)
- Desk offset auto-parse from GET_DESK_OFFSET response gives wrong value (1413mm). User sets offset manually for now.
- The correct base offset may be derivable from the USER_ID response (rhyst/linak-controller uses CMD 0x81 for base_height)

## Next Steps

- Fix flaky movement tests (inject TestClock)
- Investigate correct base offset parsing from USER_ID or DESK_OFFSET response
- Consider PR to main
