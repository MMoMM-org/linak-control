# Context -- linak-control
<!-- Current sprint focus, active work, known blockers. Updated: 2026-04-08 -->

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

- Fix 5 flaky movement tests (inject TestClock instead of real Task.sleep)
- Investigate correct base offset auto-parse — GET_DESK_OFFSET returns wrong value (1413mm); check if GET_BASE_OFFSET (0x81) gives the right one (currently set manually by user)

## Feature Backlog

- Configurable hotkeys (currently hardcoded Ctrl+Opt+1-4/Up/Down in HotkeyManager.swift)

## Done (recent)

- 2026-04-08: feat-branch merged into main (fast-forward, 87 commits)
- 2026-04-08: MIT LICENSE + THIRD_PARTY_LICENSES.md added; README updated
- 2026-04-08: untracked claude-docker/, claude-docker-home/, begin-code.sh from git (local-only infra)
- Zone 2 toggle in Settings (commit 66486ad)
