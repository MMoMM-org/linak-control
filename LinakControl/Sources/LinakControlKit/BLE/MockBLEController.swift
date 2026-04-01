// MockBLEController.swift
// LinakControlKit — Test double for BLEControllerProtocol.

import CoreBluetooth
import Foundation

// MARK: - MockBLEController

/// A scripted mock for `BLEControllerProtocol` used in unit tests.
///
/// Configure `mockDesks`, `mockReadResponses`, and `mockNotificationStreams` before
/// exercising the system under test. Inspect `writtenData` to assert write behavior.
public final class MockBLEController: BLEControllerProtocol, @unchecked Sendable {

    // MARK: - Scripted inputs

    /// Desks emitted by ``scanForPeripherals()``. Yielded in order, then the stream terminates.
    public var mockDesks: [DiscoveredDesk] = []

    /// Data returned by ``read(_:)`` keyed by characteristic UUID.
    public var mockReadResponses: [CBUUID: Data] = [:]

    /// Streams returned by ``notifications(for:)`` keyed by characteristic UUID.
    public var mockNotificationStreams: [CBUUID: AsyncStream<Data>] = [:]

    // MARK: - Captured outputs

    /// All writes captured by ``write(data:to:type:)`` in call order.
    public private(set) var writtenData: [(data: Data, characteristic: CBUUID)] = []

    // MARK: - Behaviour control

    /// When `true`, ``connect(peripheralId:)`` throws ``BLEError/connectionFailed``.
    public var shouldFailConnect: Bool = false

    /// Artificial delay injected into ``connect(peripheralId:)`` before resolving.
    public var connectDelay: Duration = .zero

    // MARK: - BLEControllerProtocol — stateStream

    public let stateStream: AsyncStream<BLEState>

    private let stateContinuation: AsyncStream<BLEState>.Continuation

    /// Inject a BLE state change into ``stateStream``.
    public func emitState(_ state: BLEState) {
        stateContinuation.yield(state)
    }

    // MARK: - Init

    public init() {
        var cont: AsyncStream<BLEState>.Continuation!
        stateStream = AsyncStream { continuation in
            cont = continuation
        }
        stateContinuation = cont
    }

    // MARK: - BLEControllerProtocol — scan

    public func scanForPeripherals() -> AsyncStream<DiscoveredDesk> {
        let desks = mockDesks
        return AsyncStream { continuation in
            for desk in desks {
                continuation.yield(desk)
            }
            continuation.finish()
        }
    }

    public func stopScan() {
        // No-op in mock: scan streams terminate immediately after yielding mockDesks.
    }

    // MARK: - BLEControllerProtocol — connect / disconnect

    public func connect(peripheralId: UUID) async throws {
        if connectDelay > .zero {
            try await Task.sleep(for: connectDelay)
        }
        if shouldFailConnect {
            throw BLEError.connectionFailed
        }
    }

    public func disconnect() {
        // No-op in mock.
    }

    // MARK: - BLEControllerProtocol — write

    public func write(
        data: Data,
        to characteristic: CBUUID,
        type: CBCharacteristicWriteType
    ) async throws {
        writtenData.append((data: data, characteristic: characteristic))
    }

    // MARK: - BLEControllerProtocol — read

    public func read(_ characteristic: CBUUID) async throws -> Data {
        guard let data = mockReadResponses[characteristic] else {
            throw BLEError.characteristicNotFound(characteristic)
        }
        return data
    }

    // MARK: - BLEControllerProtocol — notifications

    public func notifications(for characteristic: CBUUID) -> AsyncStream<Data> {
        if let stream = mockNotificationStreams[characteristic] {
            return stream
        }
        return AsyncStream { continuation in continuation.finish() }
    }

    public func setNotifyValue(_ enabled: Bool, for characteristic: CBUUID) async throws {
        // No-op in mock: notification subscriptions are pre-wired via mockNotificationStreams.
    }
}
