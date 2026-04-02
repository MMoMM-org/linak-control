// DeskManagerMovementTests.swift
// LinakControlTests — Verifies DeskManager movement control behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

/// Returns a connected DeskManager backed by a configured mock and an injected clock.
///
/// The mock is set up with a happy-path handshake using a finite height stream.
/// The returned DeskManager is in `.connected` state and ready for movement commands.
/// Inject a `TestClock` to control time deterministically; the heartbeat and movement
/// loops use this clock for all sleeps.
private func makeConnectedManager(
    clock: any ClockProtocol = SystemClock()
) async throws -> (DeskManager, MockBLEController) {
    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDefaultDPGStream()
    mock.mockNotificationStreams[DeskUUID.height] = makeFiniteHeightStream()

    let store = makeTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store, clock: clock)
    try await manager.connect(peripheralId: UUID())
    return (manager, mock)
}

// makeDPGStream is provided by TestHelpers.swift (call with responses: parameter)

private func makeDefaultDPGStream() -> AsyncStream<Data> {
    makeDPGStream(responses: HandshakeFixtures.happyPathDPGResponses)
}

private func makeFiniteHeightStream() -> AsyncStream<Data> {
    AsyncStream { continuation in
        continuation.yield(HandshakeFixtures.heightNotification730mm)
        continuation.finish()
    }
}

// makeTempConfigStore is provided by TestHelpers.swift

// MARK: - Manual Mode Tests

final class DeskManagerManualUpTests: XCTestCase {

    func testManualUpSendsMoveUpCommandRepeatedly() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveUp(mode: .manual)
        // Advance 400ms = 4 loop iterations at 100ms each
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))
        try await manager.stop()

        let commandWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.moveUp
        }
        XCTAssertGreaterThanOrEqual(
            commandWrites.count, 2,
            "Manual up should send moveUp (0x47 0x00) to command characteristic repeatedly"
        )
    }

    func testManualUpSetsIsMovingTrue() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveUp(mode: .manual)

        let state = await manager.currentState
        XCTAssertTrue(state.isMoving)
        try await manager.stop()
        _ = mock
    }

    func testManualUpSetsMoveDirectionUp() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveUp(mode: .manual)

        let state = await manager.currentState
        XCTAssertEqual(state.moveDirection, .up)
        try await manager.stop()
        _ = mock
    }

    func testManualUpClearsTargetPreset() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveUp(mode: .manual)

        let state = await manager.currentState
        XCTAssertNil(state.targetPreset)
        try await manager.stop()
        _ = mock
    }
}

// MARK: - Manual Down Tests

final class DeskManagerManualDownTests: XCTestCase {

    func testManualDownSendsMoveDownCommandRepeatedly() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveDown(mode: .manual)
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))
        try await manager.stop()

        let commandWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.moveDown
        }
        XCTAssertGreaterThanOrEqual(
            commandWrites.count, 2,
            "Manual down should send moveDown (0x46 0x00) to command characteristic repeatedly"
        )
    }

    func testManualDownSetsMoveDirectionDown() async throws {
        let (manager, mock) = try await makeConnectedManager()

        try await manager.moveDown(mode: .manual)

        let state = await manager.currentState
        XCTAssertEqual(state.moveDirection, .down)
        try await manager.stop()
        _ = mock
    }
}

// MARK: - Stop Tests

final class DeskManagerStopTests: XCTestCase {

    func testStopSendsStopCommandTwice() async throws {
        let (manager, mock) = try await makeConnectedManager()
        try await manager.moveUp(mode: .manual)
        // Clear handshake + movement writes to count stop writes cleanly
        let priorCount = mock.writtenData.count

        try await manager.stop()

        let stopWrites = mock.writtenData.dropFirst(priorCount).filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.stop
        }
        XCTAssertEqual(
            stopWrites.count, 2,
            "stop() must send 0xFF 0x00 to command characteristic exactly twice"
        )
    }

    func testStopSetsIsMovingFalse() async throws {
        let (manager, _) = try await makeConnectedManager()
        try await manager.moveUp(mode: .manual)

        try await manager.stop()

        let state = await manager.currentState
        XCTAssertFalse(state.isMoving)
    }

    func testStopClearsMoveDirection() async throws {
        let (manager, _) = try await makeConnectedManager()
        try await manager.moveUp(mode: .manual)

        try await manager.stop()

        let state = await manager.currentState
        XCTAssertNil(state.moveDirection)
    }

    func testStopThrowsWhenNotConnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.stop()
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Auto Mode Tests

