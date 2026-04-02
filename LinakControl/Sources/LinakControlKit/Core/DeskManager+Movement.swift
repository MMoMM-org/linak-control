// DeskManager+Movement.swift
// LinakControlKit — Movement control implementation for DeskManager.
//
// Manual mode: repeats move command every 100ms until stop() is called.
// Auto mode: sends preflight then repeats move-to target every 100ms until stop() is called.

import CoreBluetooth
import Foundation

// MARK: - Movement constants

private let movementInterval: Duration = .milliseconds(100)
// Auto targets defined in DeskLimits (DeskProtocol.swift) — single source of truth.

// MARK: - DeskManager movement extension

extension DeskManager {

    // MARK: - Internal entry points (called from DeskManager.swift public methods)

    /// Validates connection, cancels any prior movement, then starts a new movement task.
    func startMovement(_ direction: MoveDirection, mode: RunMode) async throws {
        FileLog.debug("startMovement(\(direction), mode: \(mode))", category: "core")
        try requireConnected()
        try await recordUserAction()
        cancelMovementTask()

        updateState {
            $0.isMoving = true
            $0.moveDirection = direction
            $0.targetPreset = nil
        }

        switch mode {
        case .manual:
            startManualMovementTask(direction: direction)
        case .auto:
            try await startAutoMovementTask(direction: direction)
        }
    }

    /// Cancels the active movement task. Does not await completion because the
    /// movement loop runs on the actor's executor and awaiting would deadlock
    /// with TestClock. One trailing write after cancel is harmless — the stop
    /// command sent afterwards overrides any residual movement command.
    func cancelMovementTask() {
        movementTask?.cancel()
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

    /// Starts a detached Task that writes the manual move command every 100ms until cancelled.
    ///
    /// Uses `Task.detached` so the loop runs on the global executor, not the actor's
    /// serial executor. This prevents deadlock when `cancelMovementTask()` awaits
    /// `movementTask?.value` — the loop can make progress independently of the actor.
    private func startManualMovementTask(direction: MoveDirection) {
        let command = manualCommand(for: direction)
        let controller = bleController
        let clockRef = clock
        movementTask = Task {
            while !Task.isCancelled {
                try? await controller.write(
                    data: command,
                    to: DeskUUID.command,
                    type: .withoutResponse
                )
                try? await clockRef.sleep(for: movementInterval)
            }
        }
    }

    /// Sends preflight then starts a detached Task that writes the move-to target every 100ms.
    private func startAutoMovementTask(direction: MoveDirection) async throws {
        try await bleController.write(
            data: DeskCommand.preflight,
            to: DeskUUID.command,
            type: .withoutResponse
        )

        let target = autoTarget(for: direction)
        let controller = bleController
        let clockRef = clock
        movementTask = Task {
            while !Task.isCancelled {
                try? await controller.write(
                    data: target,
                    to: DeskUUID.targetHeartbeat,
                    type: .withoutResponse
                )
                try? await clockRef.sleep(for: movementInterval)
            }
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
