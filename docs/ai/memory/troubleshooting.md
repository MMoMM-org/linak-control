# Troubleshooting -- linak-control
<!-- Known issues and proven fixes. Updated: 2026-07-18 -->

<!-- 2026-07-18 -->
## Desk stalls / E16 while app keeps sending move commands -- Status: resolved (issue #1)
The manual/auto move loops (DeskManager+Movement.swift) wrote the move command every 100ms with `try?` and inspected no feedback, so a blocked desk module (which shows E16 and needs a manual re-reference) was hammered 10x/sec. Fix: the loops are now actor-isolated and watch `state.heightMM`; if height does not change for `stallTimeout` (2s) while moving, the loop stops, writes stop twice, and sets `DeskState.needsReference` (surfaced via popover banner, macOS notification, IPC status). Pattern mirrors `runPresetLoop`. Known limit: a physical end-stop also triggers this (harmless) -- precise E16 vs end-stop needs the status-byte decode (see below).
Deferred layer: the status characteristic 99fa0003 was subscribed in handshake but never consumed. Now `startStatusNotificationListener` logs raw status packets (category "status"). `FileLog.debug` writes in RELEASE too and is no longer reset at launch, so the log at ~/Library/Logs/LinakControl/debug.log persists across app restarts (1MB rolling). Capture a real E16 there, then decode the status byte to set `needsReference` precisely. High-frequency per-tick logs use `FileLog.trace` (DEBUG-only) to avoid flooding the release log.

<!-- 2026-04-08 -->
## Movement button icon no feedback during auto-move -- Status: resolved
UP/DOWN button showed static icon while desk auto-moved to preset, leaving user without visual cue to stop. Fix: swap icon to STOP during active movement (commit 9e44e03).

## Hold mode kept moving after button release -- Status: resolved
In hold mode, pressing UP/DOWN started movement but release did not stop it -- user had to hit stop button. Root cause: hold-button logic was shared with auto-preset flow where continued movement is correct. Fix: manual hold release stops movement; auto mode remains latched (commit 86b752e).

## Auto mode UP key triggered DOWN movement -- Status: resolved
Auto-up target calculation overflowed, causing the UP key to move the desk down. Fix: clamp auto-up target to valid range (commit 86b752e).


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

## Desk offset resets to handshake value -- Status: resolved
persistPairingInfo and apply() both overwrote the user's manual offset with the handshake-parsed value (1413mm, incorrectly interpreted). Fix: offset exclusively from config, never from handshake state.
