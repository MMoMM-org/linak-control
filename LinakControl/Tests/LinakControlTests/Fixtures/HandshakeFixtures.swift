// HandshakeFixtures.swift
// LinakControlTests — Static byte fixtures for handshake protocol tests.

import Foundation

// MARK: - HandshakeFixtures

/// Static Data values representing real DPG1C BLE notification payloads.
///
/// Byte layouts match the protocol definitions in DeskProtocol.swift.
enum HandshakeFixtures {

    // MARK: Output mask

    /// Valid output mask: byte 0 = 0x01 (expected value).
    static let validOutputMask = Data([0x01])

    /// Invalid output mask: byte 0 = 0x02 (triggers DeskError.unexpectedMaskValue).
    static let invalidOutputMask = Data([0x02])

    // MARK: Capabilities (GET_CAPABILITIES response — 7F 80)
    //
    // Response layout: [echo_hi, echo_lo, flags, ...]
    //   echo_hi = 0x7F, echo_lo = 0x80
    //   flags byte 2:
    //     bits 0-2 = presetCount
    //     bit 3    = hasAutoUp
    //     bit 4    = hasAutoDown
    //
    // Example: 4 presets, autoUp=true, autoDown=false
    //   presetCount = 0b100 = 4
    //   hasAutoUp   = 1   → bit 3 set
    //   hasAutoDown = 0   → bit 4 clear
    //   flags = 0b00001100 = 0x0C

    /// 4 presets, autoUp=true, autoDown=false.
    static let capabilities4PresetsAutoUp = Data([0x7F, 0x80, 0x0C])

    /// 2 presets, no autoUp, no autoDown.
    static let capabilities2Presets = Data([0x7F, 0x80, 0x02])

    // MARK: Extended capabilities (GET_CAPABILITIES_EXTENDED — 7F 86)

    static let capabilitiesExtended = Data([0x7F, 0x86, 0x00])

    // MARK: User ID (GET_USER_ID — 7F 81)

    static let userID = Data([0x7F, 0x81, 0x01, 0x00])

    // MARK: Desk offset (GET_DESK_OFFSET — 7F 88)

    static let deskOffset = Data([0x7F, 0x88, 0x00, 0x00])

    // MARK: Preset heights (GET_MEMORY_POSITION_1..4 — 7F 89-8C)
    //
    // Height layout: [echo_hi, echo_lo, height_lo, height_hi]
    // height in 0.1 mm units (little-endian uint16)
    //
    //   730 mm  = 7300 tenths = 0x1C84 → lo=0x84, hi=0x1C
    //   1105 mm = 11050 tenths = 0x2B2A → lo=0x2A, hi=0x2B
    //   900 mm  = 9000 tenths = 0x2328 → lo=0x28, hi=0x23
    //   unset   = 0x0000

    /// Preset 1: 730 mm.
    static let preset1Height730mm = Data([0x7F, 0x89, 0x84, 0x1C])

    /// Preset 2: 1105 mm.
    static let preset2Height1105mm = Data([0x7F, 0x8A, 0x2A, 0x2B])

    /// Preset 3: 900 mm.
    static let preset3Height900mm = Data([0x7F, 0x8B, 0x28, 0x23])

    /// Preset 4: unset (all zeros in height bytes).
    static let preset4Unset = Data([0x7F, 0x8C, 0x00, 0x00])

    // MARK: Height notifications (characteristic 99fa0021)
    //
    // Layout: [pos_lo, pos_hi, speed_lo, speed_hi]
    // 730 mm = 7300 tenths = 0x1C84 → lo=0x84, hi=0x1C

    /// Height notification: 730 mm, speed = 0.
    static let heightNotification730mm = Data([0x84, 0x1C, 0x00, 0x00])

    // MARK: Full DPG response sequence (happy path — 8 responses in query order)

    static let happyPathDPGResponses: [Data] = [
        capabilities4PresetsAutoUp,
        capabilitiesExtended,
        userID,
        deskOffset,
        preset1Height730mm,
        preset2Height1105mm,
        preset3Height900mm,
        preset4Unset,
    ]
}
