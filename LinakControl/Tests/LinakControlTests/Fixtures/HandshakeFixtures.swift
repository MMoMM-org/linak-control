// HandshakeFixtures.swift
// LinakControlTests -- Static byte fixtures for handshake protocol tests.

import Foundation

// MARK: - HandshakeFixtures

/// Static Data values representing real DPG1C BLE notification payloads.
///
/// DPG response format: [status, length, ...payload]
///   status = 0x01 (success) or 0x0B (error)
///   length = number of payload bytes following
///
/// Byte layouts match the protocol definitions in DeskProtocol.swift.
enum HandshakeFixtures {

    // MARK: Output mask

    /// Valid output mask: byte 0 = 0x01 (expected value).
    static let validOutputMask = Data([0x01])

    /// Invalid output mask: byte 0 = 0x02 (triggers DeskError.unexpectedMaskValue).
    static let invalidOutputMask = Data([0x02])

    // MARK: Capabilities (GET_CAPABILITIES response -- 7F 80 00)
    //
    // Response layout: [status, length, flags, extra]
    //   flags (byte 2):
    //     bits 0-2 = presetCount
    //     bit 3    = hasAutoUp
    //     bit 4    = hasAutoDown
    //
    // Example: 4 presets, autoUp=true, autoDown=false
    //   presetCount = 0b100 = 4
    //   hasAutoUp   = 1   -> bit 3 set
    //   hasAutoDown = 0   -> bit 4 clear
    //   flags = 0b00001100 = 0x0C

    /// 4 presets, autoUp=true, autoDown=false.
    static let capabilities4PresetsAutoUp = Data([0x01, 0x02, 0x0C, 0x01])

    /// 2 presets, no autoUp, no autoDown.
    static let capabilities2Presets = Data([0x01, 0x02, 0x02, 0x00])

    // MARK: Extended capabilities (GET_CAPABILITIES_EXTENDED -- 7F 86 00)

    static let capabilitiesExtended = Data([0x01, 0x02, 0x00, 0x00])

    // MARK: User ID (GET_USER_ID -- 7F 81 00)
    //
    // Response layout: [status, length, ...userIdPayload]
    // Byte 0 of payload must be 0x01 for DPG1C.

    static let userID = Data([0x01, 0x03, 0x01, 0x90, 0x1A])

    // MARK: USER_ID write acknowledgement

    /// Acknowledgement returned by the desk after a SET_USER_ID (7F 81 80 ...) write.
    static let userIDWriteAck = Data([0x01, 0x00])

    // MARK: Desk offset (GET_DESK_OFFSET -- 7F 88 00)

    static let deskOffset = Data([0x01, 0x02, 0x00, 0x00])

    // MARK: Preset heights (GET_MEMORY_POSITION_1..4 -- 7F 89-8C 00)
    //
    // Response layout: [status, length, slot, height_lo, height_hi, ...]
    // height in 0.1 mm units (little-endian uint16) at bytes [3:4]
    //
    //   730 mm  = 7300 tenths = 0x1C84 -> lo=0x84, hi=0x1C
    //   1105 mm = 11050 tenths = 0x2B2A -> lo=0x2A, hi=0x2B
    //   900 mm  = 9000 tenths = 0x2328 -> lo=0x28, hi=0x23
    //   unset   = 0xFFFF

    /// Preset 1: 730 mm.
    static let preset1Height730mm = Data([0x01, 0x07, 0x01, 0x84, 0x1C, 0x00, 0x00, 0x00, 0x00])

    /// Preset 2: 1105 mm.
    static let preset2Height1105mm = Data([0x01, 0x07, 0x02, 0x2A, 0x2B, 0x00, 0x00, 0x00, 0x00])

    /// Preset 3: 900 mm.
    static let preset3Height900mm = Data([0x01, 0x07, 0x03, 0x28, 0x23, 0x00, 0x00, 0x00, 0x00])

    /// Preset 4: unset.
    static let preset4Unset = Data([0x01, 0x05, 0x04, 0xFF, 0xFF, 0xFF, 0xFF])

    // MARK: Height notifications (characteristic 99fa0021)
    //
    // Layout: [pos_lo, pos_hi, speed_lo, speed_hi]
    // 730 mm = 7300 tenths = 0x1C84 -> lo=0x84, hi=0x1C

    /// Height notification: 730 mm, speed = 0.
    static let heightNotification730mm = Data([0x84, 0x1C, 0x00, 0x00])

    // MARK: Full DPG response sequence (happy path -- 9 responses)
    //
    // The handshake first activates the DPG session via USER_ID read + write (2 responses),
    // then issues 7 DPG queries (capabilities, capabilitiesExtended, deskOffset, presets 1-4).

    static let happyPathDPGResponses: [Data] = [
        // activateDPGSession: USER_ID read response + write acknowledgement
        userID,
        userIDWriteAck,
        // issueDPGQueries: 7 query responses
        capabilities4PresetsAutoUp,
        capabilitiesExtended,
        deskOffset,
        preset1Height730mm,
        preset2Height1105mm,
        preset3Height900mm,
        preset4Unset,
    ]
}
