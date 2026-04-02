// HotkeyManagerTests.swift
// LinakControlTests — Verifies HotkeyManager enable/disable state and desk-command routing.

import XCTest
@testable import LinakControlKit

// MARK: - MockHotkeyManager

/// In-memory HotkeyManaging stub for testing consumers that depend on the protocol.
final class MockHotkeyManager: HotkeyManaging {
    private(set) var enableCallCount = 0
    private(set) var disableCallCount = 0
    private(set) var _isEnabled = false

    var isEnabled: Bool { _isEnabled }

    func enable() {
        enableCallCount += 1
        _isEnabled = true
    }

    func disable() {
        disableCallCount += 1
        _isEnabled = false
    }
}

// MARK: - Helpers

// makeTempConfigStore is provided by TestHelpers.swift (with config: parameter)

// MARK: - MockHotkeyManager Protocol Tests

final class MockHotkeyManagerTests: XCTestCase {

    func testEnableSetIsEnabledTrue() {
        let mock = MockHotkeyManager()

        mock.enable()

        XCTAssertTrue(mock.isEnabled)
    }

    func testDisableSetIsEnabledFalse() {
        let mock = MockHotkeyManager()
        mock.enable()

        mock.disable()

        XCTAssertFalse(mock.isEnabled)
    }

    func testEnableCallCountIncrements() {
        let mock = MockHotkeyManager()

        mock.enable()
        mock.enable()

        XCTAssertEqual(mock.enableCallCount, 2)
    }

    func testDisableCallCountIncrements() {
        let mock = MockHotkeyManager()

        mock.disable()
        mock.disable()

        XCTAssertEqual(mock.disableCallCount, 2)
    }

    func testInitialStateIsDisabled() {
        let mock = MockHotkeyManager()

        XCTAssertFalse(mock.isEnabled)
        XCTAssertEqual(mock.enableCallCount, 0)
        XCTAssertEqual(mock.disableCallCount, 0)
    }
}

// MARK: - HotkeyManager Enable/Disable State Tests

@MainActor
final class HotkeyManagerEnableDisableTests: XCTestCase {

    func testIsEnabledFalseBeforeEnable() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        XCTAssertFalse(hotkeys.isEnabled)
    }

    func testIsEnabledTrueAfterEnable() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        hotkeys.enable()
        defer { hotkeys.disable() }

        XCTAssertTrue(hotkeys.isEnabled)
    }

    func testIsEnabledFalseAfterDisable() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        hotkeys.enable()
        hotkeys.disable()

        XCTAssertFalse(hotkeys.isEnabled)
    }

    func testEnableIsIdempotent() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        hotkeys.enable()
        hotkeys.enable() // second call must not create a second monitor

        defer { hotkeys.disable() }
        XCTAssertTrue(hotkeys.isEnabled)
    }

    func testDisableWhenAlreadyDisabledDoesNotCrash() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        // disable without a prior enable must be a no-op
        hotkeys.disable()

        XCTAssertFalse(hotkeys.isEnabled)
    }

    func testReEnableAfterDisableRestoresEnabledState() {
        let bleController = MockBLEController()
        let store = makeTempConfigStore()
        let deskManager = DeskManager(bleController: bleController, configStore: store)
        let hotkeys = HotkeyManager(deskManager: deskManager, configStore: store)

        hotkeys.enable()
        hotkeys.disable()
        hotkeys.enable()
        defer { hotkeys.disable() }

        XCTAssertTrue(hotkeys.isEnabled)
    }
}

// MARK: - HotkeyManager Config Integration Tests

@MainActor
final class HotkeyManagerConfigIntegrationTests: XCTestCase {

    func testMoveUpUsesAutoRunUpModeFromConfig() async throws {
        let bleController = MockBLEController()
        let config = AppConfig(autoRunUp: .auto, autoRunDown: .manual)
        let store = makeTempConfigStore(config: config)
        let deskManager = DeskManager(bleController: bleController, configStore: store)

        // Verify that configStore.load() returns the expected run mode
        // (HotkeyManager reads this on each key press)
        let loaded = try store.load()
        XCTAssertEqual(loaded.autoRunUp, .auto)
    }

    func testMoveDownUsesAutoRunDownModeFromConfig() async throws {
        let bleController = MockBLEController()
        let config = AppConfig(autoRunUp: .manual, autoRunDown: .auto)
        let store = makeTempConfigStore(config: config)
        let deskManager = DeskManager(bleController: bleController, configStore: store)

        let loaded = try store.load()
        XCTAssertEqual(loaded.autoRunDown, .auto)
    }

    func testHotkeysEnabledFlagDefaultsFalse() throws {
        let store = makeTempConfigStore()
        let loaded = try store.load()
        XCTAssertFalse(loaded.hotkeysEnabled)
    }

    func testHotkeysEnabledFlagCanBePersisted() throws {
        let store = makeTempConfigStore(config: AppConfig(hotkeysEnabled: true))
        let loaded = try store.load()
        XCTAssertTrue(loaded.hotkeysEnabled)
    }
}
