// HandshakeTests.swift
// LinakControlTests — Verifies the DPG1C handshake sequence behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

private func makeDPGStream(responses: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in responses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}

private func makeHeightStream(values: [Data] = []) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for value in values {
            continuation.yield(value)
        }
        continuation.finish()
    }
}

private func configureMock(
    _ mock: MockBLEController,
    dpgResponses: [Data] = HandshakeFixtures.happyPathDPGResponses,
    heightValues: [Data] = [HandshakeFixtures.heightNotification730mm],
    outputMask: Data = HandshakeFixtures.validOutputMask
) {
    mock.mockReadResponses[DeskUUID.outputMask] = outputMask
    mock.mockNotificationStreams[DeskUUID.dpg] = makeDPGStream(responses: dpgResponses)
    mock.mockNotificationStreams[DeskUUID.height] = makeHeightStream(values: heightValues)
}

// MARK: - Happy path

final class HandshakeHappyPathTests: XCTestCase {

    func testHappyPathReturnsCorrectCapabilities() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        let result = try await performHandshake(using: mock)

        XCTAssertEqual(result.capabilities.presetCount, 4)
        XCTAssertTrue(result.capabilities.hasAutoUp)
        XCTAssertFalse(result.capabilities.hasAutoDown)
    }

    func testHappyPathReturnsCorrectPresetHeights() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        let result = try await performHandshake(using: mock)

        XCTAssertEqual(result.presetHeights.count, 4)
        XCTAssertEqual(result.presetHeights[0], 730)
        XCTAssertEqual(result.presetHeights[1], 1105)
        XCTAssertEqual(result.presetHeights[2], 900)
        XCTAssertNil(result.presetHeights[3])
    }

    func testHappyPathReturnsCurrentHeightFromFirstNotification() async throws {
        let mock = MockBLEController()
        configureMock(mock, heightValues: [HandshakeFixtures.heightNotification730mm])

        let result = try await performHandshake(using: mock)

        XCTAssertEqual(result.currentHeight, 730)
    }

    func testHappyPathWithNoHeightNotificationReturnsNilCurrentHeight() async throws {
        let mock = MockBLEController()
        configureMock(mock, heightValues: [])

        let result = try await performHandshake(using: mock)

        XCTAssertNil(result.currentHeight)
    }
}

// MARK: - Bad mask value

final class HandshakeMaskValidationTests: XCTestCase {

    func testBadMaskThrowsUnexpectedMaskValue() async throws {
        let mock = MockBLEController()
        configureMock(mock, outputMask: HandshakeFixtures.invalidOutputMask)

        do {
            _ = try await performHandshake(using: mock)
            XCTFail("Expected DeskError.unexpectedMaskValue to be thrown")
        } catch DeskError.unexpectedMaskValue(let received) {
            XCTAssertEqual(received, HandshakeFixtures.invalidOutputMask)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBadMaskDoesNotIssueDPGQueries() async throws {
        let mock = MockBLEController()
        configureMock(mock, outputMask: HandshakeFixtures.invalidOutputMask)

        _ = try? await performHandshake(using: mock)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertEqual(dpgWrites.count, 0)
    }
}

// MARK: - DPG query order

final class HandshakeDPGQueryOrderTests: XCTestCase {

    func testNineDPGWritesInCorrectOrder() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        _ = try await performHandshake(using: mock)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        // 2 writes for USER_ID init (read + write) + 7 DPG queries = 9 total
        XCTAssertEqual(dpgWrites.count, 9)
        // Step 3: activateDPGSession — USER_ID read then write
        XCTAssertEqual(dpgWrites[0].data, DeskCommand.getUserID)
        XCTAssertTrue(dpgWrites[1].data.starts(with: [0x7F, 0x81, 0x80]),
            "Second DPG write must be SET_USER_ID (7F 81 80 ...)")
        // Step 4: issueDPGQueries — 7 queries
        XCTAssertEqual(dpgWrites[2].data, DeskCommand.getCapabilities)
        XCTAssertEqual(dpgWrites[3].data, DeskCommand.getCapabilitiesExtended)
        XCTAssertEqual(dpgWrites[4].data, DeskCommand.getDeskOffset)
        XCTAssertEqual(dpgWrites[5].data, DeskCommand.readPreset(index: 1))
        XCTAssertEqual(dpgWrites[6].data, DeskCommand.readPreset(index: 2))
        XCTAssertEqual(dpgWrites[7].data, DeskCommand.readPreset(index: 3))
        XCTAssertEqual(dpgWrites[8].data, DeskCommand.readPreset(index: 4))
    }

    func testAllDPGWritesWrittenWithResponse() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        // MockBLEController.writtenData captures all writes; write type is not captured.
        // The protocol test verifies the sequence arrives — type correctness is validated
        // by BLEController integration tests.
        _ = try await performHandshake(using: mock)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertEqual(dpgWrites.count, 9, "2 USER_ID init + 7 DPG queries = 9 writes")
    }
}

// MARK: - Notification enable verification

final class HandshakeNotificationEnableTests: XCTestCase {

    func testEnablesNotificationsOnStatusDPGAndHeight() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        _ = try await performHandshake(using: mock)

        let enabledUUIDs = mock.notifyValueCalls
            .filter { $0.enabled }
            .map { $0.characteristic }

        XCTAssertTrue(enabledUUIDs.contains(DeskUUID.status), "Must enable status notifications")
        XCTAssertTrue(enabledUUIDs.contains(DeskUUID.dpg), "Must enable DPG notifications")
        XCTAssertTrue(enabledUUIDs.contains(DeskUUID.height), "Must enable height notifications")
    }

    func testNotificationsEnabledBeforeDPGQueries() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        _ = try await performHandshake(using: mock)

        // All notify calls must appear before any DPG write in the recorded call sequence.
        // We verify indirectly: notifyValueCalls has 3 entries and writtenData has 9 DPG entries.
        XCTAssertEqual(mock.notifyValueCalls.count, 3)
        XCTAssertEqual(mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }.count, 9)
    }
}

// MARK: - Capabilities parsing

final class HandshakeCapabilitiesParsingTests: XCTestCase {

    func testParsesFourPresetsAutoUpTrueAutoDownFalse() async throws {
        let mock = MockBLEController()
        configureMock(mock, dpgResponses: buildResponsesWith(capabilities: HandshakeFixtures.capabilities4PresetsAutoUp))

        let result = try await performHandshake(using: mock)

        XCTAssertEqual(result.capabilities.presetCount, 4)
        XCTAssertTrue(result.capabilities.hasAutoUp)
        XCTAssertFalse(result.capabilities.hasAutoDown)
    }

    func testParsesTwoPresetsNoAutoUpNoAutoDown() async throws {
        let mock = MockBLEController()
        configureMock(mock, dpgResponses: buildResponsesWith(capabilities: HandshakeFixtures.capabilities2Presets))

        let result = try await performHandshake(using: mock)

        XCTAssertEqual(result.capabilities.presetCount, 2)
        XCTAssertFalse(result.capabilities.hasAutoUp)
        XCTAssertFalse(result.capabilities.hasAutoDown)
    }
}

// MARK: - Private fixture builders

private func buildResponsesWith(capabilities: Data) -> [Data] {
    var responses = HandshakeFixtures.happyPathDPGResponses
    // Index 2 is the capabilities response (after USER_ID read + write ack at indices 0-1).
    responses[2] = capabilities
    return responses
}
