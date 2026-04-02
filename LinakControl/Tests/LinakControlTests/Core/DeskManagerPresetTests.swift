// DeskManagerPresetTests.swift
// LinakControlTests — Verifies DeskManager preset recall (go-to) behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Test Helpers

/// Result of `makePresetTestSetup` — a fully connected desk manager with a live height stream.
private struct PresetTestSetup {
    let manager: DeskManager
    let mock: MockBLEController
    let heightCont: AsyncStream<Data>.Continuation
}

/// Builds a DeskManager connected to a MockBLEController with a controllable height stream.
///
/// The height stream remains open after this function returns. Call `heightCont.yield(...)`
/// to inject height notifications and `heightCont.finish()` when done.
private func makePresetTestSetup() async throws -> PresetTestSetup {
    var heightCont: AsyncStream<Data>.Continuation!
    let heightStream = AsyncStream<Data> { cont in heightCont = cont }

    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockNotificationStreams[DeskUUID.dpg] = makePresetDPGStream()
    mock.mockNotificationStreams[DeskUUID.height] = heightStream

    let store = makePresetTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store)

    // Run connect in a task so we can emit the initial height to unblock the handshake.
    let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
    heightCont.yield(makePresetHeightPacket(mm: 730))
    try await connectTask.value

    return PresetTestSetup(manager: manager, mock: mock, heightCont: heightCont)
}

private func makePresetDPGStream() -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in HandshakeFixtures.happyPathDPGResponses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

/// Creates a height notification Data packet for the given height in mm.
private func makePresetHeightPacket(mm: Int, speedMMS: Int = 0) -> Data {
    let rawPosition = UInt16(mm * 10)
    let rawSpeed = UInt16(bitPattern: Int16(clamping: speedMMS))
    return Data([
        UInt8(rawPosition & 0xFF),
        UInt8(rawPosition >> 8),
        UInt8(rawSpeed & 0xFF),
        UInt8(rawSpeed >> 8)
    ])
}

private func makePresetTempConfigStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeskManagerPresetTests-\(UUID().uuidString)")
    return ConfigStore(directoryURL: tempDir)
}

// MARK: - Happy Path Tests

final class DeskManagerPresetHappyPathTests: XCTestCase {

    func testGoToPresetSendsPreflightBeforeMoveToCommands() async throws {
        let setup = try await makePresetTestSetup()
        let priorCount = setup.mock.writtenData.count

        // Start moving to preset 2 (1105mm) in a background task
        let goToTask = Task { try await setup.manager.goToPreset(index: 2) }

        // Wait briefly then emit arrival height to let the loop terminate
        try await Task.sleep(for: .milliseconds(50))
        setup.heightCont.yield(makePresetHeightPacket(mm: 1103))
        setup.heightCont.finish()

        try await goToTask.value

        let postWrites = Array(setup.mock.writtenData.dropFirst(priorCount))
        let firstWrite = postWrites.first
        XCTAssertEqual(
            firstWrite?.data, DeskCommand.preflight,
            "goToPreset must send preflight (0x00 0x00) to command characteristic first"
        )
        XCTAssertEqual(firstWrite?.characteristic, DeskUUID.command)
    }

    func testGoToPresetSendsMoveToTargetRepeatedly() async throws {
        let setup = try await makePresetTestSetup()
        let priorCount = setup.mock.writtenData.count

        let goToTask = Task { try await setup.manager.goToPreset(index: 2) }

        // Let the loop run a few iterations before arriving
        try await Task.sleep(for: .milliseconds(350))
        setup.heightCont.yield(makePresetHeightPacket(mm: 1105))
        setup.heightCont.finish()

        try await goToTask.value

        let expectedTarget = DeskCommand.moveTo(tenthsOfMm: UInt16(1105 * 10))
        let heartbeatWrites = setup.mock.writtenData.dropFirst(priorCount).filter {
            $0.characteristic == DeskUUID.targetHeartbeat && $0.data == expectedTarget
        }
        XCTAssertGreaterThanOrEqual(
            heartbeatWrites.count, 2,
            "goToPreset must send move-to 1105mm to targetHeartbeat repeatedly (at least twice in 350ms)"
        )
    }

