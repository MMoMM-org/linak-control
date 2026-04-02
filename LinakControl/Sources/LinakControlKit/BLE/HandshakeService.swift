// HandshakeService.swift
// LinakControlKit — DPG1C initialization sequence executed after BLE connection.

import CoreBluetooth
import Foundation

// MARK: - HandshakeResult

/// The desk configuration returned after a successful handshake sequence.
public struct HandshakeResult: Sendable {

    /// Capabilities decoded from the GET_CAPABILITIES (7F 80) response.
    public let capabilities: DeskCapabilities

    /// Heights for preset slots 1–4 in mm. `nil` means the slot is unset.
    public let presetHeights: [Int?]

    /// The first height notification received during the handshake, if any.
    public let currentHeight: Int?

    public init(capabilities: DeskCapabilities, presetHeights: [Int?], currentHeight: Int?) {
        self.capabilities = capabilities
        self.presetHeights = presetHeights
        self.currentHeight = currentHeight
    }
}

// MARK: - DPG query descriptors

private struct DPGQuery {
    let command: Data
    let label: String
}

private let dpgQueries: [DPGQuery] = [
    DPGQuery(command: DeskCommand.getCapabilities,         label: "GET_CAPABILITIES"),
    DPGQuery(command: DeskCommand.getCapabilitiesExtended, label: "GET_CAPABILITIES_EXTENDED"),
    DPGQuery(command: DeskCommand.getUserID,               label: "GET_USER_ID"),
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
/// 3. Issue 8 DPG queries and collect notification responses (1 s timeout each).
/// 4. Parse capabilities and preset heights from the collected responses.
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

    // Capture first height notification in background before issuing DPG queries
    let heightTask = Task<Int?, Never> { await firstHeightNotification(from: bleController) }

    // Step 2: Validate output mask
    FileLog.debug("handshake: step 2 -- reading output mask", category: "handshake")
    let mask = try await bleController.read(DeskUUID.outputMask)
    FileLog.debug("handshake: step 2 -- mask=\(mask.map { String(format: "%02x", $0) }.joined())", category: "handshake")
    guard mask == Data([0x01]) else {
        FileLog.debug("handshake: ABORT -- unexpected mask value", category: "handshake")
        heightTask.cancel()
        throw DeskError.unexpectedMaskValue(mask)
    }

    // Step 3: Issue DPG queries and collect responses
    FileLog.debug("handshake: step 3 -- issuing \(dpgQueries.count) DPG queries", category: "handshake")
    let dpgResponses = try await issueDPGQueries(using: bleController)
    FileLog.debug("handshake: step 3 -- got \(dpgResponses.count) responses", category: "handshake")

    // Step 4: Parse results
    let capabilities = try parseCapabilitiesOrThrow(from: dpgResponses)
    let presetHeights = parsePresetHeights(from: dpgResponses)
    let currentHeight = await heightTask.value

    FileLog.debug("handshake: DONE -- height=\(currentHeight.map(String.init) ?? "nil") presets=\(presetHeights)", category: "handshake")

    return HandshakeResult(
        capabilities: capabilities,
        presetHeights: presetHeights,
        currentHeight: currentHeight
    )
}

// MARK: - Step implementations

private func enableNotifications(using bleController: any BLEControllerProtocol) async throws {
    try await bleController.setNotifyValue(true, for: DeskUUID.status)
    try await bleController.setNotifyValue(true, for: DeskUUID.dpg)
    try await bleController.setNotifyValue(true, for: DeskUUID.height)
}

private func firstHeightNotification(from bleController: any BLEControllerProtocol) async -> Int? {
    for await data in bleController.notifications(for: DeskUUID.height) {
        if let (heightMM, _) = parseHeightNotification(data) {
            return heightMM
        }
    }
    return nil
}

private func issueDPGQueries(
    using bleController: any BLEControllerProtocol
) async throws -> [Data] {
    // Obtain the notification stream once; consume one value per query.
    let dpgStream = bleController.notifications(for: DeskUUID.dpg)
    let notificationBuffer = DPGNotificationBuffer(stream: dpgStream)
    var responses: [Data] = []

    for (i, query) in dpgQueries.enumerated() {
        FileLog.debug("handshake: DPG query \(i+1)/\(dpgQueries.count) \(query.label)", category: "handshake")
        try await bleController.write(data: query.command, to: DeskUUID.dpg, type: .withResponse)
        let response = try await notificationBuffer.next()
        FileLog.debug("handshake: DPG response \(i+1) = \(response.count) bytes", category: "handshake")
        responses.append(response)
    }

    return responses
}

// MARK: - DPGNotificationBuffer

/// Wraps an AsyncStream iterator to allow safe consumption from sequential async calls
/// with per-element timeout support. Uses a class to avoid inout-capture issues.
private final class DPGNotificationBuffer: @unchecked Sendable {

    private var iterator: AsyncStream<Data>.AsyncIterator

    init(stream: AsyncStream<Data>) {
        self.iterator = stream.makeAsyncIterator()
    }

    /// Returns the next notification value, or throws `DeskError.handshakeTimeout` if
    /// no value arrives within 1 second.
    func next() async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            // Capture self (the buffer), not the inout iterator.
            group.addTask { [self] in
                guard let value = await self.iterator.next() else {
                    throw DeskError.handshakeTimeout
                }
                return value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(1))
                throw DeskError.handshakeTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private func parseCapabilitiesOrThrow(from responses: [Data]) throws -> DeskCapabilities {
    // responses[0] is the GET_CAPABILITIES (7F 80) response
    guard let capabilities = parseCapabilities(responses[0]) else {
        throw DeskError.handshakeTimeout
    }
    return capabilities
}

private func parsePresetHeights(from responses: [Data]) -> [Int?] {
    // responses[4..7] are preset 1–4 responses (indices 4, 5, 6, 7)
    return (4...7).map { parsePresetHeight(responses[$0]) }
}
