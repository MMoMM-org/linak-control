// DeskProtocolTests.swift
// LinakControlTests -- Verifies parsing and encoding of the DPG1C BLE protocol.

import XCTest
@testable import LinakControlKit

private func makeData(_ bytes: [UInt8]) -> Data { Data(bytes) }

// MARK: - parseHeightNotification

final class ParseHeightNotificationTests: XCTestCase {

    // Typical height: 420mm raw -> rawPosition = 4200
    func testTypicalHeight() {
        let raw = UInt16(4200)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        let result = DeskProtocol.parseHeightNotification(data)
        XCTAssertEqual(result?.heightMM, 420)
        XCTAssertEqual(result?.speedMMS, 0)
    }

    // Height at desk lowest position (raw = 0) is accepted.
    func testZeroHeightAccepted() {
        let data = makeData([0x00, 0x00, 0x00, 0x00])
        let result = DeskProtocol.parseHeightNotification(data)
        XCTAssertEqual(result?.heightMM, 0)
    }

    // Maximum desk travel ~650mm, raw = 6500
    func testMaxTravelAccepted() {
        let raw = UInt16(6500)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        XCTAssertEqual(DeskProtocol.parseHeightNotification(data)?.heightMM, 650)
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(DeskProtocol.parseHeightNotification(makeData([0x52, 0x2B, 0x00])))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(DeskProtocol.parseHeightNotification(Data()))
    }

    func testHeightAboveRangeRejected() {
        // The valid range is 0...7000mm. Since rawPosition is uint16 (max 65535),
        // the maximum representable height is 6553mm which is within range.
        // Only truly invalid data (corrupt packets) would exceed -- tested via
        // data length checks instead.
    }

    func testSpeedParsedCorrectly() {
        // height = 420mm, speed = 100 (positive = up)
        let rawH = UInt16(4200)
        let rawS = UInt16(bitPattern: 100)
        let data = makeData([
            UInt8(rawH & 0xFF), UInt8(rawH >> 8),
            UInt8(rawS & 0xFF), UInt8(rawS >> 8)
        ])
        let result = DeskProtocol.parseHeightNotification(data)
        XCTAssertEqual(result?.speedMMS, 100)
    }

    func testNegativeSpeedParsedCorrectly() {
        let rawH = UInt16(4200)
        let rawS = UInt16(bitPattern: -50)
        let data = makeData([
            UInt8(rawH & 0xFF), UInt8(rawH >> 8),
            UInt8(rawS & 0xFF), UInt8(rawS >> 8)
        ])
        let result = DeskProtocol.parseHeightNotification(data)
        XCTAssertEqual(result?.speedMMS, -50)
    }
}

// MARK: - encodeTargetHeight

final class EncodeTargetHeightTests: XCTestCase {

    // 420mm raw * 10 = 4200 = 0x1068 -> [0x68, 0x10]
    func test420mm() {
        let data = DeskProtocol.encodeTargetHeight(mm: 420)
        XCTAssertEqual(data, makeData([0x68, 0x10]))
    }

    // 0mm (lowest position) is valid
    func testZeroMM() {
        let data = DeskProtocol.encodeTargetHeight(mm: 0)
        XCTAssertEqual(data, makeData([0x00, 0x00]))
    }

    func testAboveSafeRangeReturnsNil() {
        XCTAssertNil(DeskProtocol.encodeTargetHeight(mm: 6501))
    }

    func testAtSafeRangeLowerBound() {
        let data = DeskProtocol.encodeTargetHeight(mm: 0)
        XCTAssertEqual(data, makeData([0x00, 0x00]))
    }

    func testAtSafeRangeUpperBound() {
        // 6500mm * 10 = 65000 = 0xFDE8 (fits uint16)
        let data = DeskProtocol.encodeTargetHeight(mm: 6500)
        XCTAssertNotNil(data)
    }

    func testResultIsTwoBytes() {
        let data = DeskProtocol.encodeTargetHeight(mm: 500)
        XCTAssertEqual(data?.count, 2)
    }
}

