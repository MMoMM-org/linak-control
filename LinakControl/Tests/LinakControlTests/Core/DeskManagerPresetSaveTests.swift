// DeskManagerPresetSaveTests.swift
// LinakControlTests — Verifies DeskManager.savePreset behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

/// Builds a DeskManager connected at the given height, ready for preset save operations.
///
/// After connect, replaces the DPG notification stream with the given `saveResponses`
/// so the save sequence can consume fresh notifications without interference from the
/// handshake sequence.
private func makeConnectedManagerForSave(
    heightMM: Int = 1105,
    saveResponses: [Data] = []
) async throws -> (DeskManager, MockBLEController) {
    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(
        responses: HandshakeFixtures.happyPathDPGResponses
    )
    mock.mockNotificationStreams[DeskUUID.height] = makeHeightStream(mm: heightMM)

    let store = makeTempConfigStore()
    let manager = DeskManager(bleController: mock, configStore: store)
    try await manager.connect(peripheralId: UUID())

    // Clear writes accumulated during handshake so tests only see save-operation writes.
    mock.writtenData.removeAll()

    // Replace the now-exhausted DPG stream with fresh responses for the save operation.
    mock.mockNotificationStreams[DeskUUID.dpg] = makeFiniteStream(responses: saveResponses)

    return (manager, mock)
}

private func makeDPGStream(responses: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in responses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

private func makeFiniteStream(responses: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in responses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

private func makeHeightStream(mm: Int) -> AsyncStream<Data> {
    let raw = UInt16(mm * 10)
    let packet = Data([
        UInt8(raw & 0xFF),
        UInt8(raw >> 8),
        0x00, 0x00,
    ])
    return AsyncStream { continuation in
        continuation.yield(packet)
        continuation.finish()
    }
}

private func makeTempConfigStore() -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeskManagerPresetSaveTests-\(UUID().uuidString)")
    return ConfigStore(directoryURL: tempDir)
}

// MARK: - Happy Path Tests

final class DeskManagerPresetSaveHappyPathTests: XCTestCase {

    func testSavePreset2WritesCorrectSaveCommandBytes() async throws {
        // Preset 2, 1105mm: 11050 tenths = 0x2B2A → lo=0x2A hi=0x2B
        // Expected save command: [0x7F, 0x8A, 0x80, 0x01, 0x2A, 0x2B]
        let saveConfirmation = Data([0x7F, 0x8A, 0x00, 0x00])  // any valid response unblocks the buffer
        let readResponse = HandshakeFixtures.preset2Height1105mm
        let (manager, mock) = try await makeConnectedManagerForSave(
            heightMM: 1105,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 2)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        guard dpgWrites.count >= 1 else {
            XCTFail("Expected at least one DPG write for the save command")
            return
        }

        let saveCommandBytes = dpgWrites[0].data
        let expectedSaveCommand = Data([0x7F, 0x8A, 0x80, 0x01, 0x2A, 0x2B])
        XCTAssertEqual(
            saveCommandBytes, expectedSaveCommand,
            "Save command for preset 2 at 1105mm must be [7F 8A 80 01 2A 2B]"
        )
    }

    func testSavePreset2SendsReadPresetAfterSave() async throws {
        let saveConfirmation = Data([0x7F, 0x8A, 0x00, 0x00])
        let readResponse = HandshakeFixtures.preset2Height1105mm
        let (manager, mock) = try await makeConnectedManagerForSave(
            heightMM: 1105,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 2)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertGreaterThanOrEqual(
            dpgWrites.count, 2,
            "savePreset must write save command and then read-preset command to DPG"
        )

        let readPresetCommand = DeskCommand.readPreset(index: 2)!
        XCTAssertEqual(
            dpgWrites[1].data, readPresetCommand,
            "Second DPG write must be the read-preset command [7F 8A 00]"
        )
    }

    func testSavePresetUpdatesStateWithConfirmedHeight() async throws {
        let saveConfirmation = Data([0x7F, 0x8A, 0x00, 0x00])
        let readResponse = HandshakeFixtures.preset2Height1105mm
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: 1105,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 2)

        let state = await manager.currentState
        XCTAssertEqual(
            state.presets[1].heightMM, 1105,
            "Preset 2 height in state must be 1105mm after successful save"
        )
    }

    func testSavePreset1UpdatesCorrectSlot() async throws {
        // Preset 1, 730mm: 7300 tenths = 0x1C84 → lo=0x84 hi=0x1C
        let saveConfirmation = Data([0x7F, 0x89, 0x00, 0x00])
        let readResponse = HandshakeFixtures.preset1Height730mm
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: 730,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 1)

        let state = await manager.currentState
        XCTAssertEqual(
            state.presets[0].heightMM, 730,
            "Preset 1 height in state must be 730mm after successful save"
        )
    }
}

// MARK: - Not Connected Tests

final class DeskManagerPresetSaveNotConnectedTests: XCTestCase {

