// DeskManagerTests.swift
// LinakControlTests — Verifies DeskManager state machine and coordination behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

/// Configures a MockBLEController with a happy-path handshake.
///
/// Uses a finite height stream that terminates after yielding `heightValues`.
/// The DeskManager's post-connect listener will then iterate the same stream
/// (the underlying continuation buffer is shared).
private func configureHappyPath(
    _ mock: MockBLEController,
    heightValues: [Data] = [HandshakeFixtures.heightNotification730mm]
) {
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
        responses: HandshakeFixtures.happyPathDPGResponses
    )
    mock.mockNotificationStreams[DeskUUID.height] = makeFiniteHeightStream(values: heightValues)
}

private func makeDPGStream(responses: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in responses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

private func makeFiniteHeightStream(values: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for value in values {
            continuation.yield(value)
        }
        continuation.finish()
    }
}

/// Creates a height notification Data packet for the given height in mm.
///
/// Matches the layout expected by `parseHeightNotification(_:)`:
/// - Bytes [0:1]: position as little-endian uint16 in 0.1 mm units
/// - Bytes [2:3]: speed as little-endian int16 raw units
private func makeHeightPacket(mm: Int, speedMMS: Int = 0) -> Data {
    let rawPosition = UInt16(mm * 10)
    let rawSpeed = UInt16(bitPattern: Int16(clamping: speedMMS))
    return Data([
        UInt8(rawPosition & 0xFF),
        UInt8(rawPosition >> 8),
        UInt8(rawSpeed & 0xFF),
        UInt8(rawSpeed >> 8)
    ])
}

/// Builds a ConfigStore backed by a temp directory so tests don't touch disk.
private func makeTempConfigStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeskManagerTests-\(UUID().uuidString)")
    return ConfigStore(directoryURL: tempDir)
}

// MARK: - Initial State Tests

final class DeskManagerInitialStateTests: XCTestCase {

    func testStartsDisconnected() async {
        let mock = MockBLEController()
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected)
    }

    func testStartsWithFourEmptyPresetSlots() async {
        let mock = MockBLEController()
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)

        let state = await manager.currentState
        XCTAssertEqual(state.presets.count, 4)
        for preset in state.presets {
            XCTAssertNil(preset.heightMM)
        }
    }

    func testStartsNotMoving() async {
        let mock = MockBLEController()
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)

        let state = await manager.currentState
        XCTAssertFalse(state.isMoving)
    }
}

// MARK: - Connect Happy Path Tests

final class DeskManagerConnectHappyPathTests: XCTestCase {

    func testConnectSetsStateToConnected() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        try await manager.connect(peripheralId: UUID())

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .connected)
    }

    func testConnectPopulatesPresetHeightsFromHandshake() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        try await manager.connect(peripheralId: UUID())

        let state = await manager.currentState
        XCTAssertEqual(state.presets.count, 4)
        XCTAssertEqual(state.presets[0].heightMM, 730)
        XCTAssertEqual(state.presets[1].heightMM, 1105)
        XCTAssertEqual(state.presets[2].heightMM, 900)
        XCTAssertNil(state.presets[3].heightMM)
    }

    func testConnectSetsCurrentHeightFromHandshake() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock, heightValues: [HandshakeFixtures.heightNotification730mm])
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        try await manager.connect(peripheralId: UUID())

        let state = await manager.currentState
        XCTAssertEqual(state.heightMM, 730)
    }

    func testConnectSavesPairedDeskUUIDToConfig() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let store = makeTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)
        let expectedUUID = UUID()

        try await manager.connect(peripheralId: expectedUUID)

        let config = try store.load()
        XCTAssertEqual(config.pairedDeskUUID, expectedUUID.uuidString)
    }
}

// MARK: - Connect Failure Tests

final class DeskManagerConnectFailureTests: XCTestCase {

    func testConnectFailureResetsStateToDisconnected() async {
        let mock = MockBLEController()
        mock.shouldFailConnect = true
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        try? await manager.connect(peripheralId: UUID())

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected)
    }

    func testConnectFailureRethrowsUnderlyingError() async {
        let mock = MockBLEController()
        mock.shouldFailConnect = true
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.connect(peripheralId: UUID())
            XCTFail("Expected error to be thrown")
        } catch BLEError.connectionFailed {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testHandshakeFailureResetsStateToDisconnected() async {
        let mock = MockBLEController()
        // Missing outputMask causes handshake to throw BLEError.characteristicNotFound
        mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
            responses: HandshakeFixtures.happyPathDPGResponses
        )
        mock.mockNotificationStreams[DeskUUID.height] = makeFiniteHeightStream(values: [])
        // Intentionally omit mockReadResponses[DeskUUID.outputMask]
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        try? await manager.connect(peripheralId: UUID())

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected)
    }
}

// MARK: - Disconnect Tests

final class DeskManagerDisconnectTests: XCTestCase {

    func testDisconnectFromConnectedResetsStateToDisconnected() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())
        try await manager.connect(peripheralId: UUID())

        await manager.disconnect()

        let state = await manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected)
    }

    func testDisconnectClearsHeightAndMovement() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())
        try await manager.connect(peripheralId: UUID())

        await manager.disconnect()

        let state = await manager.currentState
        XCTAssertNil(state.heightMM)
        XCTAssertNil(state.speedMMS)
        XCTAssertFalse(state.isMoving)
    }

    func testDisconnectPreservesPresetSlotCount() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())
        try await manager.connect(peripheralId: UUID())

        await manager.disconnect()

        let state = await manager.currentState
        XCTAssertEqual(state.presets.count, 4)
    }
}

