// TestHelpers.swift
// LinakControlTests — Shared test utilities to eliminate duplication across test files.
//
// Contains common factory functions used by multiple test suites:
// - makeTempConfigStore: isolated ConfigStore backed by a temp directory
// - waitFor: async polling helper
// - makeHeightPacket: BLE height notification packet builder
// - makeDPGStream: finite AsyncStream from a response array

import Foundation
@testable import LinakControlKit

// MARK: - ConfigStore Factory

/// Builds a ConfigStore backed by a unique temp directory so tests don't share on-disk state.
///
/// - Parameters:
///   - tag: Label embedded in the directory name for debugging (defaults to caller file name).
///   - config: Optional pre-populated config to save immediately.
///   - pairedUUID: Convenience shortcut — sets `pairedDeskUUID` on a default config.
func makeTempConfigStore(
    tag: String = "Test",
    config: AppConfig? = nil,
    pairedUUID: UUID? = nil
) -> ConfigStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(tag)-\(UUID().uuidString)")
    let store = ConfigStore(directoryURL: tempDir)
    if let config {
        try? store.save(config)
    } else if let uuid = pairedUUID {
        var cfg = AppConfig.default
        cfg.pairedDeskUUID = uuid.uuidString
        try? store.save(cfg)
    }
    return store
}

// MARK: - Async Polling

/// Polls until `predicate` returns true or `timeout` elapses.
///
/// Useful for waiting on actor state propagation in tests where direct
/// `await` isn't sufficient due to background task scheduling.
func waitFor(
    timeout: TimeInterval = 2.0,
    predicate: @escaping () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - BLE Packet Builders

/// Creates a 4-byte BLE height notification matching `parseHeightNotification(_:)` layout.
///
/// - Parameters:
///   - mm: Height in millimetres.
///   - speedMMS: Speed in mm/s (0 = stationary).
/// - Returns: 4-byte Data: [pos_lo, pos_hi, speed_lo, speed_hi].
func makeHeightPacket(mm: Int, speedMMS: Int = 0) -> Data {
    let rawPosition = UInt16(mm * 10)
    let rawSpeed = UInt16(bitPattern: Int16(clamping: speedMMS))
    return Data([
        UInt8(rawPosition & 0xFF),
        UInt8(rawPosition >> 8),
        UInt8(rawSpeed & 0xFF),
        UInt8(rawSpeed >> 8)
    ])
}

// MARK: - AsyncStream Builders

/// Creates a finite `AsyncStream<Data>` that yields each response then terminates.
///
/// Use for scripting DPG handshake or notification sequences in tests.
func makeDPGStream(responses: [Data]) -> AsyncStream<Data> {
    AsyncStream { continuation in
        for response in responses {
            continuation.yield(response)
        }
        continuation.finish()
    }
}
