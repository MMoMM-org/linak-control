// UIBLEIntegrationTests.swift
// LinakControlTests — Integration tests wiring DeskViewModel → DeskManager → MockBLEController.
//
// These tests exercise the full preset-switch data flow end-to-end. Only the BLE
// transport layer is mocked — DeskManager and DeskViewModel are real instances.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Shared setup

/// A connected integration harness: real DeskViewModel → real DeskManager → MockBLEController.
private struct UIBLEHarness {
    let viewModel: DeskViewModel
    let manager: DeskManager
    let mock: MockBLEController
    let heightCont: AsyncStream<Data>.Continuation
}

/// Builds a fully connected harness with preset heights loaded from HandshakeFixtures.
///
/// Preset heights after handshake:
///   preset 1 = 730 mm, preset 2 = 1105 mm, preset 3 = 900 mm, preset 4 = unset
private func makeConnectedHarness() async throws -> UIBLEHarness {
    var heightCont: AsyncStream<Data>.Continuation!
    let heightStream = AsyncStream<Data> { cont in heightCont = cont }

    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = makeHarnessDPGStream()
    mock.mockNotificationStreams[DeskUUID.height] = heightStream

    let store = makeIntegrationTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store)
    let viewModel = await DeskViewModel(deskManager: manager, configStore: store)

    // Connect while emitting the initial height so the handshake can complete.
    let connectTask = Task { try await manager.connect(peripheralId: UUID()) }
    heightCont.yield(makeHeightPacket(mm: 730))
    try await connectTask.value

    return UIBLEHarness(
        viewModel: viewModel,
        manager: manager,
        mock: mock,
        heightCont: heightCont
    )
}

private func makeHarnessDPGStream() -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in HandshakeFixtures.happyPathDPGResponses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

/// Encodes a height notification packet (4 bytes, little-endian position and speed).
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

private func makeIntegrationTempConfigStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("UIBLEIntegrationTests-\(UUID().uuidString)")
    return ConfigStore(directoryURL: tempDir)
}

