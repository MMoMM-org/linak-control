// SettingsViewModelTests.swift
// LinakControlTests — Verifies settings-related actions on DeskViewModel.

import XCTest
@testable import LinakControlKit

// MARK: - Helpers

// makeTempConfigStore is provided by TestHelpers.swift (with config: parameter)

@MainActor
private func makeViewModel(mock: MockBLEController, store: ConfigStore) -> (DeskManager, DeskViewModel) {
    let manager = DeskManager(bleController: mock, configStore: store)
    let viewModel = DeskViewModel(deskManager: manager, configStore: store)
    return (manager, viewModel)
}

// waitFor is provided by TestHelpers.swift

// MARK: - showSettings

@MainActor
final class SettingsShowSettingsTests: XCTestCase {

    func testShowSettingsDefaultsToFalse() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        XCTAssertFalse(viewModel.showSettings)
    }

    func testShowSettingsCanBeToggledToTrue() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.showSettings = true

        XCTAssertTrue(viewModel.showSettings)
    }
}

// MARK: - updateUnit

@MainActor
final class SettingsUpdateUnitTests: XCTestCase {

    func testUpdateUnitToInchPersistsToConfig() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateUnit(.inch)

        let saved = try store.load()
        XCTAssertEqual(saved.unit, .inch)
    }

    func testUpdateUnitToCmPersistsToConfig() throws {
        let store = makeTempConfigStore(config: AppConfig(unit: .inch))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateUnit(.cm)

        let saved = try store.load()
        XCTAssertEqual(saved.unit, .cm)
    }

    func testUpdateUnitChangesPublishedUnit() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateUnit(.inch)

        XCTAssertEqual(viewModel.unit, .inch)
    }

    func testUpdateUnitRecalculatesHeightDisplayWhenHeightKnown() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)
        // Simulate a known height by setting directly (unit defaults to .cm)
        viewModel.heightMM = 730

        viewModel.updateUnit(.inch)

        // 730 mm → 28.7 in
        XCTAssertEqual(viewModel.heightDisplay, "28.7 in")
    }

    func testUpdateUnitLeavesHeightDisplayAsDashWhenNoHeight() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateUnit(.inch)

        XCTAssertEqual(viewModel.heightDisplay, "—")
    }
}

// MARK: - updateAutoRunUp

@MainActor
final class SettingsUpdateAutoRunUpTests: XCTestCase {

    func testUpdateAutoRunUpToAutoPersistsToConfig() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunUp(.auto)

        let saved = try store.load()
        XCTAssertEqual(saved.autoRunUp, .auto)
    }

    func testUpdateAutoRunUpChangesPublishedProperty() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunUp(.auto)

        XCTAssertEqual(viewModel.autoRunUp, .auto)
    }

    func testUpdateAutoRunUpDoesNotChangeAutoRunDown() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunUp(.auto)

        let saved = try store.load()
        XCTAssertEqual(saved.autoRunDown, .manual)
    }
}

// MARK: - updateAutoRunDown

@MainActor
final class SettingsUpdateAutoRunDownTests: XCTestCase {

    func testUpdateAutoRunDownToAutoPersistsToConfig() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunDown(.auto)

        let saved = try store.load()
        XCTAssertEqual(saved.autoRunDown, .auto)
    }

    func testUpdateAutoRunDownChangesPublishedProperty() {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunDown(.auto)

        XCTAssertEqual(viewModel.autoRunDown, .auto)
    }

    func testUpdateAutoRunDownDoesNotChangeAutoRunUp() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateAutoRunDown(.auto)

        let saved = try store.load()
        XCTAssertEqual(saved.autoRunUp, .manual)
    }
}

// MARK: - updateStartAtLogin

@MainActor
final class SettingsUpdateStartAtLoginTests: XCTestCase {

    func testUpdateStartAtLoginTruePersistsToConfig() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateStartAtLogin(true)

        let saved = try store.load()
        XCTAssertTrue(saved.startAtLogin)
    }

    func testUpdateStartAtLoginFalsePersistsToConfig() throws {
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateStartAtLogin(false)

        let saved = try store.load()
        XCTAssertFalse(saved.startAtLogin)
    }
}

// MARK: - updateHotkeysEnabled

@MainActor
final class SettingsUpdateHotkeysEnabledTests: XCTestCase {

    func testUpdateHotkeysEnabledTruePersistsToConfig() throws {
        let store = makeTempConfigStore()
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateHotkeysEnabled(true)

        let saved = try store.load()
        XCTAssertTrue(saved.hotkeysEnabled)
    }

    func testUpdateHotkeysEnabledFalsePersistsToConfig() throws {
        let store = makeTempConfigStore(config: AppConfig(hotkeysEnabled: true))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.updateHotkeysEnabled(false)

        let saved = try store.load()
        XCTAssertFalse(saved.hotkeysEnabled)
    }
}

// MARK: - forgetAndRescan

@MainActor
final class SettingsForgetAndRescanTests: XCTestCase {

    func testForgetAndRescanClearsPairedDeskUUID() throws {
        let store = makeTempConfigStore(config: AppConfig(pairedDeskUUID: UUID().uuidString))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.forgetAndRescan()

        let saved = try store.load()
        XCTAssertNil(saved.pairedDeskUUID)
    }

    func testForgetAndRescanClearsPairedDeskName() throws {
        let store = makeTempConfigStore(config: AppConfig(pairedDeskName: "LINAK DPG1C"))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.forgetAndRescan()

        let saved = try store.load()
        XCTAssertNil(saved.pairedDeskName)
    }

    func testForgetAndRescanSetsIsFirstRunToTrue() {
        let store = makeTempConfigStore(config: AppConfig(pairedDeskUUID: UUID().uuidString))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)

        viewModel.forgetAndRescan()

        XCTAssertTrue(viewModel.isFirstRun)
    }

    func testForgetAndRescanClosesSettingsPanel() {
        let store = makeTempConfigStore(config: AppConfig(pairedDeskUUID: UUID().uuidString))
        let (_, viewModel) = makeViewModel(mock: MockBLEController(), store: store)
        viewModel.showSettings = true

        viewModel.forgetAndRescan()

        XCTAssertFalse(viewModel.showSettings)
    }
}
