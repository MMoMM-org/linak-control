// DeskManagerReconnectionTests.swift
// LinakControlTests — Tests for reconnection, wake-up, and heartbeat behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Shared Fixtures

private let pairedDeskUUID = UUID()

// MARK: - Test Factories

// makeTempConfigStore is provided by TestHelpers.swift (with pairedUUID: parameter)

private func makeManager(
    mock: MockBLEController,
    clock: TestClock,
    pairedUUID: UUID = pairedDeskUUID
) -> DeskManager {
    let store = makeTempConfigStore(pairedUUID: pairedUUID)
    return DeskManager(bleController: mock, configStore: store, clock: clock)
}

private func makeConnectedManager(
    mock: MockBLEController,
    clock: TestClock,
    pairedUUID: UUID = pairedDeskUUID
) async throws -> DeskManager {
    configureHappyPath(mock)
    let manager = makeManager(mock: mock, clock: clock, pairedUUID: pairedUUID)
    try await manager.connect(peripheralId: pairedUUID)
    return manager
}

private func configureHappyPath(_ mock: MockBLEController) {
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
        responses: HandshakeFixtures.happyPathDPGResponses
    )
    mock.mockNotificationStreams[DeskUUID.height] = makeFiniteHeightStream(
        values: [HandshakeFixtures.heightNotification730mm]
    )
}

// makeDPGStream is provided by TestHelpers.swift

private func makeFiniteHeightStream(values: [Data]) -> AsyncStream<Data> {
    makeDPGStream(responses: values)
}

private func heartbeatWrites(in mock: MockBLEController) -> Int {
    mock.writtenData.filter {
        $0.characteristic == DeskUUID.targetHeartbeat && $0.data == DeskCommand.heartbeat
    }.count
}

// MARK: - Reconnection Backoff Tests

final class DeskManagerReconnectionBackoffTests: XCTestCase {

    func testReconnectionStartsAfterFirstBackoffWindow() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.shouldFailConnect = true
        let countBeforeDisconnect = mock.connectCallCount

        await manager.handleDisconnection()

        // Before 1s — no reconnection attempt
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mock.connectCallCount, countBeforeDisconnect,
            "Should not reconnect before the 1s window")

        // Advance 1s — first attempt fires
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mock.connectCallCount, countBeforeDisconnect + 1,
            "Should attempt reconnect after 1s")

        await manager.disconnect()
    }

    func testReconnectionBackoffDoublesOnEachFailure() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.shouldFailConnect = true
        let base = mock.connectCallCount

        await manager.handleDisconnection()

        // Allow the reconnection task to start and register its first clock.sleep.
        try await Task.sleep(for: .milliseconds(50))

        // Attempt 1 — after 1s
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mock.connectCallCount, base + 1)

        // Attempt 2 — after another 2s
        clock.advance(by: .seconds(2))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mock.connectCallCount, base + 2)

        // Attempt 3 — after another 4s
        clock.advance(by: .seconds(4))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mock.connectCallCount, base + 3)

        // Attempt 4 — after another 8s
        clock.advance(by: .seconds(8))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mock.connectCallCount, base + 4)

        await manager.disconnect()
    }

    func testBackoffIsCappedAt60Seconds() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.shouldFailConnect = true
        await manager.handleDisconnection()

        // Drive through 6 failures using actual backoff: 1, 2, 4, 8, 16, 32
        for i in 0..<6 {
            let delay = 1 << i  // 1, 2, 4, 8, 16, 32
            clock.advance(by: .seconds(delay))
            try await Task.sleep(for: .milliseconds(50))
        }

        let attemptsAfterSixFailures = mock.connectCallCount

        // 7th attempt should fire after 60s (capped from 64)
        clock.advance(by: .seconds(60))
        try await Task.sleep(for: .milliseconds(50))

        // 8th attempt also after 60s
        clock.advance(by: .seconds(60))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mock.connectCallCount, attemptsAfterSixFailures + 2,
            "After cap, each 60s window produces exactly one attempt")

        await manager.disconnect()
    }

    func testReconnectSuccessAfterTwoFailures() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.shouldFailConnect = true
        await manager.handleDisconnection()

        // Fail attempt 1
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))

        // Fail attempt 2
        clock.advance(by: .seconds(2))
        try await Task.sleep(for: .milliseconds(50))

        // Configure success for attempt 3
        mock.shouldFailConnect = false
        configureHappyPath(mock)

        clock.advance(by: .seconds(4))
        try await Task.sleep(for: .milliseconds(100))

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .connected,
            "Should be connected after successful reconnect on attempt 3")
    }

    func testUserDisconnectCancelsReconnection() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.shouldFailConnect = true
        await manager.handleDisconnection()

        // User disconnects before any retry fires
        await manager.disconnect()
        let countAfterUserDisconnect = mock.connectCallCount

        // Advance past the backoff window
        clock.advance(by: .seconds(5))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mock.connectCallCount, countAfterUserDisconnect,
            "Reconnection task should be cancelled when user disconnects")
    }
}

// MARK: - Wake-Up Sequence Tests

final class DeskManagerWakeUpTests: XCTestCase {