    func testSavePresetThrowsNotConnectedWhenDisconnected() async {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        do {
            try await manager.savePreset(index: 1)
            XCTFail("Expected DeskError.notConnected")
        } catch DeskError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Guard Tests

final class DeskManagerPresetSaveGuardTests: XCTestCase {

    func testSavePresetThrowsForInvalidIndexZero() async throws {
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: 1000,
            saveResponses: []
        )

        do {
            try await manager.savePreset(index: 0)
            XCTFail("Expected DeskError.presetNotSet for index 0")
        } catch DeskError.presetNotSet {
            // expected
        } catch DeskError.notConnected {
            XCTFail("Got notConnected but desk is connected")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSavePresetThrowsForInvalidIndexFive() async throws {
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: 1000,
            saveResponses: []
        )

        do {
            try await manager.savePreset(index: 5)
            XCTFail("Expected DeskError.presetNotSet for index 5")
        } catch DeskError.presetNotSet {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSavePresetThrowsWhenNoCurrentHeight() async throws {
        // Connect without a height notification so state.heightMM stays nil
        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { continuation in
            for response in HandshakeFixtures.happyPathDPGResponses {
                continuation.yield(response)
            }
            continuation.finish()
        }
        // Provide no valid height packet so currentHeight is nil after handshake
        mock.mockNotificationStreams[DeskUUID.height] = AsyncStream { continuation in
            continuation.finish()
        }

        let manager = DeskManager(
            bleController: mock,
            configStore: makeTempConfigStore()
        )
        try await manager.connect(peripheralId: UUID())

        // Verify the state has no current height
        let stateBeforeSave = await manager.currentState
        XCTAssertNil(stateBeforeSave.heightMM, "Precondition: heightMM must be nil for this test")

        mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { continuation in
            continuation.finish()
        }

        do {
            try await manager.savePreset(index: 1)
            XCTFail("Expected DeskError.presetNotSet when heightMM is nil")
        } catch DeskError.presetNotSet {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Command Byte Verification Tests

final class DeskManagerPresetSaveCommandBytesTests: XCTestCase {

    func testSaveCommandBytesForPreset1At730mm() async throws {
        // Preset 1, 730mm: 7300 tenths = 0x1C84 → lo=0x84 hi=0x1C
        // Slot byte for preset 1 = 0x89
        // Expected: [0x7F, 0x89, 0x80, 0x01, 0x84, 0x1C]
        let saveConfirmation = Data([0x7F, 0x89, 0x00, 0x00])
        let readResponse = HandshakeFixtures.preset1Height730mm
        let (manager, mock) = try await makeConnectedManagerForSave(
            heightMM: 730,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 1)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertGreaterThanOrEqual(dpgWrites.count, 1)

        let expectedSaveCommand = Data([0x7F, 0x89, 0x80, 0x01, 0x84, 0x1C])
        XCTAssertEqual(
            dpgWrites[0].data, expectedSaveCommand,
            "Save command for preset 1 at 730mm must be [7F 89 80 01 84 1C]"
        )
    }

    func testSaveCommandBytesForPreset3At900mm() async throws {
        // Preset 3, 900mm: 9000 tenths = 0x2328 → lo=0x28 hi=0x23
        // Slot byte for preset 3 = 0x8B
        // Expected: [0x7F, 0x8B, 0x80, 0x01, 0x28, 0x23]
        let saveConfirmation = Data([0x7F, 0x8B, 0x00, 0x00])
        let readResponse = HandshakeFixtures.preset3Height900mm
        let (manager, mock) = try await makeConnectedManagerForSave(
            heightMM: 900,
            saveResponses: [saveConfirmation, readResponse]
        )

        try await manager.savePreset(index: 3)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertGreaterThanOrEqual(dpgWrites.count, 1)

        let expectedSaveCommand = Data([0x7F, 0x8B, 0x80, 0x01, 0x28, 0x23])
        XCTAssertEqual(
            dpgWrites[0].data, expectedSaveCommand,
            "Save command for preset 3 at 900mm must be [7F 8B 80 01 28 23]"
        )
    }
}

// MARK: - Re-read Confirmation Tests

final class DeskManagerPresetSaveRereadTests: XCTestCase {

    func testRereadResponseHeightUpdatesPreviousPresetValue() async throws {
        // Handshake populated preset 3 with 900mm; now save at 1105mm and confirm 1105mm
        let heightMM = 1105
        let raw = UInt16(heightMM * 10)
        let confirmedResponse = Data([0x7F, 0x8B, UInt8(raw & 0xFF), UInt8(raw >> 8)])
        let saveConfirmation = Data([0x7F, 0x8B, 0x00, 0x00])
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: heightMM,
            saveResponses: [saveConfirmation, confirmedResponse]
        )

        try await manager.savePreset(index: 3)

        let state = await manager.currentState
        XCTAssertEqual(
            state.presets[2].heightMM, heightMM,
            "After save, preset 3 must reflect the confirmed 1105mm height from re-read"
        )
    }

    func testRereadHeightTakesPrecedenceOverOriginalHeight() async throws {
        // Desk confirms a different height than what we sent (firmware rounding)
        // We stored 1105mm but firmware confirms 1104mm — firmware is truth
        let storedHeightMM = 1105
        let firmwareHeightMM = 1104
        let firmwareRaw = UInt16(firmwareHeightMM * 10)
        let confirmedResponse = Data([0x7F, 0x8A, UInt8(firmwareRaw & 0xFF), UInt8(firmwareRaw >> 8)])
        let saveConfirmation = Data([0x7F, 0x8A, 0x00, 0x00])
        let (manager, _) = try await makeConnectedManagerForSave(
            heightMM: storedHeightMM,
            saveResponses: [saveConfirmation, confirmedResponse]
        )

        try await manager.savePreset(index: 2)

        let state = await manager.currentState
        XCTAssertEqual(
            state.presets[1].heightMM, firmwareHeightMM,
            "Firmware-confirmed height must take precedence in state after re-read"
        )
    }
}
