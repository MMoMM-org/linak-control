// HandshakeService.swift
// LinakControlKit -- DPG1C initialization sequence executed after BLE connection.

import CoreBluetooth
import Foundation

// MARK: - HandshakeResult

/// The desk configuration returned after a successful handshake sequence.
public struct HandshakeResult: Sendable {

    /// Capabilities decoded from the GET_CAPABILITIES (7F 80) response.
    public let capabilities: DeskCapabilities

    /// Heights for preset slots 1-4 in mm. `nil` means the slot is unset.
    public let presetHeights: [Int?]

    /// The first height notification received during the handshake, if any.
    public let currentHeight: Int?

    /// Desk base offset in mm, parsed from GET_DESK_OFFSET. `nil` if not reported.
    public let deskOffsetMM: Int?

    public init(capabilities: DeskCapabilities, presetHeights: [Int?], currentHeight: Int?, deskOffsetMM: Int? = nil) {
        self.capabilities = capabilities
        self.presetHeights = presetHeights
        self.currentHeight = currentHeight
        self.deskOffsetMM = deskOffsetMM
    }
}

// MARK: - DPG query descriptors

private struct DPGQuery {
    let command: Data
    let label: String
}

/// Post-init queries issued after the DPG session is activated.
private let dpgQueries: [DPGQuery] = [
    DPGQuery(command: DeskCommand.getCapabilities,         label: "GET_CAPABILITIES"),
    DPGQuery(command: DeskCommand.getCapabilitiesExtended, label: "GET_CAPABILITIES_EXTENDED"),
    DPGQuery(command: DeskCommand.getDeskOffset,           label: "GET_DESK_OFFSET"),
    DPGQuery(command: DeskCommand.readPreset(index: 1)!,   label: "GET_MEMORY_POSITION_1"),
    DPGQuery(command: DeskCommand.readPreset(index: 2)!,   label: "GET_MEMORY_POSITION_2"),
    DPGQuery(command: DeskCommand.readPreset(index: 3)!,   label: "GET_MEMORY_POSITION_3"),
    DPGQuery(command: DeskCommand.readPreset(index: 4)!,   label: "GET_MEMORY_POSITION_4"),
]

// MARK: - Public entry point

/// Execute the DPG1C initialization sequence and return the parsed desk configuration.
///
/// The sequence runs in this exact order:
/// 1. Enable notifications on status (0003), dpg (0011), and height (0021).
/// 2. Read and validate the output mask (0029).
/// 3. Activate the DPG session by reading the USER_ID, ensuring byte 0 is 0x01,
///    and writing it back. The desk rejects all queries without this step.
/// 4. Issue DPG queries (capabilities, offset, presets) and collect responses.
/// 5. Parse capabilities and preset heights from the collected responses.
///
/// - Parameter bleController: The BLE controller connected to the desk.
/// - Returns: A `HandshakeResult` with capabilities, preset heights, and optional current height.
/// - Throws: `DeskError` for protocol violations or timeouts; `BLEError` for transport failures.
public func performHandshake(using bleController: any BLEControllerProtocol) async throws -> HandshakeResult {

    FileLog.debug("handshake: START", category: "handshake")

    // Step 1: Enable notifications
    FileLog.debug("handshake: step 1 -- enabling notifications", category: "handshake")
    try await enableNotifications(using: bleController)
    FileLog.debug("handshake: step 1 -- notifications enabled", category: "handshake")

    // Step 2: Validate output mask
    FileLog.debug("handshake: step 2 -- reading output mask", category: "handshake")
    let mask = try await bleController.read(DeskUUID.outputMask)
    FileLog.debug("handshake: step 2 -- mask=\(mask.map { String(format: "%02x", $0) }.joined())", category: "handshake")
    guard mask == Data([0x01]) else {
        FileLog.debug("handshake: ABORT -- unexpected mask value", category: "handshake")
        throw DeskError.unexpectedMaskValue(mask)
    }

    // Step 3: Activate DPG session via USER_ID read + write
    FileLog.debug("handshake: step 3 -- activating DPG session (USER_ID init)", category: "handshake")
    let dpgStream = bleController.notifications(for: DeskUUID.dpg)
    let notificationBuffer = TimedStreamBuffer(stream: dpgStream)
    try await activateDPGSession(using: bleController, buffer: notificationBuffer)
    FileLog.debug("handshake: step 3 -- DPG session activated", category: "handshake")

    // Step 4: Issue DPG queries and collect responses
    FileLog.debug("handshake: step 4 -- issuing \(dpgQueries.count) DPG queries", category: "handshake")
    let dpgResponses = try await issueDPGQueries(using: bleController, buffer: notificationBuffer)
    FileLog.debug("handshake: step 4 -- got \(dpgResponses.count) responses", category: "handshake")

    // Step 5: Parse results
    let capabilities = try parseCapabilitiesOrThrow(from: dpgResponses)
    let deskOffsetMM = parseDeskOffset(from: dpgResponses)
    let presetHeights = parsePresetHeights(from: dpgResponses)

    // Read current height directly from the characteristic. This avoids
    // fighting with the height notification listener for the stream and
    // eliminates a 3-second timeout wait on stationary desks.
    var currentHeight: Int?
    FileLog.debug("handshake: step 5 -- reading current height", category: "handshake")
    if let data = try? await bleController.read(DeskUUID.height),
       let (h, _) = parseHeightNotification(data) {
        currentHeight = h
    }

    FileLog.debug("handshake: DONE -- height=\(currentHeight.map(String.init) ?? "nil") offset=\(deskOffsetMM.map(String.init) ?? "nil") presets=\(presetHeights)", category: "handshake")

    return HandshakeResult(
        capabilities: capabilities,
        presetHeights: presetHeights,
        currentHeight: currentHeight,
        deskOffsetMM: deskOffsetMM
    )
}

