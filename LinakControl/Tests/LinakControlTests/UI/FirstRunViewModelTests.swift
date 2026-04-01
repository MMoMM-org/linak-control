// FirstRunViewModelTests.swift
// LinakControlTests — Verifies first-run detection and scan/select behaviors on DeskViewModel.

import XCTest
@testable import LinakControlKit

// MARK: - Helpers

private func makeTempConfigStore(config: AppConfig? = nil) -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FirstRunViewModelTests-\(UUID().uuidString)")
    let store = ConfigStore(directoryURL: tempDir)
    if let config {
        try? store.save(config)
    }
    return store
}

private func makeViewModel(mock: MockBLEController, store: ConfigStore) -> (DeskManager, DeskViewModel) {
    let manager = DeskManager(bleController: mock, configStore: store)
    let viewModel = DeskViewModel(deskManager: manager, configStore: store)
    return (manager, viewModel)
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

// MARK: - isFirstRun Detection

@MainActor
final class FirstRunDetectionTests: XCTestCase {

    func testIsFirstRunWhenNoPairedDesk() async {
        let store = makeTempConfigStore(config: AppConfig(pairedDeskUUID: nil))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        XCTAssertTrue(viewModel.isFirstRun)
    }

    func testIsNotFirstRunWhenPairedDeskExists() async {
        let uuid = UUID().uuidString
        let store = makeTempConfigStore(config: AppConfig(pairedDeskUUID: uuid))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        XCTAssertFalse(viewModel.isFirstRun)
    }

    func testIsFirstRunWhenNoConfigFileExists() async {
        // ConfigStore.load() returns AppConfig.default (nil pairedDeskUUID) when no file exists.
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        XCTAssertTrue(viewModel.isFirstRun)
    }
}

// MARK: - startScan

@MainActor
final class FirstRunStartScanTests: XCTestCase {

    func testStartScanCollectsDiscoveredDesks() async {
        let desk1 = DiscoveredDesk(peripheralId: UUID(), name: "LINAK DPG1C", rssi: -55)
        let desk2 = DiscoveredDesk(peripheralId: UUID(), name: "LINAK Desk-B12", rssi: -72)

        let mock = MockBLEController()
        mock.mockDesks = [desk1, desk2]

        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: mock, store: store)

        viewModel.startScan()

        await waitFor { await MainActor.run { viewModel.discoveredDesks.count == 2 } }

        XCTAssertEqual(viewModel.discoveredDesks.count, 2)
        XCTAssertEqual(viewModel.discoveredDesks[0].name, "LINAK DPG1C")
        XCTAssertEqual(viewModel.discoveredDesks[1].name, "LINAK Desk-B12")
    }

    func testStartScanClearsStaleDesksBeforeNewScan() async {
        let desk = DiscoveredDesk(peripheralId: UUID(), name: "LINAK DPG1C", rssi: -55)

        let mock = MockBLEController()
        mock.mockDesks = [desk]

        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: mock, store: store)

        // First scan populates discoveredDesks.
        viewModel.startScan()
        await waitFor { await MainActor.run { viewModel.discoveredDesks.count == 1 } }

        // Second scan with empty mockDesks should clear the list.
        mock.mockDesks = []
        viewModel.startScan()

        await waitFor(timeout: 0.5) {
            await MainActor.run { viewModel.discoveredDesks.isEmpty }
        }
        XCTAssertTrue(viewModel.discoveredDesks.isEmpty)
    }

    func testStartScanWithNoDesksLeavesDiscoveredDesksEmpty() async {
        let mock = MockBLEController()
        mock.mockDesks = []

        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: mock, store: store)

        viewModel.startScan()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(viewModel.discoveredDesks.isEmpty)
    }
}

// MARK: - selectDesk

@MainActor
final class FirstRunSelectDeskTests: XCTestCase {

    func testSelectDeskTriggersConnectWithCorrectUUID() async {
        let targetId = UUID()
        let desk = DiscoveredDesk(peripheralId: targetId, name: "LINAK DPG1C", rssi: -55)

        let mock = MockBLEController()
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: mock, store: store)

        viewModel.selectDesk(desk)

        // Allow fire-and-forget task to execute.
        await waitFor { await MainActor.run { mock.connectCallCount > 0 } }

        XCTAssertEqual(mock.connectCallCount, 1)
    }

    func testSelectDeskDoesNotCrashOnConnectionFailure() async {
        let desk = DiscoveredDesk(peripheralId: UUID(), name: "LINAK DPG1C", rssi: -55)

        let mock = MockBLEController()
        mock.shouldFailConnect = true

        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: mock, store: store)

        // Should not throw — selectDesk uses fire-and-forget.
        viewModel.selectDesk(desk)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.connectionState, .disconnected)
    }
}
