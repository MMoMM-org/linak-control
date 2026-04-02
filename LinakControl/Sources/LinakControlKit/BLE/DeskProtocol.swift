// DeskProtocol.swift
// LinakControlKit

import Foundation

// MARK: - Data Models

/// Capabilities reported by the desk via the 7F 80 query on characteristic 99fa0011.
public struct DeskCapabilities: Sendable {
    public let presetCount: Int
    public let hasAutoUp: Bool
    public let hasAutoDown: Bool

    public init(presetCount: Int, hasAutoUp: Bool, hasAutoDown: Bool) {
        self.presetCount = presetCount
        self.hasAutoUp = hasAutoUp
        self.hasAutoDown = hasAutoDown
    }
}

// MARK: - Protocol Constants

/// Central desk protocol constants. All range checks and target calculations
/// reference these values. Raw positions are relative to the desk's lowest point.
public enum DeskLimits {
    /// Valid raw position range in mm accepted from height notifications.
    /// Typical travel is 0-650mm; wider band for sensor margin.
    public static let validHeightRange: ClosedRange<Int> = 0...7000

    /// Safe raw command range in mm for move-to targets.
    /// Upper limit 6500 keeps uint16 encoding safe (6500 * 10 = 65000 < 65535).
    public static let safeCommandRange: ClosedRange<Int> = 0...6500

    /// Auto-up target in 0.1mm units -- top of safe range.
    public static let autoUpTargetTenths: UInt16 = UInt16(safeCommandRange.upperBound * 10)

    /// Auto-down target in 0.1mm units -- bottom of safe range.
    public static let autoDownTargetTenths: UInt16 = UInt16(safeCommandRange.lowerBound * 10)
}

// MARK: - DeskProtocol namespace

/// Namespace for DPG1C BLE protocol parsing and encoding functions.
/// Groups all wire-format conversions in one place to avoid free-function pollution.
public enum DeskProtocol {

    // MARK: - Decoding

    /// Parse a 4-byte height notification from characteristic 99fa0021.
    ///
    /// Layout (little-endian):
    /// - Bytes [0:1]: position as uint16 in 0.1 mm units
    /// - Bytes [2:3]: speed as int16 in raw units
    ///
    /// Returns nil when data is too short or the decoded height falls outside
    /// `validHeightRange` (0...7000 mm).
    public static func parseHeightNotification(_ data: Data) -> (heightMM: Int, speedMMS: Int)? {
        guard data.count >= 4 else { return nil }

        let rawPosition = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let rawSpeed    = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))

        let heightMM = Int(rawPosition) / 10

        guard DeskLimits.validHeightRange.contains(heightMM) else { return nil }

        return (heightMM: heightMM, speedMMS: Int(rawSpeed))
    }

    /// Parse a capabilities response to the 7F 80 query on characteristic 99fa0011.
    ///
    /// Response byte 2 bit layout:
    /// - bits 0-2: preset count (0-4)
    /// - bit 3:   hasAutoUp
    /// - bit 4:   hasAutoDown
    ///
    /// Returns nil when data is too short to contain byte 2.
    public static func parseCapabilities(_ data: Data) -> DeskCapabilities? {
        guard data.count >= 3 else { return nil }

        let flags = data[2]
        let presetCount = Int(flags & 0b00000111)
        let hasAutoUp   = (flags & 0b00001000) != 0
        let hasAutoDown = (flags & 0b00010000) != 0

        return DeskCapabilities(
            presetCount: presetCount,
            hasAutoUp: hasAutoUp,
            hasAutoDown: hasAutoDown
        )
    }

    /// Parse a preset height response to a 7F 89-8C query on characteristic 99fa0011.
    ///
    /// DPG response format: [status, length, slot, height_lo, height_hi, ...].
    /// Height is a uint16 in 0.1 mm units at bytes [3:4] (little-endian).
    /// Returns nil when data is too short, or when the preset is unset (0xFFFF).
    public static func parsePresetHeight(_ data: Data) -> Int? {
        guard data.count >= 5 else { return nil }

        let rawHeight = UInt16(data[3]) | (UInt16(data[4]) << 8)
        guard rawHeight != 0, rawHeight != 0xFFFF else { return nil }

        return Int(rawHeight) / 10
    }

    /// Parse a desk offset response to the 7F 88 query on characteristic 99fa0011.
    ///
    /// DPG response format: [status, length, offset_lo, offset_hi, ...].
    /// Offset is a uint16 in 0.1 mm units at bytes [2:3] (little-endian).
    /// Returns nil when data is too short or the offset is zero.
    public static func parseDeskOffset(_ data: Data) -> Int? {
        guard data.count >= 4 else { return nil }

        let rawOffset = UInt16(data[2]) | (UInt16(data[3]) << 8)
        guard rawOffset != 0 else { return nil }

        return Int(rawOffset) / 10
    }

    /// Parse the base height offset from a USER_ID (0x81) response.
    /// The offset is stored as LE uint16 in 0.1mm units at bytes [3:4].
    /// Returns nil when data is too short.
    public static func parseBaseOffset(fromUserID data: Data) -> Int? {
        guard data.count >= 5 else { return nil }
        let raw = UInt16(data[3]) | (UInt16(data[4]) << 8)
        guard raw != 0 else { return nil }
        return Int(raw) / 10
    }

    // MARK: - Encoding

    /// Encode a target height in mm as a 2-byte little-endian uint16 (0.1 mm units)
    /// for writing to characteristic 99fa0031.
    ///
    /// Rejects values outside the safe command range (0...6500 mm) and returns nil.
    public static func encodeTargetHeight(mm: Int) -> Data? {
        guard DeskLimits.safeCommandRange.contains(mm) else { return nil }

        let rawValue = UInt16(mm * 10)
        return Data([
            UInt8(rawValue & 0xFF),
            UInt8(rawValue >> 8)
        ])
    }
}
