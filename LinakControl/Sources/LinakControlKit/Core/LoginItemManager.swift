// LoginItemManager.swift
// LinakControlKit — Manages "Start at login" registration via SMAppService.

import ServiceManagement

// MARK: - Protocol

/// Abstraction over SMAppService for testability.
public protocol LoginItemManaging {
    func register() throws
    func unregister() throws
}

// MARK: - Production Implementation

/// Registers and unregisters the main app as a login item using SMAppService.
///
/// macOS 13+ recommended API (ADR-5). No LaunchAgent plist required.
public final class LoginItemManager: LoginItemManaging {

    public init() {}

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
