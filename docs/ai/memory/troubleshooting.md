# Troubleshooting -- linak-control
<!-- Known issues and proven fixes. Updated: 2026-04-02 -->

## USER_ID corruption -- Status: resolved
Writing incorrect USER_ID data back to the desk corrupted its user profile, resetting calibration/offset to 0. Fix: skip write-back when byte 0 is already 0x01. If corrupted, use the LINAK Desk Control iOS app to repair the desk's user profile.

## DPG queries return 0x0B 0x00 -- Status: resolved
All DPG queries failed because: (a) commands were 2 bytes instead of required 3 bytes, and (b) USER_ID session activation was missing. Fix: 3-byte read format [0x7F, cmd, 0x00] + USER_ID read+write before queries.

## Heartbeat disrupts movement -- Status: resolved
Heartbeat [0x01 0x80] writes to same characteristic (0x0031) as moveTo targets. Desk interpreted heartbeat as target position ~33m, causing erratic movement. Fix: suppress heartbeat when state.isMoving is true.

## Height validation rejects real values -- Status: resolved
validHeightRange was 500-1500mm (absolute), but height characteristic reports raw values (0-650mm). All real desk heights were rejected. Fix: widen to 0-7000mm for raw values.

## Preset move fails silently -- Status: resolved
validHeightRangeMM in DeskManager+Presets.swift had stale absolute range (600-1350). Raw preset values (49, 420, 486mm) were rejected. Fix: use DeskLimits.safeCommandRange (0-6500) as single source of truth.

## Config lost on restart -- Status: resolved
Adding new fields (deskOffsetMM) to AppConfig broke the auto-synthesized Codable decoder -- missing keys caused entire decode to fail, falling back to defaults. Fix: custom init(from:) with decodeIfPresent for all fields.

## SPM lock files block tests -- Status: known
Background agent processes can leave orphan swift-package processes holding `.build/*.lock`. Fix: `killall swift-package; make test` or `rm -f LinakControl/.build/*.lock`.

## TestClock + actor-isolated Task deadlock -- Status: resolved
TestClock + actor-isolated Task + `await task.value` deadlocks: the actor awaits the task that needs the actor to check `isCancelled`. `Task.detached` doesn't help because TestClock.advance doesn't synchronize with the global executor. Fix: cancel without await (fire-and-forget), use SystemClock with real timing in tests, use `waitFor()` polling for state checks.

## Base offset parsed from wrong response -- Status: resolved
GET_DESK_OFFSET (0x88) has an 11-byte payload that was incorrectly read as uint16, yielding 1413mm. The real base offset is in the USER_ID (0x81) response at bytes [3:4] as LE uint16 in 0.1mm (e.g. 0x1A90 = 680mm). Fix: `DeskProtocol.parseBaseOffset(fromUserID:)`.

## Desk offset resets to handshake value -- Status: resolved
persistPairingInfo and apply() both overwrote the user's manual offset with the handshake-parsed value (1413mm, incorrectly interpreted). Fix: offset exclusively from config, never from handshake state.