    func testGoToPresetSetsTargetPresetDuringMovement() async throws {
        let setup = try await makePresetTestSetup()

        let goToTask = Task { try await setup.manager.goToPreset(index: 2) }

        // Check state during movement (before arrival)
        try await Task.sleep(for: .milliseconds(50))
        let movingState = await setup.manager.currentState
        XCTAssertEqual(movingState.targetPreset, 2)
        XCTAssertTrue(movingState.isMoving)

        // Emit arrival and finish
        setup.heightCont.yield(makePresetHeightPacket(mm: 1105))
        setup.heightCont.finish()
        try await goToTask.value
    }

    func testGoToPresetClearsTargetPresetOnArrival() async throws {
        let setup = try await makePresetTestSetup()

        let goToTask = Task { try await setup.manager.goToPreset(index: 2) }

        try await Task.sleep(for: .milliseconds(50))
        setup.heightCont.yield(makePresetHeightPacket(mm: 1103))
        setup.heightCont.finish()

        try await goToTask.value

        let state = await setup.manager.currentState
        XCTAssertNil(state.targetPreset, "targetPreset must be nil after arrival")
        XCTAssertFalse(state.isMoving, "isMoving must be false after arrival")
    }

    func testGoToPresetArrivalWithinFiveMmTolerance() async throws {
        let setup = try await makePresetTestSetup()

        // Preset 2 = 1105mm; arrive at exactly 1100mm (5mm under — boundary of tolerance)
        let goToTask = Task { try await setup.manager.goToPreset(index: 2) }

        try await Task.sleep(for: .milliseconds(50))
        setup.heightCont.yield(makePresetHeightPacket(mm: 1100))
        setup.heightCont.finish()

        try await goToTask.value

        let state = await setup.manager.currentState
        XCTAssertNil(state.targetPreset, "Must detect arrival at exactly 5mm tolerance boundary")
    }
}

// MARK: - Unset Preset Tests

final class DeskManagerPresetUnsetTests: XCTestCase {

