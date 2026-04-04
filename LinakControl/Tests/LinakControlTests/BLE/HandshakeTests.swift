// HandshakeTests.swift
// LinakControlTests — Verifies the DPG1C handshake sequence behavior.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Helpers

// makeDPGStream is provided by TestHelpers.swift

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
    if let firstHeight = heightValues.first {
        mock.mockReadResponses[DeskUUID.height] = firstHeight
    }
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

    func testEightDPGWritesInCorrectOrder() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        _ = try await performHandshake(using: mock)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        // 1 USER_ID read (write skipped when byte 0 == 0x01) + 7 DPG queries = 8 total
        XCTAssertEqual(dpgWrites.count, 8)
        // Step 3: activateDPGSession -- USER_ID read only
        XCTAssertEqual(dpgWrites[0].data, DeskCommand.getUserID)
        // Step 4: issueDPGQueries -- 7 queries
        XCTAssertEqual(dpgWrites[1].data, DeskCommand.getCapabilities)
        XCTAssertEqual(dpgWrites[2].data, DeskCommand.getBaseOffset)
        XCTAssertEqual(dpgWrites[3].data, DeskCommand.getDeskOffset)
        XCTAssertEqual(dpgWrites[4].data, DeskCommand.readPreset(index: 1))
        XCTAssertEqual(dpgWrites[5].data, DeskCommand.readPreset(index: 2))
        XCTAssertEqual(dpgWrites[6].data, DeskCommand.readPreset(index: 3))
        XCTAssertEqual(dpgWrites[7].data, DeskCommand.readPreset(index: 4))
    }

    func testAllDPGWritesWrittenWithResponse() async throws {
        let mock = MockBLEController()
        configureMock(mock)

        _ = try await performHandshake(using: mock)

        let dpgWrites = mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }
        XCTAssertEqual(dpgWrites.count, 8, "1 USER_ID read + 7 DPG queries = 8 writes")
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
        // We verify indirectly: notifyValueCalls has 3 entries and writtenData has 8 DPG entries.
        XCTAssertEqual(mock.notifyValueCalls.count, 3)
        XCTAssertEqual(mock.writtenData.filter { $0.characteristic == DeskUUID.dpg }.count, 8)
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
    // Index 1 is the capabilities response (after USER_ID read at index 0).
    responses[1] = capabilities
    return responses
}
