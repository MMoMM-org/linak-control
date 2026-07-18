// DeskManager+Movement.swift
// LinakControlKit — Movement control implementation for DeskManager.
//
// Manual mode: repeats move command every 100ms until stop() is called.
// Auto mode: sends preflight then repeats move-to target every 100ms until stop() is called.

import CoreBluetooth
import Foundation

// MARK: - Movement constants

private let movementInterval: Duration = .milliseconds(100)

/// How long the desk height may stay unchanged while a movement is commanded
/// before the loop concludes the desk is not responding and stops. Wide enough
/// to absorb wake-up, preflight, and acceleration latency at the start of a move.
private let stallTimeout: Duration = .seconds(2)
// Auto targets defined in DeskLimits (DeskProtocol.swift) — single source of truth.

// MARK: - DeskManager movement extension

extension DeskManager {

    // MARK: - Internal entry points (called from DeskManager.swift public methods)

    /// Validates connection, cancels any prior movement, then starts a new movement task.
    func startMovement(_ direction: MoveDirection, mode: RunMode) async throws {
        FileLog.debug("startMovement(\(direction), mode: \(mode))", category: "core")
        try requireConnected()
        try await recordUserAction()
        await cancelMovementTask()

        // Wake the desk before sending movement commands.
        try? await bleController.write(data: DeskCommand.wakeUp, to: DeskUUID.command, type: .withoutResponse)

        updateState {
            $0.isMoving = true
            $0.moveDirection = direction
            $0.targetPreset = nil
            // Optimistic: a fresh move attempt clears any prior stall flag. The
            // watchdog re-raises it if the desk still fails to respond.
            $0.needsReference = false
        }

        switch mode {
        case .manual:
            startManualMovementTask(direction: direction)
        case .auto:
            try await startAutoMovementTask(direction: direction)
        }
    }

    /// Cancels the active movement task and waits for it to drain.
    func cancelMovementTask() async {
        movementTask?.cancel()
        await movementTask?.value
        movementTask = nil
    }

    /// Writes the stop command twice then resets movement state.
    func writeStopCommand() async throws {
        try await bleController.write(
            data: DeskCommand.stop,
            to: DeskUUID.command,
            type: .withoutResponse
        )
        try await bleController.write(
            data: DeskCommand.stop,
            to: DeskUUID.command,
            type: .withoutResponse
        )
    }

    // MARK: - Private movement task builders

    /// Starts the watchdog loop that writes the manual move command every 100ms
    /// until cancelled or the desk stalls.
    private func startManualMovementTask(direction: MoveDirection) {
        let command = manualCommand(for: direction)
        movementTask = Task { [weak self] in
            await self?.runMovementLoop(command: command, characteristic: DeskUUID.command)
        }
    }

    /// Sends preflight then starts the watchdog loop that writes the move-to
    /// target every 100ms until cancelled or the desk stalls.
    private func startAutoMovementTask(direction: MoveDirection) async throws {
        try await bleController.write(
            data: DeskCommand.preflight,
            to: DeskUUID.command,
            type: .withoutResponse
        )

        let target = autoTarget(for: direction)
        movementTask = Task { [weak self] in
            await self?.runMovementLoop(command: target, characteristic: DeskUUID.targetHeartbeat)
        }
    }

    // MARK: - Watchdog loop

    /// Actor-isolated movement loop: writes `command` to `characteristic` every
    /// 100ms while observing desk height. If the height does not change for
    /// `stallTimeout` the desk is treated as not responding — the loop stops
    /// hammering it (per issue #1) and raises `needsReference`.
    ///
    /// Mirrors `runPresetLoop` (DeskManager+Presets.swift), which already
    /// terminates a repeating move loop on a height/time condition.
    private func runMovementLoop(command: Data, characteristic: CBUUID) async {
        var lastHeight = state.heightMM
        var lastProgressAt = clock.now()

        while !Task.isCancelled {
            try? await bleController.write(
                data: command,
                to: characteristic,
                type: .withoutResponse
            )
            try? await clock.sleep(for: movementInterval)

            let current = state.heightMM
            if current != lastHeight {
                lastHeight = current
                lastProgressAt = clock.now()
            } else if lastProgressAt.duration(to: clock.now()) >= stallTimeout {
                await handleStall()
                break
            }
        }
    }

    /// Stops the desk and flags a stall after the height failed to change while
    /// moving. The desk may be at a physical end-stop or the control module may
    /// need a manual re-reference (E16 on the display).
    private func handleStall() async {
        FileLog.debug(
            "movement stall: height unchanged for \(stallTimeout) while moving — stopping; desk may need manual re-reference (E16)",
            category: "movement"
        )
        try? await writeStopCommand()
        updateState {
            $0.isMoving = false
            $0.moveDirection = nil
            $0.speedMMS = 0
            $0.needsReference = true
        }
    }

    // MARK: - Command helpers

    private func manualCommand(for direction: MoveDirection) -> Data {
        switch direction {
        case .up:   return DeskCommand.moveUp
        case .down: return DeskCommand.moveDown
        }
    }

    private func autoTarget(for direction: MoveDirection) -> Data {
        switch direction {
        case .up:   return DeskCommand.moveTo(tenthsOfMm: DeskLimits.autoUpTargetTenths)
        case .down: return DeskCommand.moveTo(tenthsOfMm: DeskLimits.autoDownTargetTenths)
        }
    }
}
