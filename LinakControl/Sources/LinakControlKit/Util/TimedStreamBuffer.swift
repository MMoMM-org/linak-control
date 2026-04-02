// TimedStreamBuffer.swift
// LinakControlKit -- Actor-isolated async stream buffer with per-element timeout.
//
// Shared by HandshakeService and PresetSave for consuming DPG notification
// responses one at a time with a 1-second deadline per element.

import Foundation

/// Wraps an `AsyncStream<Data>` iterator behind actor isolation, providing
/// safe sequential consumption with a per-element timeout.
///
/// Using an actor instead of `@unchecked Sendable` prevents data races on
/// the mutable iterator when accessed from task-group child tasks.
internal actor TimedStreamBuffer {

    /// Box that holds the mutable iterator. Actors cannot call mutating methods
    /// on stored value-type properties, so we wrap in a reference type.
    private final class IteratorBox {
        var iterator: AsyncStream<Data>.AsyncIterator
        init(_ stream: AsyncStream<Data>) { iterator = stream.makeAsyncIterator() }
        func next() async -> Data? { await iterator.next() }
    }

    private let box: IteratorBox
    private let timeout: Duration

    init(stream: AsyncStream<Data>, timeout: Duration = .seconds(1)) {
        self.box = IteratorBox(stream)
        self.timeout = timeout
    }

    /// Returns the next value from the stream, or throws `DeskError.handshakeTimeout`
    /// if no value arrives within the configured timeout.
    func next() async throws -> Data {
        let iteratorBox = box
        let timeoutDuration = timeout

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                guard let value = await iteratorBox.next() else {
                    throw DeskError.handshakeTimeout
                }
                return value
            }
            group.addTask {
                try await Task.sleep(for: timeoutDuration)
                throw DeskError.handshakeTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