// MARK: - Step implementations

private func enableNotifications(using bleController: any BLEControllerProtocol) async throws {
    try await bleController.setNotifyValue(true, for: DeskUUID.status)
    try await bleController.setNotifyValue(true, for: DeskUUID.dpg)
    try await bleController.setNotifyValue(true, for: DeskUUID.height)
}


/// Reads the USER_ID from the desk, ensures byte 0 is 0x01, and writes it back
/// to activate the DPG query session. Without this step the desk returns 0x0B
/// error responses to all DPG queries.
private func activateDPGSession(
    using bleController: any BLEControllerProtocol,
    buffer: TimedStreamBuffer
) async throws {
    // Read current USER_ID
    FileLog.debug("handshake: USER_ID read", category: "handshake")
    try await bleController.write(data: DeskCommand.getUserID, to: DeskUUID.dpg, type: .withResponse)
    let userIdResponse = try await buffer.next()
    let hex = userIdResponse.map { String(format: "%02x", $0) }.joined(separator: " ")
    FileLog.debug("handshake: USER_ID response = [\(hex)] (\(userIdResponse.count) bytes)", category: "handshake")

    // Build the user data payload for the write-back.
    // DPG response format: [status, length, ...payload].
    // Extract payload (skip status + length bytes).
    // If the response is an error (0x0b) or too short, use a default payload.
    var userData: Data
    if userIdResponse.count > 2 && userIdResponse[0] != 0x0b {
        userData = Data(userIdResponse[2...])
    } else {
        // Desk hasn't been initialized yet -- use a minimal default.
        userData = Data([0x01])
    }

    // DPG1C requires byte 0 of user data to be 0x01.
    // Only write back if modification is needed — avoids sending corrupted
    // data back to the desk and getting 0x0B rejection errors.
    if !userData.isEmpty && userData[0] == 0x01 {
        FileLog.debug("handshake: USER_ID byte 0 already 0x01, skipping write-back", category: "handshake")
    } else {
        if userData.isEmpty {
            userData = Data([0x01])
        } else {
            userData[0] = 0x01
        }
        let setCommand = DeskCommand.setUserID(userData: userData)
        let setHex = setCommand.map { String(format: "%02x", $0) }.joined(separator: " ")
        FileLog.debug("handshake: USER_ID write = [\(setHex)]", category: "handshake")
        try await bleController.write(data: setCommand, to: DeskUUID.dpg, type: .withResponse)
        let writeResponse = try await buffer.next()
        let writeHex = writeResponse.map { String(format: "%02x", $0) }.joined(separator: " ")
        FileLog.debug("handshake: USER_ID write response = [\(writeHex)]", category: "handshake")
    }
}

private func issueDPGQueries(
    using bleController: any BLEControllerProtocol,
    buffer: TimedStreamBuffer
) async throws -> [Data] {
    var responses: [Data] = []

    for (i, query) in dpgQueries.enumerated() {
        FileLog.debug("handshake: DPG query \(i+1)/\(dpgQueries.count) \(query.label)", category: "handshake")
        try await bleController.write(data: query.command, to: DeskUUID.dpg, type: .withResponse)
        let response = try await buffer.next()
        let hex = response.map { String(format: "%02x", $0) }.joined(separator: " ")
        FileLog.debug("handshake: DPG response \(i+1) = [\(hex)] (\(response.count) bytes)", category: "handshake")
        responses.append(response)
    }

    return responses
}

// TimedStreamBuffer is now TimedStreamBuffer (Util/TimedStreamBuffer.swift).

private func parseCapabilitiesOrThrow(from responses: [Data]) throws -> DeskCapabilities {
    // responses[0] is the GET_CAPABILITIES (7F 80) response
    guard let capabilities = parseCapabilities(responses[0]) else {
        throw DeskError.handshakeTimeout
    }
    return capabilities
}

private func parseDeskOffset(from responses: [Data]) -> Int? {
    // responses[2] is the GET_DESK_OFFSET response
    guard responses.count > 2 else { return nil }
    return parseDeskOffset(responses[2])
}

private func parsePresetHeights(from responses: [Data]) -> [Int?] {
    // responses[3..6] are preset 1-4 responses (indices 3, 4, 5, 6)
    return (3...6).map { parsePresetHeight(responses[$0]) }
}
