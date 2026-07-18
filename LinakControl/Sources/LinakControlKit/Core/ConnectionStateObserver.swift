// ConnectionStateObserver.swift
// LinakControlKit — Watches DeskManager state transitions and routes to NotificationPosting.

import Foundation

// MARK: - ConnectionStateObserver

/// Observes `DeskManager.stateStream` and fires notifications on connection state transitions.
///
/// Rules:
/// - `.connected` after `.disconnected` or `.scanning` (reconnect) → postConnected()
/// - `.disconnected` when NOT user-initiated → postDisconnected()
/// - Initial connect (scanning → connecting → connected) → no "Connected" notification
public final class ConnectionStateObserver: Sendable {

    private let deskManager: DeskManager
    private let notificationPoster: any NotificationPosting

    public init(deskManager: DeskManager, notificationPoster: any NotificationPosting) {
        self.deskManager = deskManager
        self.notificationPoster = notificationPoster
    }

    /// Starts observing the state stream. Returns the background task so the caller can cancel it.
    @discardableResult
    public func start() -> Task<Void, Never> {
        let manager = deskManager
        let poster = notificationPoster
        return Task {
            await observeStateStream(manager: manager, poster: poster)
        }
    }
}

// MARK: - Private observation loop

private func observeStateStream(
    manager: DeskManager,
    poster: any NotificationPosting
) async {
    var previous: ConnectionState = .disconnected
    var hasEverConnected = false
    var previousNeedsReference = false

    for await state in await manager.stateStream {
        guard !Task.isCancelled else { return }

        let current = state.connectionState

        // Fire once on the rising edge of the stall/needs-reference flag.
        if state.needsReference, !previousNeedsReference {
            poster.postNeedsReference()
        }
        previousNeedsReference = state.needsReference

        defer { previous = current }

        switch (previous, current) {
        case (.disconnected, .connected), (.scanning, .connected), (.connecting, .connected):
            // Only notify on reconnect — not the very first successful connection.
            if hasEverConnected {
                poster.postConnected()
            }
            hasEverConnected = true

        case (_, .disconnected) where previous == .connected:
            // Unexpected disconnect — check the flag on the actor.
            let isUserInitiated = await manager.isUserInitiatedDisconnect
            if !isUserInitiated {
                poster.postDisconnected()
            }

        default:
            break
        }
    }
}