    func testGoToPresetThrowsWhenPresetHasNoHeight() async throws {
        // Preset 4 is unset (heightMM = nil from HandshakeFixtures.preset4Unset)
        let setup = try await makePresetTestSetup()

        do {
            try await setup.manager.goToPreset(index: 4)
            XCTFail("Expected DeskError.presetNotSet")
        } catch DeskError.presetNotSet(let index) {
            XCTAssertEqual(index, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        setup.heightCont.finish()
    }

    func testGoToPresetWithUnsetPresetDoesNotChangeState() async throws {
        let setup = try await makePresetTestSetup()

        try? await setup.manager.goToPreset(index: 4)

        let state = await setup.manager.currentState
        XCTAssertNil(state.targetPreset, "targetPreset must not be set when preset is unset")
        XCTAssertFalse(state.isMoving, "isMoving must not be set when preset is unset")

        setup.heightCont.finish()
    }
}

// MARK: - Not Connected Tests

final class DeskManagerPresetNotConnectedTests: XCTestCase {

    func testGoToPresetThrowsWhenNotConnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makePresetTempConfigStore())

        do {
            try await manager.goToPreset(index: 1)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Cancellation Tests

final class DeskManagerPresetCancellationTests: XCTestCase {

    func testNewGoToPresetCancelsPreviousMove() async throws {
        let setup = try await makePresetTestSetup()

        // Start moving to preset 1 (730mm) — won't arrive (no matching height emitted)
        let firstTask = Task { try? await setup.manager.goToPreset(index: 1) }
        try await Task.sleep(for: .milliseconds(50))

        // Verify first move is active
        let midState = await setup.manager.currentState
        XCTAssertEqual(midState.targetPreset, 1, "First goToPreset must set targetPreset to 1")

        // Start moving to preset 2 (1105mm) — must cancel the first
        let secondTask = Task { try await setup.manager.goToPreset(index: 2) }

        // Poll until targetPreset updates to 2, giving the actor time to process the second call.
        var switchedState = await setup.manager.currentState
        for _ in 0..<20 {
            if switchedState.targetPreset == 2 { break }
            try await Task.sleep(for: .milliseconds(25))
            switchedState = await setup.manager.currentState
        }

        XCTAssertEqual(
            switchedState.targetPreset, 2,
            "Second goToPreset must cancel first and switch targetPreset to 2"
        )

        // Emit arrival for preset 2 and clean up
        setup.heightCont.yield(makePresetHeightPacket(mm: 1105))
        setup.heightCont.finish()

        try await secondTask.value
        firstTask.cancel()
        _ = await firstTask.result
    }

    func testStopCancelsPresetMove() async throws {
        let setup = try await makePresetTestSetup()

        // Start a preset move that won't arrive naturally
        let goToTask = Task { try? await setup.manager.goToPreset(index: 2) }
        try await Task.sleep(for: .milliseconds(50))

        // stop() must cancel the preset move and clear state
        try await setup.manager.stop()

        let state = await setup.manager.currentState
        XCTAssertNil(state.targetPreset, "stop() must clear targetPreset")
        XCTAssertFalse(state.isMoving, "stop() must clear isMoving")

        setup.heightCont.finish()
        goToTask.cancel()
        _ = await goToTask.result
    }
}

// MARK: - Safety Validation Tests

final class DeskManagerPresetSafetyTests: XCTestCase {

    func testGoToPresetRejectsTargetBelowMinimum() async throws {
        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask

        // Craft DPG responses with preset 1 at 500mm (out of range)
        // 500mm = 5000 tenths = 0x1388 -> lo=0x88, hi=0x13
        // DPG format: [status, length, slot, height_lo, height_hi, ...]
        let preset1At500mm = Data([0x01, 0x07, 0x01, 0x88, 0x13, 0x00, 0x00, 0x00, 0x00])
        var dpgResponses = HandshakeFixtures.happyPathDPGResponses
        // Index 5 = preset 1 (after USER_ID read/write ack + caps + capsExt + offset)
        dpgResponses[5] = preset1At500mm

        mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { cont in
            for r in dpgResponses { cont.yield(r) }
            cont.finish()
        }

        var heightCont: AsyncStream<Data>.Continuation!
        mock.mockNotificationStreams[DeskUUID.height] = AsyncStream { cont in heightCont = cont }

        let manager = DeskManager(bleController: mock, configStore: makePresetTempConfigStore())
        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makePresetHeightPacket(mm: 730))
        try await connectTask.value

        do {
            try await manager.goToPreset(index: 1)
            XCTFail("Expected DeskError.targetOutOfRange")
        } catch DeskError.targetOutOfRange(let height) {
            XCTAssertEqual(height, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        heightCont.finish()
    }

    func testGoToPresetRejectsTargetAboveMaximum() async throws {
        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask

        // Preset 1 at 1400mm (out of range)
        // 1400mm = 14000 tenths = 0x36B0 -> lo=0xB0, hi=0x36
        // DPG format: [status, length, slot, height_lo, height_hi, ...]
        let preset1At1400mm = Data([0x01, 0x07, 0x01, 0xB0, 0x36, 0x00, 0x00, 0x00, 0x00])
        var dpgResponses = HandshakeFixtures.happyPathDPGResponses
        // Index 5 = preset 1 (after USER_ID read/write ack + caps + capsExt + offset)
        dpgResponses[5] = preset1At1400mm

        mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { cont in
            for r in dpgResponses { cont.yield(r) }
            cont.finish()
        }

        var heightCont: AsyncStream<Data>.Continuation!
        mock.mockNotificationStreams[DeskUUID.height] = AsyncStream { cont in heightCont = cont }

        let manager = DeskManager(bleController: mock, configStore: makePresetTempConfigStore())
        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makePresetHeightPacket(mm: 730))
        try await connectTask.value

        do {
            try await manager.goToPreset(index: 1)
            XCTFail("Expected DeskError.targetOutOfRange")
        } catch DeskError.targetOutOfRange(let height) {
            XCTAssertEqual(height, 1400)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        heightCont.finish()
    }
}
