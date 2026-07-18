// DeskManagerStatusFaultTests.swift
// LinakControlTests — Verifies the desk status characteristic (99fa0003) fast
// path: a pushed fault pulse (E16/E26) stops movement and raises a decoded
// needsReference + faultCode immediately, without waiting for the stall timeout.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

private struct FaultTestSetup {
    let manager: DeskManager
    let mock: MockBLEController
    let heightCont: AsyncStream<Data>.Continuation
    let statusCont: AsyncStream<Data>.Continuation
}

/// Connected manager with live height AND status streams so tests can push a
/// status fault pulse while a move is in progress. Uses the real system clock
/// (the fault path is event-driven, not time-driven).
private func makeFaultTestSetup() async throws -> FaultTestSetup {
    var heightCont: AsyncStream<Data>.Continuation!
    let heightStream = AsyncStream<Data> { heightCont = $0 }
    var statusCont: AsyncStream<Data>.Continuation!
    let statusStream = AsyncStream<Data> { statusCont = $0 }

    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(responses: HandshakeFixtures.happyPathDPGResponses)
    mock.mockNotificationStreams[DeskUUID.height] = heightStream
    mock.mockNotificationStreams[DeskUUID.status] = statusStream

    let store = makeTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store)

    let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
    heightCont.yield(makeHeightPacket(mm: 730))
    try await connectTask.value

    return FaultTestSetup(manager: manager, mock: mock, heightCont: heightCont, statusCont: statusCont)
}

private func stopCount(_ mock: MockBLEController) -> Int {
    mock.writtenData.filter { $0.characteristic == DeskUUID.command && $0.data == DeskCommand.stop }.count
}

// MARK: - Tests

final class DeskManagerStatusFaultTests: XCTestCase {

    func testE16FaultPulseStopsMoveAndSetsCode() async throws {
        let setup = try await makeFaultTestSetup()

        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))

        // Desk pushes the E16 fault pulse.
        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { await setup.manager.currentState.needsReference }

        let state = await setup.manager.currentState
        XCTAssertTrue(state.needsReference, "Fault pulse must raise needsReference")
        XCTAssertEqual(state.faultCode, 0x1e, "Fault code must be recorded")
        XCTAssertFalse(state.isMoving, "Fault must stop movement")
        XCTAssertGreaterThanOrEqual(stopCount(setup.mock), 2, "Fault must send stop twice")
    }

    func testE26FaultPulseSetsCode() async throws {
        let setup = try await makeFaultTestSetup()

        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))

        setup.statusCont.yield(Data([0x01, 0x00, 0x17]))
        await waitFor { await setup.manager.currentState.faultCode == 0x17 }

        let state = await setup.manager.currentState
        XCTAssertTrue(state.needsReference)
        XCTAssertEqual(state.faultCode, 0x17)
    }

    func testOkStatusDoesNotSetNeedsReference() async throws {
        let setup = try await makeFaultTestSetup()

        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))

        // Empty and zero-code payloads are OK — the transient clear pulse must
        // not be treated as fault-resolved OR as a fault.
        setup.statusCont.yield(Data([]))
        setup.statusCont.yield(Data([0x01, 0x00, 0x00]))
        try await Task.sleep(for: .milliseconds(80))

        let state = await setup.manager.currentState
        XCTAssertFalse(state.needsReference, "OK status must not raise needsReference")
        XCTAssertNil(state.faultCode)

        try await setup.manager.stop()
    }

    func testNextMoveClearsFaultCode() async throws {
        let setup = try await makeFaultTestSetup()

        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))
        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { await setup.manager.currentState.needsReference }

        // A fresh move attempt optimistically clears the fault flags.
        try await setup.manager.moveDown(mode: .manual)
        try await Task.sleep(for: .milliseconds(30))
        let state = await setup.manager.currentState
        XCTAssertFalse(state.needsReference)
        XCTAssertNil(state.faultCode)

        try await setup.manager.stop()
    }

    func testFaultPostsCodeSpecificNotification() async throws {
        let setup = try await makeFaultTestSetup()
        let poster = MockNotificationPoster()
        let observer = ConnectionStateObserver(deskManager: setup.manager, notificationPoster: poster)
        let observerTask = observer.start()
        defer { observerTask.cancel() }

        try await setup.manager.moveUp(mode: .manual)
        try await Task.sleep(for: .milliseconds(50))
        setup.statusCont.yield(Data([0x01, 0x00, 0x1e]))
        await waitFor { poster.needsReferenceCount >= 1 }

        XCTAssertEqual(poster.needsReferenceCount, 1)
        XCTAssertTrue(
            poster.lastNeedsReferenceBody?.contains("E16") ?? false,
            "Notification body must be specific to the E16 fault code"
        )
    }
}
