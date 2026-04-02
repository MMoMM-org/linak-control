// DeskManager+Movement.swift
// LinakControlKit — Movement control implementation for DeskManager.
//
// Manual mode: repeats move command every 100ms until stop() is called.
// Auto mode: sends preflight then repeats move-to target every 100ms until stop() is called.

import CoreBluetooth
import Foundation

// MARK: - Movement constants

private let movementIntervalNanoseconds: UInt64 = 100_000_000   // 100 ms
// Auto targets defined in DeskLimits (DeskProtocol.swift) — single source of truth.

// MARK: - DeskManager movement extension

extension DeskManager {

    // MARK: - Internal entry points (called from DeskManager.swift public methods)

    /// Validates connection, cancels any prior movement, then starts a new movement task.
    func startMovement(_ direction: MoveDirection, mode: RunMode) async throws {
        FileLog.debug("startMovement(\(direction), mode: \(mode))", category: "core")
        try requireConnected()
        await cancelMovementTask()

        // Wake the desk before sending movement commands.
        try? await bleController.write(data: DeskCommand.wakeUp, to: DeskUUID.command, type: .withoutResponse)

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

    /// Cancels the active movement task and waits for it to finish.
    func cancelMovementTask() async {
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

    /// Starts a Task that writes the manual move command every 100ms until cancelled.
    private func startManualMovementTask(direction: MoveDirection) {
        let command = manualCommand(for: direction)
        let controller = bleController
        movementTask = Task {
            while !Task.isCancelled {
                try? await controller.write(
                    data: command,
                    to: DeskUUID.command,
                    type: .withoutResponse
                )
                try? await Task.sleep(nanoseconds: movementIntervalNanoseconds)
            }
        }
    }

    /// Sends preflight then starts a Task that writes the move-to target every 100ms until cancelled.
    private func startAutoMovementTask(direction: MoveDirection) async throws {
        try await bleController.write(
            data: DeskCommand.preflight,
            to: DeskUUID.command,
            type: .withoutResponse
        )

        let target = autoTarget(for: direction)
        let controller = bleController
        movementTask = Task {
            while !Task.isCancelled {
                try? await controller.write(
                    data: target,
                    to: DeskUUID.targetHeartbeat,
                    type: .withoutResponse
                )
                try? await Task.sleep(nanoseconds: movementIntervalNanoseconds)
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
