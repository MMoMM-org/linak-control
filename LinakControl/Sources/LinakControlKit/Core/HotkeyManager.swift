// HotkeyManager.swift
// LinakControlKit — Global keyboard shortcut registration for desk control.
//
// Ctrl+Opt+1-4 activates presets; Ctrl+Opt+Up/Down moves the desk.
// Requires Accessibility permission (System Settings > Privacy > Accessibility).

import AppKit

// MARK: - Protocol

/// Manages global keyboard shortcuts for desk control.
public protocol HotkeyManaging {
    func enable()
    func disable()
    var isEnabled: Bool { get }
}

// MARK: - Production Implementation

/// Registers Ctrl+Opt+1-4 for preset activation and Ctrl+Opt+Up/Down for movement.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` which fires even when the app is in the background.
/// The monitor runs on the main thread. Requires Accessibility permission.
@MainActor
public final class HotkeyManager: HotkeyManaging {

    // MARK: - Key Codes

    private enum KeyCode {
        static let one: UInt16   = 18
        static let two: UInt16   = 19
        static let three: UInt16 = 20
        static let four: UInt16  = 21
        static let upArrow: UInt16   = 126
        static let downArrow: UInt16 = 125
    }

    // MARK: - Dependencies

    private let deskManager: DeskManager
    private let configStore: ConfigStore

    // MARK: - State

    private var monitor: Any?

    public var isEnabled: Bool { monitor != nil }

    // MARK: - Init

    public init(deskManager: DeskManager, configStore: ConfigStore) {
        self.deskManager = deskManager
        self.configStore = configStore
    }

    // MARK: - HotkeyManaging

    public func enable() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    public func disable() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        let required: NSEvent.ModifierFlags = [.control, .option]
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard actual == required else { return }

        switch event.keyCode {
        case KeyCode.one:       triggerPreset(index: 1)
        case KeyCode.two:       triggerPreset(index: 2)
        case KeyCode.three:     triggerPreset(index: 3)
        case KeyCode.four:      triggerPreset(index: 4)
        case KeyCode.upArrow:   triggerMoveUp()
        case KeyCode.downArrow: triggerMoveDown()
        default: break
        }
    }

    private func triggerPreset(index: Int) {
        Task { try? await deskManager.goToPreset(index: index) }
    }

    private func triggerMoveUp() {
        let mode = resolvedRunMode(\.autoRunUp)
        Task { try? await deskManager.moveUp(mode: mode) }
    }

    private func triggerMoveDown() {
        let mode = resolvedRunMode(\.autoRunDown)
        Task { try? await deskManager.moveDown(mode: mode) }
    }

    private func resolvedRunMode(_ keyPath: KeyPath<AppConfig, RunMode>) -> RunMode {
        (try? configStore.load())?[keyPath: keyPath] ?? .manual
    }
}
