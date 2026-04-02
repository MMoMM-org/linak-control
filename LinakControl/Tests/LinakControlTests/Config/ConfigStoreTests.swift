// ConfigStoreTests.swift
// LinakControlTests

import XCTest
@testable import LinakControlKit

final class ConfigStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempStore() throws -> (store: ConfigStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinakControlTests-\(UUID().uuidString)")
        let store = ConfigStore(directoryURL: dir)
        return (store, dir)
    }

    // MARK: - Default config values

    func testDefaultConfigHasExpectedValues() {
        let config = AppConfig.default
        XCTAssertNil(config.pairedDeskUUID)
        XCTAssertNil(config.pairedDeskName)
        XCTAssertEqual(config.unit, .cm)
        XCTAssertEqual(config.autoRunUp, .manual)
        XCTAssertEqual(config.autoRunDown, .manual)
        XCTAssertFalse(config.startAtLogin)
        XCTAssertFalse(config.hotkeysEnabled)
        XCTAssertEqual(config.presetLabels, [nil, nil, nil, nil])
    }

    // MARK: - Load returns default when file absent

    func testLoadReturnsDefaultWhenFileDoesNotExist() throws {
        let (store, _) = try makeTempStore()
        let config = try store.load()
        XCTAssertEqual(config, AppConfig.default)
    }

    // MARK: - Save creates directory

    func testSaveCreatesDirectory() throws {
        let (store, dir) = try makeTempStore()
        try store.save(.default)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dir.path),
            "Expected directory to be created at \(dir.path)"
        )
    }

    func testSaveDirectoryHasMode0o700() throws {
        let (store, dir) = try makeTempStore()
        try store.save(.default)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700, "Directory should have mode 0o700")
    }

    func testSaveFileHasMode0o600() throws {
        let (store, dir) = try makeTempStore()
        try store.save(.default)
        let filePath = dir.appendingPathComponent("config.json").path
        let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600, "File should have mode 0o600")
    }

    // MARK: - Save then load round-trip

    func testRoundTripPreservesAllFields() throws {
        let (store, _) = try makeTempStore()
        var original = AppConfig.default
        original.pairedDeskUUID = "12345678-1234-1234-1234-123456789ABC"
        original.pairedDeskName = "My Desk"
        original.unit = .inch
        original.autoRunUp = .auto
        original.autoRunDown = .auto
        original.startAtLogin = true
        original.hotkeysEnabled = true
        original.presetLabels = ["Sitting", "Standing", "Video Call", "Lunch"]

        try store.save(original)
        let loaded = try store.load()

        XCTAssertEqual(loaded, original)
    }

    func testRoundTripWithNilOptionals() throws {
        let (store, _) = try makeTempStore()
        let original = AppConfig.default

        try store.save(original)
        let loaded = try store.load()

        XCTAssertEqual(loaded, original)
    }

    // MARK: - JSON key encoding uses snake_case

    func testJSONEncodingUsesSnakeCaseKeys() throws {
        let (store, dir) = try makeTempStore()
        var config = AppConfig.default
        config.pairedDeskUUID = "ABCD"
        config.pairedDeskName = "Desk"
        config.unit = .inch
        config.autoRunUp = .auto
        config.autoRunDown = .auto
        config.startAtLogin = true
        config.hotkeysEnabled = true
        config.presetLabels = ["Sit", nil, nil, nil]

        try store.save(config)

        let filePath = dir.appendingPathComponent("config.json")
        let data = try Data(contentsOf: filePath)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertNotNil(json["paired_desk_uuid"], "Expected key 'paired_desk_uuid'")
        XCTAssertNotNil(json["paired_desk_name"], "Expected key 'paired_desk_name'")
        XCTAssertNotNil(json["unit"], "Expected key 'unit'")
        XCTAssertNotNil(json["auto_run_up"], "Expected key 'auto_run_up'")
        XCTAssertNotNil(json["auto_run_down"], "Expected key 'auto_run_down'")
        XCTAssertNotNil(json["start_at_login"], "Expected key 'start_at_login'")
        XCTAssertNotNil(json["hotkeys_enabled"], "Expected key 'hotkeys_enabled'")
        XCTAssertNotNil(json["preset_labels"], "Expected key 'preset_labels'")

        // Legacy individual keys must NOT appear in new format
        XCTAssertNil(json["preset_1_label"])

        // Camel-case keys must NOT appear
        XCTAssertNil(json["pairedDeskUUID"])
        XCTAssertNil(json["autoRunUp"])
        XCTAssertNil(json["startAtLogin"])
    }

    func testJSONEnumValuesAreStrings() throws {
        let (store, dir) = try makeTempStore()
        var config = AppConfig.default
        config.unit = .cm
        config.autoRunUp = .manual
        config.autoRunDown = .auto

        try store.save(config)

        let filePath = dir.appendingPathComponent("config.json")
        let data = try Data(contentsOf: filePath)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["unit"] as? String, "cm")
        XCTAssertEqual(json["auto_run_up"] as? String, "manual")
        XCTAssertEqual(json["auto_run_down"] as? String, "auto")
    }

    // MARK: - Multiple saves overwrite previous file

    func testSubsequentSaveOverwritesPreviousValues() throws {
        let (store, _) = try makeTempStore()
        var first = AppConfig.default
        first.pairedDeskName = "First"
        try store.save(first)

        var second = AppConfig.default
        second.pairedDeskName = "Second"
        try store.save(second)

        let loaded = try store.load()
        XCTAssertEqual(loaded.pairedDeskName, "Second")
    }
}
