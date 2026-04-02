// DeskManager+Presets.swift
// LinakControlKit — Preset recall (go-to) implementation for DeskManager.
//
// Control loop: writes target position every 100ms to DeskUUID.targetHeartbeat
// until the desk reports height within 5mm of target, or 30 seconds elapse.

import CoreBluetooth
import Foundation

// MARK: - Preset constants

private let presetArrivalToleranceMM = 5
private let presetTimeout: Duration = .seconds(30)
private let presetLoopInterval: Duration = .milliseconds(100)
private let presetPreflightDelay: Duration = .milliseconds(100)
// Range constants are defined in DeskLimits (DeskProtocol.swift) — single source of truth.

// MARK: - DeskManager preset extension

extension DeskManager {

    // MARK: - Entry point (called from DeskManager.swift public goToPreset)

    /// Validates preconditions, cancels any prior move, and starts the control loop.
    func executeGoToPreset(index: Int) async throws {
        FileLog.debug("executeGoToPreset(\(index))", category: "core")
        try requireConnected()
        try await recordUserAction()

        let targetMM = try resolvePresetHeight(index)
        try guardHeightInRange(targetMM)

        await cancelPresetMoveTask()
        await cancelMovementTask()

        updateState {
            $0.targetPreset = index
            $0.isMoving = true
        }

        try await sendPreflight()
        startPresetControlLoop(targetMM: targetMM)
    }

    /// Cancels the active preset move task and waits for it to drain.
    func cancelPresetMoveTask() async {
        presetMoveTask?.cancel()
        await presetMoveTask?.value
        presetMoveTask = nil
    }

    // MARK: - Private implementation

    /// Returns the stored height for the given preset index, or throws if unset.
    private func resolvePresetHeight(_ index: Int) throws -> Int {
        guard index >= 1 && index <= state.presets.count else {
            throw DeskError.presetNotSet(index: index)
        }
        guard let heightMM = state.presets[index - 1].heightMM else {
            throw DeskError.presetNotSet(index: index)
        }
        return heightMM
    }

    /// Throws `DeskError.targetOutOfRange` if target falls outside the safe raw range.
    private func guardHeightInRange(_ heightMM: Int) throws {
        guard DeskLimits.safeCommandRange.contains(heightMM) else {
            throw DeskError.targetOutOfRange(heightMM)
        }
    }

    /// Sends the preflight command and waits the required delay.
    private func sendPreflight() async throws {
        try await bleController.write(
            data: DeskCommand.preflight,
            to: DeskUUID.command,
            type: .withoutResponse
        )
        try await clock.sleep(for: presetPreflightDelay)
    }

    /// Starts the background task that drives the desk toward `targetMM`.
    private func startPresetControlLoop(targetMM: Int) {
        let rawTarget = UInt16(targetMM * 10)
        let targetData = DeskCommand.moveTo(tenthsOfMm: rawTarget)
        let controller = bleController
        let clockRef = clock
        let deadline = clock.now().advanced(by: presetTimeout)

        presetMoveTask = Task { [weak self] in
            await self?.runPresetLoop(
                targetMM: targetMM,
                targetData: targetData,
                controller: controller,
                clock: clockRef,
                deadline: deadline
            )
        }
    }

    /// Executes the control loop: writes target every 100ms until arrival or timeout.
    private func runPresetLoop(
        targetMM: Int,
        targetData: Data,
        controller: any BLEControllerProtocol,
        clock: any ClockProtocol,
        deadline: ContinuousClock.Instant
    ) async {
        while !Task.isCancelled {
            if hasArrived(at: targetMM) { break }
            if clock.now() >= deadline { break }
            try? await controller.write(
                data: targetData,
                to: DeskUUID.targetHeartbeat,
                type: .withoutResponse
            )
            try? await clock.sleep(for: presetLoopInterval)
        }
        clearPresetMoveState()
    }

    /// Returns true when desk height is within the arrival tolerance of the target.
    private func hasArrived(at targetMM: Int) -> Bool {
        guard let current = state.heightMM else { return false }
        return abs(current - targetMM) <= presetArrivalToleranceMM
    }

    /// Clears movement and target state after the control loop completes.
    /// Sends stop commands to ensure the desk halts, then resets the movement flags.
    private func clearPresetMoveState() {
        FileLog.debug("clearPresetMoveState: height=\(state.heightMM.map(String.init) ?? "nil")", category: "core")
        // Send stop to ensure desk stops and speed drops to zero.
        Task {
            try? await bleController.write(data: DeskCommand.stop, to: DeskUUID.command, type: .withoutResponse)
            try? await bleController.write(data: DeskCommand.stop, to: DeskUUID.command, type: .withoutResponse)
        }
        updateState {
            $0.isMoving = false
            $0.moveDirection = nil
            $0.speedMMS = 0
            $0.targetPreset = nil
        }
    }
}
