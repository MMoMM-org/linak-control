// LoginItemManagerTests.swift
// LinakControlTests — Verifies login-item registration behavior via DeskViewModel.

import XCTest
@testable import LinakControlKit

// MARK: - Mock

final class MockLoginItemManager: LoginItemManaging {
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false

    func register() throws {
        if shouldThrowOnRegister { throw LoginItemTestError.registrationFailed }
        registerCallCount += 1
    }

    func unregister() throws {
        if shouldThrowOnUnregister { throw LoginItemTestError.unregistrationFailed }
        unregisterCallCount += 1
    }
}

private enum LoginItemTestError: Error {
    case registrationFailed
    case unregistrationFailed
}

// MARK: - Helpers

private func makeTempConfigStore(config: AppConfig? = nil) -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("LoginItemManagerTests-\(UUID().uuidString)")
    let store = ConfigStore(directoryURL: tempDir)
    if let config { try? store.save(config) }
    return store
}

@MainActor
private func makeViewModel(
    store: ConfigStore,
    loginItemManager: LoginItemManaging = MockLoginItemManager()
) -> DeskViewModel {
    let manager = DeskManager(bleController: MockBLEController(), configStore: store)
    return DeskViewModel(deskManager: manager, configStore: store, loginItemManager: loginItemManager)
}

// MARK: - Initial State

@MainActor
final class LoginItemInitialStateTests: XCTestCase {

    func testStartAtLoginDefaultsToFalseWhenNoConfig() {
        let store = makeTempConfigStore()
        let viewModel = makeViewModel(store: store)

        XCTAssertFalse(viewModel.startAtLogin)
    }

    func testStartAtLoginReflectsPersistedTrueValue() {
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let viewModel = makeViewModel(store: store)

        XCTAssertTrue(viewModel.startAtLogin)
    }

    func testStartAtLoginReflectsPersistedFalseValue() {
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: false))
        let viewModel = makeViewModel(store: store)

        XCTAssertFalse(viewModel.startAtLogin)
    }
}

// MARK: - setStartAtLogin Behavior

@MainActor
final class SetStartAtLoginTests: XCTestCase {

    func testEnablingCallsRegisterOnce() {
        let mock = MockLoginItemManager()
        let store = makeTempConfigStore()
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        viewModel.setStartAtLogin(true)

        XCTAssertEqual(mock.registerCallCount, 1)
        XCTAssertEqual(mock.unregisterCallCount, 0)
    }

    func testDisablingCallsUnregisterOnce() {
        let mock = MockLoginItemManager()
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        viewModel.setStartAtLogin(false)

        XCTAssertEqual(mock.unregisterCallCount, 1)
        XCTAssertEqual(mock.registerCallCount, 0)
    }

    func testEnablingUpdatesStartAtLoginPublishedProperty() {
        let store = makeTempConfigStore()
        let viewModel = makeViewModel(store: store)

        viewModel.setStartAtLogin(true)

        XCTAssertTrue(viewModel.startAtLogin)
    }

    func testDisablingUpdatesStartAtLoginPublishedProperty() {
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let viewModel = makeViewModel(store: store, loginItemManager: MockLoginItemManager())

        viewModel.setStartAtLogin(false)

        XCTAssertFalse(viewModel.startAtLogin)
    }

    func testEnablingPersistsStartAtLoginTrueToConfig() async throws {
        let mock = MockLoginItemManager()
        let store = makeTempConfigStore()
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        viewModel.setStartAtLogin(true)
        // Allow the fire-and-forget Task to complete.
        try await Task.sleep(for: .milliseconds(50))

        let saved = try store.load()
        XCTAssertTrue(saved.startAtLogin)
    }

    func testDisablingPersistsStartAtLoginFalseToConfig() async throws {
        let mock = MockLoginItemManager()
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        viewModel.setStartAtLogin(false)
        try await Task.sleep(for: .milliseconds(50))

        let saved = try store.load()
        XCTAssertFalse(saved.startAtLogin)
    }

    func testRegisterErrorDoesNotCrashAndStillPersists() async throws {
        let mock = MockLoginItemManager()
        mock.shouldThrowOnRegister = true
        let store = makeTempConfigStore()
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        // Should not throw — errors from SMAppService are swallowed intentionally.
        viewModel.setStartAtLogin(true)
        try await Task.sleep(for: .milliseconds(50))

        // Published property still updates.
        XCTAssertTrue(viewModel.startAtLogin)
        // Config is still persisted.
        let saved = try store.load()
        XCTAssertTrue(saved.startAtLogin)
    }

    func testUnregisterErrorDoesNotCrashAndStillPersists() async throws {
        let mock = MockLoginItemManager()
        mock.shouldThrowOnUnregister = true
        let store = makeTempConfigStore(config: AppConfig(startAtLogin: true))
        let viewModel = makeViewModel(store: store, loginItemManager: mock)

        viewModel.setStartAtLogin(false)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.startAtLogin)
        let saved = try store.load()
        XCTAssertFalse(saved.startAtLogin)
    }
}