final class DeskManagerAutoUpTests: XCTestCase {

    func testAutoUpSendsPreflightBeforeMoving() async throws {
        let (manager, mock) = try await makeConnectedManager()
        let priorCount = mock.writtenData.count

        try await manager.moveUp(mode: .auto)
        try await manager.stop()

        let postWrites = Array(mock.writtenData.dropFirst(priorCount))
            .filter { $0.characteristic == DeskUUID.command }
        XCTAssertGreaterThanOrEqual(postWrites.count, 1, "Need at least preflight")
        XCTAssertEqual(postWrites[0].data, DeskCommand.preflight, "First command must be preflight")
    }

    func testAutoUpSendsMoveToMaxHeightRepeatedly() async throws {
        let (manager, mock) = try await makeConnectedManager()
        let expectedTarget = DeskCommand.moveTo(tenthsOfMm: DeskLimits.autoUpTargetTenths)

        try await manager.moveUp(mode: .auto)
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))
        try await manager.stop()

        let heartbeatWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.targetHeartbeat && $0.data == expectedTarget
        }
        XCTAssertGreaterThanOrEqual(
            heartbeatWrites.count, 2,
            "Auto up should send move-to max height repeatedly to targetHeartbeat characteristic"
        )
    }
}

final class DeskManagerAutoDownTests: XCTestCase {

    func testAutoDownSendsPreflightBeforeMoving() async throws {
        let (manager, mock) = try await makeConnectedManager()
        let priorCount = mock.writtenData.count

        try await manager.moveDown(mode: .auto)
        try await manager.stop()

        let postWrites = Array(mock.writtenData.dropFirst(priorCount))
            .filter { $0.characteristic == DeskUUID.command }
        XCTAssertGreaterThanOrEqual(postWrites.count, 1, "Need at least preflight")
        XCTAssertEqual(postWrites[0].data, DeskCommand.preflight, "First command must be preflight")
    }

    func testAutoDownSendsMoveToMinHeightRepeatedly() async throws {
        let (manager, mock) = try await makeConnectedManager()
        let expectedTarget = DeskCommand.moveTo(tenthsOfMm: DeskLimits.autoDownTargetTenths)

        try await manager.moveDown(mode: .auto)
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))
        try await manager.stop()

        let heartbeatWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.targetHeartbeat && $0.data == expectedTarget
        }
        XCTAssertGreaterThanOrEqual(
            heartbeatWrites.count, 2,
            "Auto down should send move-to min height repeatedly to targetHeartbeat characteristic"
        )
    }
}

// MARK: - Task Cancellation Tests

final class DeskManagerMovementCancellationTests: XCTestCase {

    func testNewMovementCancelsPreviousMovement() async throws {
        let (manager, mock) = try await makeConnectedManager()

        // Start moving up
        try await manager.moveUp(mode: .manual)
        // Advance 200ms = 2 loop iterations
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))

        // Capture how many up-commands were written before switching direction
        let upCountBefore = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.moveUp
        }.count

        // Start moving down — should cancel the up task
        try await manager.moveDown(mode: .manual)
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(10))
        try await manager.stop()

        let upCountAfter = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.moveUp
        }.count

        // The up task should not have continued writing after moveDown was called
        XCTAssertLessThanOrEqual(
            upCountAfter - upCountBefore, 1,
            "Starting moveDown must cancel the previous moveUp task"
        )

        let downWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.moveDown
        }
        XCTAssertGreaterThanOrEqual(
            downWrites.count, 1,
            "moveDown task must have started writing after cancelling up task"
        )
    }

    func testNewMovementSetsCorrectDirectionAfterSwitch() async throws {
        let (manager, _) = try await makeConnectedManager()

        try await manager.moveUp(mode: .manual)
        try await manager.moveDown(mode: .manual)

        let state = await manager.currentState
        XCTAssertEqual(state.moveDirection, .down)
        try await manager.stop()
    }
}

// MARK: - Not Connected Tests

final class DeskManagerMovementNotConnectedTests: XCTestCase {

    func testMoveUpThrowsWhenNotConnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.moveUp(mode: .manual)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMoveDownThrowsWhenNotConnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.moveDown(mode: .manual)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAutoMoveUpThrowsWhenNotConnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.moveUp(mode: .auto)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
