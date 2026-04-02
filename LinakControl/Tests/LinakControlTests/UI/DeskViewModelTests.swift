// DeskViewModelTests.swift
// LinakControlTests — Verifies DeskViewModel state mapping and action dispatch.

import XCTest
@testable import LinakControlKit

// MARK: - Helpers

private func makeTempConfigStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeskViewModelTests-\(UUID().uuidString)")
    return ConfigStore(directoryURL: tempDir)
}

private func makeHappyPathMock() -> MockBLEController {
    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockNotificationStreams[DeskUUID.dpg] = finiteStream(HandshakeFixtures.happyPathDPGResponses)
    mock.mockNotificationStreams[DeskUUID.height] = finiteStream([HandshakeFixtures.heightNotification730mm])
    return mock
}

private func finiteStream(_ values: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for value in values { continuation.yield(value) }
        continuation.finish()
    }
}

/// Polls until the predicate returns true or the timeout elapses.
private func waitFor(
    timeout: TimeInterval = 1.0,
    predicate: @escaping () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// Convenience factory that shares one ConfigStore between DeskManager and DeskViewModel.
@MainActor
private func makeManagerAndViewModel(mock: MockBLEController) -> (DeskManager, DeskViewModel, ConfigStore) {
    let store = makeTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store)
    let viewModel = DeskViewModel(deskManager: manager, configStore: store)
    return (manager, viewModel, store)
}

// MARK: - Initial State

@MainActor
final class DeskViewModelInitialStateTests: XCTestCase {

    func testInitialConnectionStateIsDisconnected() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertEqual(viewModel.connectionState, .disconnected)
    }

    func testInitialHeightMMIsNil() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertNil(viewModel.heightMM)
    }

    func testInitialHeightDisplayIsDash() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertEqual(viewModel.heightDisplay, "—")
    }

    func testInitialIsMovingIsFalse() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertFalse(viewModel.isMoving)
    }

    func testInitialPresetsHasFourSlots() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertEqual(viewModel.presets.count, 4)
    }
}

// MARK: - State Stream Updates

@MainActor
final class DeskViewModelStateStreamTests: XCTestCase {

    func testConnectionStateUpdatesToConnectedAfterConnect() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())

        await waitFor { await MainActor.run { viewModel.connectionState == .connected } }

        XCTAssertEqual(viewModel.connectionState, .connected)
    }

    func testHeightMMPopulatedAfterConnect() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())

        await waitFor { await MainActor.run { viewModel.heightMM != nil } }

        XCTAssertEqual(viewModel.heightMM, 730)
    }

    func testHeightDisplayFormattedAsCentimeters() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())

        await waitFor { await MainActor.run { viewModel.heightDisplay != "—" } }

        XCTAssertEqual(viewModel.heightDisplay, "73 cm")
    }

    func testPresetsPopulatedFromHandshake() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())

        await waitFor { await MainActor.run { viewModel.presets[0].heightMM != nil } }

        XCTAssertEqual(viewModel.presets[0].heightMM, 730)
        XCTAssertEqual(viewModel.presets[1].heightMM, 1105)
        XCTAssertEqual(viewModel.presets[2].heightMM, 900)
        XCTAssertNil(viewModel.presets[3].heightMM)
    }

    func testConnectionStateUpdatesToDisconnectedAfterDisconnect() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())
        await waitFor { await MainActor.run { viewModel.connectionState == .connected } }

        await manager.disconnect()

        await waitFor { await MainActor.run { viewModel.connectionState == .disconnected } }
        XCTAssertEqual(viewModel.connectionState, .disconnected)
    }
}

// MARK: - heightDisplay Formatting

@MainActor
final class DeskViewModelHeightDisplayTests: XCTestCase {

    func testHeightDisplayIsDashWhenNoHeight() async {
        let (_, viewModel, _) = makeManagerAndViewModel(mock: MockBLEController())
        XCTAssertEqual(viewModel.heightDisplay, "—")
    }

    func testHeightDisplayUsesCentimetersByDefault() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())
        await waitFor { await MainActor.run { viewModel.heightDisplay != "—" } }

        XCTAssertTrue(
            viewModel.heightDisplay.hasSuffix("cm"),
            "Expected cm suffix, got: \(viewModel.heightDisplay)"
        )
    }
}

// MARK: - Action Methods

@MainActor
final class DeskViewModelActionTests: XCTestCase {

    func testGoToPresetDoesNotCrashWhenConnected() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())
        await waitFor { await MainActor.run { viewModel.connectionState == .connected } }

        // goToPreset fires-and-forgets; verify it does not crash or deadlock.
        viewModel.goToPreset(index: 1)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.connectionState, .connected)
    }

    func testStopDoesNotSetIsMovingWhenAlreadyStopped() async throws {
        let (manager, viewModel, _) = makeManagerAndViewModel(mock: makeHappyPathMock())

        try await manager.connect(peripheralId: UUID())
        await waitFor { await MainActor.run { viewModel.connectionState == .connected } }

        viewModel.stop()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.isMoving)
    }
}
