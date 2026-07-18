// DeskManagerStandDownTests.swift
// LinakControlTests — Verifies the fault stand-down behaviour: on a fault the
// app releases BLE (so the desk can be manually initialised) while preserving
// the fault reason, and a subsequent movement auto-reconnects.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

private let standDownPairedUUID = UUID()

private struct StandDownSetup {
    let manager: DeskManager
    let mock: MockBLEController
    let statusCont: AsyncStream<Data>.Continuation
}

/// Connected manager with a paired UUID and a live status stream so tests can
/// push a fault pulse.
private func makeStandDownSetup() async throws -> StandDownSetup {
    var statusCont: AsyncStream<Data>.Continuation!
    let statusStream = AsyncStream<Data> { statusCont = $0 }
    var heightCont: AsyncStream<Data>.Continuation!
    let heightStream = AsyncStream<Data> { heightCont = $0 }

    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(responses: HandshakeFixtures.happyPathDPGResponses)
    mock.mockNotificationStreams[DeskUUID.height] = heightStream
    mock.mockNotificationStreams[DeskUUID.status] = statusStream

    let store = makeTempConfigStore(pairedUUID: standDownPairedUUID)
    let manager = DeskManager(bleController: mock, configStore: store)

    let connectTask = Task { try await manager.connect(peripheralId: standDownPairedUUID) }
    heightCont.yield(makeHeightPacket(mm: 730))
    try await connectTask.value

    return StandDownSetup(manager: manager, mock: mock, statusCont: statusCont)
}

/// Re-arms the finite handshake streams so a reconnect can complete.
private func rearmHandshake(_ mock: MockBLEController) {
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(responses: HandshakeFixtures.happyPathDPGResponses)
    mock.mockNotificationStreams[DeskUUID.height] = makeDPGStream(responses: [HandshakeFixtures.heightNotification730mm])
}

final class DeskManagerStandDownTests: XCTestCase {

    func testStandDownDisconnectsButPreservesFault() async throws {
        let setup = try await makeStandDownSetup()

        setup.statusCont.yield(Data([0x01, 0x00, 0x1e])) // E16
        await waitFor { await setup.manager.currentState.needsReference }

        await setup.manager.standDown()

        let state = await setup.manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected, "Stand-down releases BLE")
        XCTAssertTrue(state.needsReference, "Fault flag must survive stand-down")
        XCTAssertEqual(state.faultCode, 0x1e, "Fault code must survive stand-down")
        XCTAssertFalse(state.isMoving)
    }

    func testConnectClearsPreservedFault() async throws {
        let setup = try await makeStandDownSetup()
        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { await setup.manager.currentState.needsReference }
        await setup.manager.standDown()

        rearmHandshake(setup.mock)
        try await setup.manager.connect(peripheralId: standDownPairedUUID)

        let state = await setup.manager.currentState
        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertFalse(state.needsReference, "A fresh connection clears the fault")
        XCTAssertNil(state.faultCode)
    }

    func testObserverStandsDownOnFaultWithoutDisconnectNotification() async throws {
        let setup = try await makeStandDownSetup()
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: setup.manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { await setup.manager.currentState.connectionState == .disconnected }
        try await Task.sleep(for: .milliseconds(50))

        let state = await setup.manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected, "Observer must stand the app down on fault")
        XCTAssertTrue(state.needsReference)
        XCTAssertEqual(poster.needsReferenceCount, 1)
        XCTAssertEqual(poster.disconnectedCount, 0, "Stand-down must not post a Disconnected notification")
    }

    func testMoveAutoReconnectsAfterStandDown() async throws {
        let setup = try await makeStandDownSetup()
        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { await setup.manager.currentState.needsReference }
        await setup.manager.standDown()
        let connectsBefore = setup.mock.connectCallCount

        rearmHandshake(setup.mock)
        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertGreaterThan(setup.mock.connectCallCount, connectsBefore, "A move must auto-reconnect")
        let reconnectedState = await setup.manager.currentState.connectionState
        XCTAssertEqual(reconnectedState, .connected)

        try await setup.manager.stop()
    }

    func testMoveWithoutPairedDeskThrows() async throws {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.moveUp(mode: .manual)
            XCTFail("Expected DeskError.notConnected without a paired desk")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