// MARK: - Height Notification Tests

final class DeskManagerHeightNotificationTests: XCTestCase {

    func testHeightNotificationsUpdateStateHeightMM() async throws {
        let mock = MockBLEController()

        // Use a continuation stream so we can inject values after the handshake
        var heightCont: AsyncStream<Data>.Continuation!
        let heightStream = AsyncStream<Data> { cont in heightCont = cont }
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
            responses: HandshakeFixtures.happyPathDPGResponses
        )
        mock.mockNotificationStreams[DeskUUID.height] = heightStream

        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        // Connect — handshake firstHeightNotification will wait; emit one to unblock it
        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makeHeightPacket(mm: 730))
        try await connectTask.value

        // Emit a post-connect height notification
        heightCont.yield(makeHeightPacket(mm: 900))
        heightCont.finish()

        // Allow the height listener task to process
        try await Task.sleep(for: .milliseconds(50))

        let state = await manager.currentState
        XCTAssertEqual(state.heightMM, 900)
    }

    func testHeightNotificationsSetIsMovingWhenSpeedNonZero() async throws {
        let mock = MockBLEController()

        var heightCont: AsyncStream<Data>.Continuation!
        let heightStream = AsyncStream<Data> { cont in heightCont = cont }
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
            responses: HandshakeFixtures.happyPathDPGResponses
        )
        mock.mockNotificationStreams[DeskUUID.height] = heightStream

        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makeHeightPacket(mm: 730))
        try await connectTask.value

        // Emit moving notification
        heightCont.yield(makeHeightPacket(mm: 800, speedMMS: 10))
        heightCont.finish()

        try await Task.sleep(for: .milliseconds(50))

        let state = await manager.currentState
        XCTAssertTrue(state.isMoving)
        XCTAssertEqual(state.moveDirection, .up)
    }

    func testHeightNotificationsSetIsMovingFalseWhenSpeedZero() async throws {
        let mock = MockBLEController()

        var heightCont: AsyncStream<Data>.Continuation!
        let heightStream = AsyncStream<Data> { cont in heightCont = cont }
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
            responses: HandshakeFixtures.happyPathDPGResponses
        )
        mock.mockNotificationStreams[DeskUUID.height] = heightStream

        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makeHeightPacket(mm: 730))
        try await connectTask.value

        // Emit stationary notification
        heightCont.yield(makeHeightPacket(mm: 730, speedMMS: 0))
        heightCont.finish()

        try await Task.sleep(for: .milliseconds(50))

        let state = await manager.currentState
        XCTAssertFalse(state.isMoving)
        XCTAssertNil(state.moveDirection)
    }

    func testHeightNotificationsUpdateActivePresetWhenAtPresetHeight() async throws {
        let mock = MockBLEController()

        var heightCont: AsyncStream<Data>.Continuation!
        let heightStream = AsyncStream<Data> { cont in heightCont = cont }
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
            responses: HandshakeFixtures.happyPathDPGResponses
        )
        mock.mockNotificationStreams[DeskUUID.height] = heightStream

        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
        heightCont.yield(makeHeightPacket(mm: 730))
        try await connectTask.value

        // Preset 1 = 730 mm; emit height at exactly that position, stationary
        heightCont.yield(makeHeightPacket(mm: 730, speedMMS: 0))
        heightCont.finish()

        try await Task.sleep(for: .milliseconds(50))

        let state = await manager.currentState
        XCTAssertEqual(state.activePreset, 1)
    }
}

// MARK: - State Stream Tests

final class DeskManagerStateStreamTests: XCTestCase {

    func testStateStreamYieldsOnConnect() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        var receivedStates: [ConnectionState] = []
        let streamTask = Task {
            for await state in await manager.stateStream {
                receivedStates.append(state.connectionState)
                if state.connectionState == .connected { break }
            }
        }

        try await manager.connect(peripheralId: UUID())
        streamTask.cancel()
        await streamTask.value

        XCTAssertTrue(
            receivedStates.contains(.connecting),
            "Stream must yield .connecting during connect"
        )
        XCTAssertTrue(
            receivedStates.contains(.connected),
            "Stream must yield .connected after successful handshake"
        )
    }

    func testStateStreamYieldsOnDisconnect() async throws {
        let mock = MockBLEController()
        configureHappyPath(mock)
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())
        try await manager.connect(peripheralId: UUID())

        var receivedStates: [ConnectionState] = []
        let streamTask = Task {
            for await state in await manager.stateStream {
                receivedStates.append(state.connectionState)
                if state.connectionState == .disconnected { break }
            }
        }

        await manager.disconnect()
        await streamTask.value

        XCTAssertTrue(
            receivedStates.contains(.disconnected),
            "Stream must yield .disconnected after disconnect"
        )
    }
}

// MARK: - Movement Stub Tests

final class DeskManagerMovementStubTests: XCTestCase {

    func testMoveUpThrowsNotConnectedWhenDisconnected() async {
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

    func testMoveDownThrowsNotConnectedWhenDisconnected() async {
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

    func testStopThrowsNotConnectedWhenDisconnected() async {
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

    func testGoToPresetThrowsNotConnectedWhenDisconnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.goToPreset(index: 1)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSavePresetThrowsNotConnectedWhenDisconnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.savePreset(index: 1)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