    func testWakeUpWritesFE00ThenFF00() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        // Height read succeeds so desk "responds" on first attempt
        mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm

        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)

        try await manager.wakeUpDesk()

        let commandWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.command }
        XCTAssertGreaterThanOrEqual(commandWrites.count, 2,
            "Should write at least wakeUp + stop")
        XCTAssertEqual(commandWrites[0].data, DeskCommand.wakeUp, "First write must be FE 00")
        XCTAssertEqual(commandWrites[1].data, DeskCommand.stop, "Second write must be FF 00")
    }

    func testWakeUpSucceedsWhenDeskRespondsOnFirstAttempt() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm

        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)

        // Should not throw
        try await manager.wakeUpDesk()
    }

    func testWakeUpThrowsWakeUpFailedWhenDeskNeverResponds() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        // No height read response — deskIsResponding() returns false every time

        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)

        do {
            try await manager.wakeUpDesk()
            XCTFail("Expected DeskError.wakeUpFailed")
        } catch DeskError.wakeUpFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWakeUpSendsThreeAttemptsBeforeGivingUp() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        // No height read response — all 3 attempts will fail

        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)

        try? await manager.wakeUpDesk()

        let wakeWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.wakeUp
        }
        let stopWrites = mock.writtenData.filter {
            $0.characteristic == DeskUUID.command && $0.data == DeskCommand.stop
        }

        XCTAssertEqual(wakeWrites.count, 3, "Should send FE 00 exactly three times")
        XCTAssertEqual(stopWrites.count, 3, "Should send FF 00 exactly three times")
    }
}

// MARK: - Heartbeat Tests

final class DeskManagerHeartbeatTests: XCTestCase {

    func testHeartbeatWritesEverySecondAfterConnect() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        mock.writtenData.removeAll()

        // Allow the heartbeat task to register its clock.sleep before we advance time.
        try await Task.sleep(for: .milliseconds(50))

        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(heartbeatWrites(in: mock), 1, "One heartbeat per second")

        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(heartbeatWrites(in: mock), 2, "Two heartbeats after 2 seconds")

        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(heartbeatWrites(in: mock), 3, "Three heartbeats after 3 seconds")

        await manager.disconnect()
    }

    /// Issue #14: 0x0031 is the reference-input characteristic and the desk
    /// reads a write there as a target position. While the desk asks to be
    /// re-referenced the user is running the initialisation procedure on the
    /// control box, and any write aborts it — so the heartbeat must go quiet.
    ///
    /// Note both pre-existing guards are inactive here: the stall clears
    /// `isMoving`, and `moveUp` has just recorded a user action. This test
    /// therefore isolates the `needsReference` guard.
    func testHeartbeatPausesWhileDeskNeedsReference() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        // Force a stall so the desk asks to be re-referenced.
        try await manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))
        clock.advance(by: .milliseconds(2100))
        await waitFor { await manager.currentState.needsReference }

        let moving = await manager.currentState.isMoving
        XCTAssertFalse(moving, "Precondition: the stall must have cleared isMoving")

        mock.writtenData.removeAll()
        try await Task.sleep(for: .milliseconds(50))

        // The control box needs the channel free for the whole procedure.
        for _ in 0..<3 {
            clock.advance(by: .seconds(1))
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(
            heartbeatWrites(in: mock), 0,
            "Heartbeat must stay silent while the desk needs a re-reference"
        )

        await manager.disconnect()
    }

    /// The suppression must not be permanent — otherwise the desk would sleep.
    /// The next move from the app clears `needsReference`, and once that move
    /// ends the keep-alive resumes.
    func testHeartbeatResumesAfterNextMoveClearsNeedsReference() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        try await manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))
        clock.advance(by: .milliseconds(2100))
        await waitFor { await manager.currentState.needsReference }

        // A new move clears the flag optimistically; stopping it clears isMoving.
        try await manager.moveUp(mode: .manual)
        try await manager.stop()
        await waitFor { await manager.currentState.needsReference == false }

        mock.writtenData.removeAll()
        try await Task.sleep(for: .milliseconds(50))

        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            heartbeatWrites(in: mock), 1,
            "Heartbeat must resume once the desk no longer needs a re-reference"
        )

        await manager.disconnect()
    }

    func testHeartbeatPausesAfter10MinutesOfIdle() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        // Record a user action at time T=0
        await manager.setLastUserActionForTesting(clock.now())

        // Advance 601 seconds — past the 10-minute idle threshold
        clock.advance(by: .seconds(601))
        try await Task.sleep(for: .milliseconds(50))

        // Clear all writes that happened during those 601 seconds
        mock.writtenData.removeAll()

        // Advance 1 more second — heartbeat should NOT fire (desk is idle)
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(heartbeatWrites(in: mock), 0,
            "Heartbeat should be paused after 10 min of no user action")

        await manager.disconnect()
    }

    func testHeartbeatResumesAfterUserAction() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        // Set last user action to right now
        await manager.setLastUserActionForTesting(clock.now())

        // Advance past idle timeout
        clock.advance(by: .seconds(601))
        try await Task.sleep(for: .milliseconds(50))

        // Simulate user action — refresh lastUserAction to current (post-advance) time
        await manager.setLastUserActionForTesting(clock.now())
        mock.writtenData.removeAll()

        // Advance 1 second — heartbeat should fire again
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(heartbeatWrites(in: mock), 1,
            "Heartbeat should resume after a user action")

        await manager.disconnect()
    }

    func testHeartbeatStopsAfterDisconnect() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        let manager = try await makeConnectedManager(mock: mock, clock: clock)

        await manager.disconnect()
        mock.writtenData.removeAll()

        clock.advance(by: .seconds(3))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(heartbeatWrites(in: mock), 0,
            "No heartbeat writes should occur after disconnect")
    }
}
