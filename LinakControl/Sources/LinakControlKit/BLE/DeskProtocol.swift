// DeskProtocol.swift
// LinakControlKit

import Foundation

// MARK: - Data Models

/// Capabilities reported by the desk via the 7F 80 query on characteristic 99fa0011.
public struct DeskCapabilities {
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

/// Valid physical desk range in mm. Accepts a wider band than the mechanical
/// limits so marginal sensor readings are still usable.
private let validHeightRange = 500...1500

/// Safe command range in mm. Values outside this range are rejected by
/// `encodeTargetHeight` to protect the desk mechanics.
private let safeCommandRange = 600...1350

// MARK: - Decoding

/// Parse a 4-byte height notification from characteristic 99fa0021.
///
/// Layout (little-endian):
/// - Bytes [0:1]: position as uint16 in 0.1 mm units
/// - Bytes [2:3]: speed as int16 in raw units
///
/// Returns nil when data is too short or the decoded height falls outside
/// `validHeightRange` (500...1500 mm).
public func parseHeightNotification(_ data: Data) -> (heightMM: Int, speedMMS: Int)? {
    guard data.count >= 4 else { return nil }

    let rawPosition = UInt16(data[0]) | (UInt16(data[1]) << 8)
    let rawSpeed    = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))

    let heightMM = Int(rawPosition) / 10

    guard validHeightRange.contains(heightMM) else { return nil }

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
public func parseCapabilities(_ data: Data) -> DeskCapabilities? {
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
/// Height is stored as uint16 in 0.1 mm units at bytes [2:3] (little-endian).
/// Returns nil when data is too short, or when the preset is unset (all zeros).
public func parsePresetHeight(_ data: Data) -> Int? {
    guard data.count >= 4 else { return nil }

    let rawHeight = UInt16(data[2]) | (UInt16(data[3]) << 8)
    guard rawHeight != 0 else { return nil }

    return Int(rawHeight) / 10
}

// MARK: - Encoding

/// Encode a target height in mm as a 2-byte little-endian uint16 (0.1 mm units)
/// for writing to characteristic 99fa0031.
///
/// Rejects values outside the safe command range (600...1350 mm) and returns nil.
public func encodeTargetHeight(mm: Int) -> Data? {
    guard safeCommandRange.contains(mm) else { return nil }

    let rawValue = UInt16(mm * 10)
    return Data([
        UInt8(rawValue & 0xFF),
        UInt8(rawValue >> 8)
    ])
}