/// Polls until the predicate returns true or the timeout elapses.
private func waitFor(
    timeout: TimeInterval = 2.0,
    predicate: @escaping () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - Preset switch end-to-end

@MainActor
final class UIBLEPresetSwitchTests: XCTestCase {

    /// Verifies that calling goToPreset on the view model causes the BLE layer to receive
    /// a preflight command followed by move-to heartbeats targeting the correct height.
    func testPresetSwitchEndToEnd() async throws {
        let harness = try await makeConnectedHarness()
        let priorWriteCount = harness.mock.writtenData.count

        // Trigger the preset switch through the view model (fire-and-forget).
        harness.viewModel.goToPreset(index: 2)

        // Allow the preflight and first heartbeat to be written before arriving.
        try await Task.sleep(for: .milliseconds(200))

        // Emit the arrival height for preset 2 (1105mm).
        harness.heightCont.yield(makeHeightPacket(mm: 1105))
        harness.heightCont.finish()

        // Wait for the view model to reflect the arrived preset.
        await waitFor { harness.viewModel.activePreset == 2 }

        let newWrites = Array(harness.mock.writtenData.dropFirst(priorWriteCount))

        // Preflight must be the first command write.
        let cmdWrites = newWrites.filter { $0.characteristic == DeskUUID.command }
        XCTAssertGreaterThanOrEqual(cmdWrites.count, 1, "Need at least preflight")
        XCTAssertEqual(cmdWrites[0].data, DeskCommand.preflight, "First must be preflight")

        // At least one heartbeat targeting 1105mm must have been sent.
        let expectedTarget = DeskCommand.moveTo(tenthsOfMm: UInt16(1105 * 10))
        let heartbeatWrites = newWrites.filter {
            $0.characteristic == DeskUUID.targetHeartbeat && $0.data == expectedTarget
        }
        XCTAssertGreaterThanOrEqual(heartbeatWrites.count, 1, "Must send at least one move-to heartbeat")

        // View model must report preset 2 as active after arrival.
        XCTAssertEqual(harness.viewModel.activePreset, 2)
    }

    /// Verifies that heightDisplay and heightMM update on the view model when height
    /// notifications flow through the mock BLE layer.
    func testHeightUpdatesFlowToViewModel() async throws {
        let harness = try await makeConnectedHarness()

        // Confirm baseline height from handshake.
        await waitFor { harness.viewModel.heightMM == 730 }
        XCTAssertEqual(harness.viewModel.heightMM, 730)
        XCTAssertEqual(harness.viewModel.heightDisplay, "73 cm")

        // Emit a new height notification simulating movement to 900mm.
        harness.heightCont.yield(makeHeightPacket(mm: 900))

        await waitFor { harness.viewModel.heightMM == 900 }

        XCTAssertEqual(harness.viewModel.heightMM, 900)
        XCTAssertEqual(harness.viewModel.heightDisplay, "90 cm")

        harness.heightCont.finish()
    }

    /// Verifies activePreset becomes 2 only after the desk reports height within 5mm of the target.
    func testActivePresetSetOnlyAfterArrivalWithinTolerance() async throws {
        let harness = try await makeConnectedHarness()

        harness.viewModel.goToPreset(index: 2)

        // Height at 1111mm is outside the 5mm tolerance of 1105mm — no active preset yet.
        harness.heightCont.yield(makeHeightPacket(mm: 1111))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(harness.viewModel.activePreset, "Must not set activePreset outside 5mm tolerance")

        // Height at 1103mm is within 5mm of 1105mm — active preset must become 2.
        harness.heightCont.yield(makeHeightPacket(mm: 1103))
        harness.heightCont.finish()

        await waitFor { harness.viewModel.activePreset == 2 }
        XCTAssertEqual(harness.viewModel.activePreset, 2)
    }
}

// MARK: - Connection state flow

@MainActor
final class UIBLEConnectionStateTests: XCTestCase {

    /// Verifies the full disconnected → connecting → connected transition is reflected in the view model.
    func testConnectionStateFlowsEndToEnd() async throws {
        var heightCont: AsyncStream<Data>.Continuation!
        let heightStream = AsyncStream<Data> { cont in heightCont = cont }

        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
        mock.mockNotificationStreams[DeskUUID.dpg] = makeHarnessDPGStream()
        mock.mockNotificationStreams[DeskUUID.height] = heightStream

        let store = makeIntegrationTempConfigStore()
        let manager = DeskManager(bleController: mock, configStore: store)
        let viewModel = DeskViewModel(deskManager: manager, configStore: store)

        // Start disconnected.
        XCTAssertEqual(viewModel.connectionState, .disconnected)

        // Begin connecting — observe state transitions via the stateStream, which yields
        // both .connecting and .connected snapshots before we await managerConnectTask.
        var observedConnecting = false
        var stateIterator = await manager.stateStream.makeAsyncIterator()

        let managerConnectTask = Task { try await manager.connect(peripheralId: UUID()) }

        // Read the first state snapshot from stateStream; DeskManager.connect() sets .connecting
        // as its first action, so we collect snapshots until we see .connecting or .connected.
        while let snapshot = await stateIterator.next() {
            if snapshot.connectionState == .connecting {
                observedConnecting = true
                break
            }
            if snapshot.connectionState == .connected {
                break
            }
        }

        heightCont.yield(makeHeightPacket(mm: 730))
        try await managerConnectTask.value

        // Connecting state must have been observed during the transition.
        XCTAssertTrue(observedConnecting, "connectionState must pass through .connecting before .connected")

        // Final state must be connected.
        await waitFor { viewModel.connectionState == .connected }
        XCTAssertEqual(viewModel.connectionState, .connected)

        heightCont.finish()
    }
}

// MARK: - Movement direction

@MainActor
final class UIBLEMovementDirectionTests: XCTestCase {

    /// Verifies that isMoving and moveDirection update correctly during upward movement.
    func testMovementDirectionReflectedInViewModelDuringUpwardMove() async throws {
        let harness = try await makeConnectedHarness()

        // Emit a height packet with positive speed (upward movement).
        harness.heightCont.yield(makeHeightPacket(mm: 750, speedMMS: 30))

        await waitFor { harness.viewModel.isMoving }

        XCTAssertTrue(harness.viewModel.isMoving)
        XCTAssertEqual(harness.viewModel.moveDirection, .up)
        // activePreset must be nil while moving.
        XCTAssertNil(harness.viewModel.activePreset)

        // Emit arrival at rest.
        harness.heightCont.yield(makeHeightPacket(mm: 730, speedMMS: 0))
        harness.heightCont.finish()

        await waitFor { !harness.viewModel.isMoving }

        XCTAssertFalse(harness.viewModel.isMoving)
        XCTAssertNil(harness.viewModel.moveDirection)
    }

    /// Verifies moveDirection is .down when speed is negative.
    func testMovementDirectionReflectedInViewModelDuringDownwardMove() async throws {
        let harness = try await makeConnectedHarness()

        harness.heightCont.yield(makeHeightPacket(mm: 700, speedMMS: -30))

        await waitFor { harness.viewModel.isMoving }

        XCTAssertTrue(harness.viewModel.isMoving)
        XCTAssertEqual(harness.viewModel.moveDirection, .down)

        harness.heightCont.yield(makeHeightPacket(mm: 730, speedMMS: 0))
        harness.heightCont.finish()
    }
}
