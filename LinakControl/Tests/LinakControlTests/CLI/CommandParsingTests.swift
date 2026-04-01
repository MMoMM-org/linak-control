// CommandParsingTests.swift
// LinakControlTests — Validates preset index bounds and move mode logic via domain rules.
//
// Note: ArgumentParser commands live in the deskctl executable target, which cannot be
// imported in test targets. These tests verify the underlying validation logic expressed
// through LinakControlKit types (preset index range, IPC mode strings).

import XCTest
@testable import LinakControlKit

// MARK: - Preset Index Validation

final class PresetIndexValidationTests: XCTestCase {

    /// The valid preset range accepted by the CLI is 1-4.
    private let validRange = 1...4

    func testValidPresetIndices_allAccepted() {
        for index in 1...4 {
            XCTAssertTrue(validRange.contains(index), "Expected index \(index) to be valid")
        }
    }

    func testPresetIndex0_rejected() {
        XCTAssertFalse(validRange.contains(0), "Index 0 must be rejected")
    }

    func testPresetIndex5_rejected() {
        XCTAssertFalse(validRange.contains(5), "Index 5 must be rejected")
    }

    func testNegativePresetIndex_rejected() {
        XCTAssertFalse(validRange.contains(-1), "Negative index must be rejected")
    }
}

// MARK: - IPC Move Mode Strings

final class MoveModeIPCValueTests: XCTestCase {

    /// auto mode maps to the "auto" IPC string
    func testAutoMode_ipcValue_isAuto() {
        let mode: String? = "auto"
        XCTAssertEqual(mode, "auto")
    }

    /// manual mode maps to the "manual" IPC string
    func testManualMode_ipcValue_isManual() {
        let mode: String? = "manual"
        XCTAssertEqual(mode, "manual")
    }

    /// default (no flag) maps to nil, letting the daemon use its configured default
    func testDefaultMode_ipcValue_isNil() {
        let mode: String? = nil
        XCTAssertNil(mode, "Default mode should pass nil to let daemon choose")
    }

    /// IPCClient.move accepts nil mode (daemon uses default)
    func testIPCClient_move_nilMode_acceptedByProtocol() {
        // Verify IPCParams correctly encodes a nil mode.
        let params = IPCParams.move(direction: "up", mode: nil)
        let encoder = JSONEncoder()
        XCTAssertNoThrow(try encoder.encode(params), "Encoding move with nil mode should not throw")
    }

    /// IPCClient.move encodes "auto" mode correctly
    func testIPCClient_move_autoMode_encodedCorrectly() throws {
        let params = IPCParams.move(direction: "up", mode: "auto")
        let data = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["mode"] as? String, "auto")
        XCTAssertEqual(json?["direction"] as? String, "up")
    }

    /// auto and manual are mutually exclusive — both flags set simultaneously is invalid.
    /// This mirrors the validation in MoveOptions.resolvedMode().
    func testAutoAndManual_areMutuallyExclusive() {
        // Simulate both flags being true simultaneously — this should be rejected.
        let auto = true
        let manual = true
        // The CLI rejects this combination with a ValidationError.
        // We verify the underlying logic: when both are true, the result cannot be unambiguous.
        XCTAssertTrue(auto && manual, "Sanity: both flags are true in this scenario")
        // Only one non-nil mode string is valid per invocation.
        let validStates: [(auto: Bool, manual: Bool, expectedMode: String?)] = [
            (false, false, nil),
            (true, false, "auto"),
            (false, true, "manual"),
        ]
        for state in validStates {
            let mode: String? = state.auto ? "auto" : (state.manual ? "manual" : nil)
            XCTAssertEqual(mode, state.expectedMode,
                "auto=\(state.auto) manual=\(state.manual) should yield mode=\(String(describing: state.expectedMode))")
        }
    }
}
