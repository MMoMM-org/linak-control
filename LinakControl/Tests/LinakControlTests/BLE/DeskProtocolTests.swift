// DeskProtocolTests.swift
// LinakControlTests

import XCTest
@testable import LinakControlKit

// MARK: - Helpers

private func makeData(_ bytes: [UInt8]) -> Data {
    Data(bytes)
}

// MARK: - parseHeightNotification

final class ParseHeightNotificationTests: XCTestCase {

    // SDD traced walkthrough — row 1: stationary at 110.9 cm
    func testStationaryAt1109mm() {
        let data = makeData([0x52, 0x2B, 0x00, 0x00])
        let result = parseHeightNotification(data)
        XCTAssertEqual(result?.heightMM, 1109)
        XCTAssertEqual(result?.speedMMS, 0)
    }

    // SDD traced walkthrough — row 2: moving up at ~26 mm/s
    func testMovingUpAt1109mm() {
        let data = makeData([0x52, 0x2B, 0x1A, 0x00])
        let result = parseHeightNotification(data)
        XCTAssertEqual(result?.heightMM, 1109)
        XCTAssertEqual(result?.speedMMS, 26)
    }

    // SDD traced walkthrough — row 3: moving down at ~16 mm/s
    func testMovingDownAt737mm() {
        let data = makeData([0xD2, 0x1C, 0xF0, 0xFF])
        let result = parseHeightNotification(data)
        XCTAssertEqual(result?.heightMM, 737)
        XCTAssertEqual(result?.speedMMS, -16)
    }

    // SDD traced walkthrough — row 4: all zeros rejected by range check
    func testZeroHeightRejected() {
        let data = makeData([0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(parseHeightNotification(data))
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(parseHeightNotification(makeData([0x52, 0x2B, 0x00])))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(parseHeightNotification(Data()))
    }

    func testHeightBelowRangeRejected() {
        // rawPosition = 4990 -> heightMM = 499 (below 500 floor)
        let raw = UInt16(4990)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        XCTAssertNil(parseHeightNotification(data))
    }

    func testHeightAboveRangeRejected() {
        // rawPosition = 15010 -> heightMM = 1501 (above 1500 ceiling)
        let raw = UInt16(15010)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        XCTAssertNil(parseHeightNotification(data))
    }

    func testHeightAtLowerBoundAccepted() {
        // heightMM = 500 (boundary)
        let raw = UInt16(5000)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        XCTAssertEqual(parseHeightNotification(data)?.heightMM, 500)
    }

    func testHeightAtUpperBoundAccepted() {
        // heightMM = 1500 (boundary)
        let raw = UInt16(15000)
        let data = makeData([UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
        XCTAssertEqual(parseHeightNotification(data)?.heightMM, 1500)
    }
}

// MARK: - encodeTargetHeight

final class EncodeTargetHeightTests: XCTestCase {

    // 1105mm * 10 = 11050 = 0x2B2A -> [0x2A, 0x2B]
    func test1105mm() {
        let data = encodeTargetHeight(mm: 1105)
        XCTAssertEqual(data, makeData([0x2A, 0x2B]))
    }

    // 737mm * 10 = 7370 = 0x1CCA -> [0xCA, 0x1C]
    func test737mm() {
        let data = encodeTargetHeight(mm: 737)
        XCTAssertEqual(data, makeData([0xCA, 0x1C]))
    }

    func testBelowSafeRangeReturnsNil() {
        XCTAssertNil(encodeTargetHeight(mm: 599))
    }

    func testAboveSafeRangeReturnsNil() {
        XCTAssertNil(encodeTargetHeight(mm: 1351))
    }

    func testAtSafeRangeLowerBound() {
        // 600mm * 10 = 6000 = 0x1770 -> [0x70, 0x17]
        let data = encodeTargetHeight(mm: 600)
        XCTAssertEqual(data, makeData([0x70, 0x17]))
    }

    func testAtSafeRangeUpperBound() {
        // 1350mm * 10 = 13500 = 0x34BC -> [0xBC, 0x34]
        let data = encodeTargetHeight(mm: 1350)
        XCTAssertEqual(data, makeData([0xBC, 0x34]))
    }

    func testOutOfRangeValue500mm() {
        XCTAssertNil(encodeTargetHeight(mm: 500))
    }

    func testOutOfRangeValue1400mm() {
        XCTAssertNil(encodeTargetHeight(mm: 1400))
    }

    func testResultIsTwoBytes() {
        let data = encodeTargetHeight(mm: 1000)
        XCTAssertEqual(data?.count, 2)
    }
}

// MARK: - parsePresetHeight

final class ParsePresetHeightTests: XCTestCase {

    func testValidPreset() {
        // preset at 1000mm -> raw = 10000 = 0x2710 -> bytes[2:3] = [0x10, 0x27]
        let data = makeData([0x7F, 0x89, 0x10, 0x27])
        XCTAssertEqual(parsePresetHeight(data), 1000)
    }

    func testUnsetPresetAllZeros() {
        let data = makeData([0x7F, 0x89, 0x00, 0x00])
        XCTAssertNil(parsePresetHeight(data))
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(parsePresetHeight(makeData([0x7F, 0x89, 0x10])))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(parsePresetHeight(Data()))
    }
}

// MARK: - parseCapabilities

final class ParseCapabilitiesTests: XCTestCase {

    // 4 presets (0b00000100 = 4), hasAutoUp (bit3), hasAutoDown (bit4)
    // flags = 0b00011100 = 0x1C
    func testFullCapabilities() {
        let data = makeData([0x7F, 0x80, 0x1C])
        let caps = parseCapabilities(data)
        XCTAssertEqual(caps?.presetCount, 4)
        XCTAssertEqual(caps?.hasAutoUp, true)
        XCTAssertEqual(caps?.hasAutoDown, true)
    }

    func testNoCapabilities() {
        let data = makeData([0x7F, 0x80, 0x00])
        let caps = parseCapabilities(data)
        XCTAssertEqual(caps?.presetCount, 0)
        XCTAssertEqual(caps?.hasAutoUp, false)
        XCTAssertEqual(caps?.hasAutoDown, false)
    }

    func testOnlyAutoUp() {
        // bit3 set: 0b00001000 = 0x08
        let data = makeData([0x7F, 0x80, 0x08])
        let caps = parseCapabilities(data)
        XCTAssertEqual(caps?.hasAutoUp, true)
        XCTAssertEqual(caps?.hasAutoDown, false)
    }

    func testOnlyAutoDown() {
        // bit4 set: 0b00010000 = 0x10
        let data = makeData([0x7F, 0x80, 0x10])
        let caps = parseCapabilities(data)
        XCTAssertEqual(caps?.hasAutoUp, false)
        XCTAssertEqual(caps?.hasAutoDown, true)
    }

    func testDataTooShortReturnsNil() {
        XCTAssertNil(parseCapabilities(makeData([0x7F, 0x80])))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(parseCapabilities(Data()))
    }

    func testTwoPresetsNoAutoFeatures() {
        // 0b00000010 = 0x02
        let data = makeData([0x7F, 0x80, 0x02])
        let caps = parseCapabilities(data)
        XCTAssertEqual(caps?.presetCount, 2)
        XCTAssertEqual(caps?.hasAutoUp, false)
        XCTAssertEqual(caps?.hasAutoDown, false)
    }
}
