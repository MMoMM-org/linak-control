// NotificationServiceTests.swift
// LinakControlTests — Tests for ConnectionStateObserver notification routing.

import XCTest
@testable import LinakControlKit

// MARK: - MockNotificationPoster

final class MockNotificationPoster: NotificationPosting, @unchecked Sendable {
    private(set) var permissionRequested = false
    private(set) var disconnectedCount = 0
    private(set) var connectedCount = 0
    private(set) var needsReferenceCount = 0

    func requestPermission() { permissionRequested = true }
    func postDisconnected() { disconnectedCount += 1 }
    func postConnected() { connectedCount += 1 }
    func postNeedsReference() { needsReferenceCount += 1 }
}

// MARK: - Test Factories

// makeTempConfigStore and makeDPGStream are provided by TestHelpers.swift

private func makeFiniteHeightStream(values: [Data]) -> AsyncStream<Data> {
    makeDPGStream(responses: values)
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

// MARK: - Unexpected Disconnect Tests

final class ConnectionStateObserverUnexpectedDisconnectTests: XCTestCase {

    func testUnexpectedDisconnectPostsDisconnectedNotification() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let pairedUUID = UUID()
        let store = makeTempConfigStore(pairedUUID: pairedUUID)
        let manager = DeskManager(bleController: mock, configStore: store)
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        try await manager.connect(peripheralId: pairedUUID)

        // Simulate unexpected disconnect (not user-initiated)
        await manager.handleDisconnection()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(poster.disconnectedCount, 1, "Should post one disconnected notification")
        XCTAssertEqual(poster.connectedCount, 0, "Should not post connected on initial connect")

        await manager.disconnect()
    }

    func testUserInitiatedDisconnectDoesNotPostDisconnectedNotification() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let pairedUUID = UUID()
        let store = makeTempConfigStore(pairedUUID: pairedUUID)
        let manager = DeskManager(bleController: mock, configStore: store)
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        try await manager.connect(peripheralId: pairedUUID)

        // User-initiated disconnect
        await manager.disconnect()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(poster.disconnectedCount, 0, "Should not post disconnected on user-initiated disconnect")
    }
}

// MARK: - Reconnect Tests

final class ConnectionStateObserverReconnectTests: XCTestCase {

    func testReconnectAfterUnexpectedDisconnectPostsConnectedNotification() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        configureHappyPath(mock)
        let pairedUUID = UUID()
        let store = makeTempConfigStore(pairedUUID: pairedUUID)
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        // Initial connect (no "Connected" notification expected)
        try await manager.connect(peripheralId: pairedUUID)
        XCTAssertEqual(poster.connectedCount, 0, "Initial connect must not trigger Connected notification")

        // Unexpected disconnect
        await manager.handleDisconnection()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(poster.disconnectedCount, 1)

        // Reconnect succeeds
        configureHappyPath(mock)
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(poster.connectedCount, 1, "Should post Connected notification on reconnect")

        await manager.disconnect()
    }

    func testInitialConnectDoesNotPostConnectedNotification() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        try await manager.connect(peripheralId: UUID())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(poster.connectedCount, 0, "Initial connect must not trigger Connected notification")
        XCTAssertEqual(poster.disconnectedCount, 0, "Initial connect must not trigger Disconnected notification")

        await manager.disconnect()
    }
}

// MARK: - Needs-Reference (Stall) Tests

final class ConnectionStateObserverStallTests: XCTestCase {

    func testMovementStallPostsNeedsReferenceNotification() async throws {
        let clock = TestClock()
        let mock = MockBLEController()
        configureHappyPath(mock)
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store, clock: clock)
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        try await manager.connect(peripheralId: UUID())

        // Start a manual move; the desk height never changes → stall.
        try await manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))
        clock.advance(by: .milliseconds(2100))
        await waitFor { await manager.currentState.needsReference }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            poster.needsReferenceCount, 1,
            "A movement stall must post exactly one needs-reference notification"
        )

        await manager.disconnect()
    }
}