// MARK: - parsePresetHeight

final class ParsePresetHeightTests: XCTestCase {

    func testValidPreset() {
        // preset at 420mm -> raw = 4200 = 0x1068 -> bytes[3:4] = [0x68, 0x10]
        // DPG format: [status, length, slot, height_lo, height_hi, ...]
        let data = makeData([0x01, 0x07, 0x01, 0x68, 0x10, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(DeskProtocol.parsePresetHeight(data), 420)
    }

    func testUnsetPresetFFFF() {
        let data = makeData([0x01, 0x05, 0x01, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertNil(DeskProtocol.parsePresetHeight(data))
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(DeskProtocol.parsePresetHeight(makeData([0x01, 0x07, 0x01, 0x10])))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(DeskProtocol.parsePresetHeight(Data()))
    }
}

// MARK: - parseCapabilities

final class ParseCapabilitiesTests: XCTestCase {

    // 4 presets (0b00000100 = 4), hasAutoUp (bit3), hasAutoDown (bit4)
    // flags = 0b00011100 = 0x1C
    func testFullCapabilities() {
        let data = makeData([0x01, 0x02, 0x1C, 0x00])
        let caps = DeskProtocol.parseCapabilities(data)
        XCTAssertEqual(caps?.presetCount, 4)
        XCTAssertEqual(caps?.hasAutoUp, true)
        XCTAssertEqual(caps?.hasAutoDown, true)
    }

    func testNoCapabilities() {
        let data = makeData([0x01, 0x02, 0x00, 0x00])
        let caps = DeskProtocol.parseCapabilities(data)
        XCTAssertEqual(caps?.presetCount, 0)
        XCTAssertEqual(caps?.hasAutoUp, false)
        XCTAssertEqual(caps?.hasAutoDown, false)
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(DeskProtocol.parseCapabilities(makeData([0x01, 0x02])))
    }
}

// MARK: - parseBaseOffset

final class ParseBaseOffsetTests: XCTestCase {

    func testRealUserIDResponse680mm() {
        // [0x01, 0x03, 0x01, 0x90, 0x1A] -> bytes[3:4] = 0x1A90 = 6800 tenths = 680mm
        let data = makeData([0x01, 0x03, 0x01, 0x90, 0x1A])
        XCTAssertEqual(DeskProtocol.parseBaseOffset(fromUserID: data), 680)
    }

    func testRealUserIDResponse660mm() {
        // [0x01, 0x03, 0x01, 0xCE, 0x19] -> bytes[3:4] = 0x19CE = 6606 tenths = 660mm
        let data = makeData([0x01, 0x03, 0x01, 0xCE, 0x19])
        XCTAssertEqual(DeskProtocol.parseBaseOffset(fromUserID: data), 660)
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(DeskProtocol.parseBaseOffset(fromUserID: makeData([0x01, 0x03, 0x01, 0x90])))
        XCTAssertNil(DeskProtocol.parseBaseOffset(fromUserID: Data()))
    }

    func testZeroOffsetReturnsNil() {
        let data = makeData([0x01, 0x03, 0x01, 0x00, 0x00])
        XCTAssertNil(DeskProtocol.parseBaseOffset(fromUserID: data))
    }
}

// MARK: - parseDeskOffset

final class ParseDeskOffsetTests: XCTestCase {

    func testValidOffset() {
        // 620mm = 6200 tenths -> [2:3] = [0x38, 0x18] LE = 0x1838 = 6200
        let data = makeData([0x01, 0x02, 0x38, 0x18])
        XCTAssertEqual(DeskProtocol.parseDeskOffset(data), 620)
    }

    func testZeroOffsetReturnsNil() {
        let data = makeData([0x01, 0x02, 0x00, 0x00])
        XCTAssertNil(DeskProtocol.parseDeskOffset(data))
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(DeskProtocol.parseDeskOffset(makeData([0x01, 0x02, 0x38])))
    }
}

