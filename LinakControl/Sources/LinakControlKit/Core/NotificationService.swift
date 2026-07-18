// NotificationService.swift
// LinakControlKit — Posts macOS User Notifications for desk connection state changes.

import UserNotifications

// MARK: - NotificationPosting

/// Abstracts UNUserNotificationCenter for testability.
public protocol NotificationPosting: Sendable {
    func requestPermission()
    func postDisconnected()
    func postConnected()
    func postNeedsReference()
}

// MARK: - NotificationService

/// Sends macOS User Notifications when the desk connects or unexpectedly disconnects.
public final class NotificationService: NotificationPosting {

    public init() {}

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func postDisconnected() {
        let content = UNMutableNotificationContent()
        content.title = "Desk Disconnected"
        content.body = "Reconnecting..."
        let request = UNNotificationRequest(
            identifier: "desk-disconnected",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func postConnected() {
        let content = UNMutableNotificationContent()
        content.title = "Desk Connected"
        let request = UNNotificationRequest(
            identifier: "desk-connected",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func postNeedsReference() {
        let content = UNMutableNotificationContent()
        content.title = "Desk Not Moving"
        content.body = "The desk stopped responding. It may need a manual reset on the control box."
        let request = UNNotificationRequest(
            identifier: "desk-needs-reference",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
