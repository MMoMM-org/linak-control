// MenuBarController.swift
// LinakControlKit — Two-zone NSStatusItem controller per ADR-6.

import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarController

/// Owns the two NSStatusItems in the macOS menu bar.
///
/// Zone 1: desk icon that toggles an NSPopover containing `PopoverView`.
/// Zone 2: preset + height text that shows an `NSMenu` with four preset items.
///
/// Observes `DeskViewModel` to update both zones reactively.
@MainActor
public final class MenuBarController: NSObject {

    // MARK: - Private state

    private var zone1StatusItem: NSStatusItem?
    private var zone2StatusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: DeskViewModel
    private var cancellable: AnyCancellable?

    // MARK: - Init

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    // MARK: - Public API

    /// Creates both NSStatusItems and connects them to the view model.
    ///
    /// When `autoOpen` is true the popover opens immediately after setup,
    /// which is useful for first-run pairing so the user sees the scanning UI
    /// without having to find and click the (dimmed) menu-bar icon first.
    public func setup(autoOpen: Bool = false) {
        FileLog.debug("setup(autoOpen: \(autoOpen)) isFirstRun=\(viewModel.isFirstRun)", category: "ui")
        setupZone1()
        if viewModel.showZone2 { setupZone2() }
        startObservingViewModel()

        if autoOpen {
            // Slight delay so the status item is laid out in the menu bar first.
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
        }
    }

    // MARK: - Zone 1: desk icon → popover

    private func setupZone1() {
        FileLog.debug("setupZone1: creating square-length status item", category: "ui")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = zone1Image(for: viewModel.connectionState)
        item.button?.image?.isTemplate = true
        item.button?.alphaValue = viewModel.connectionState == .connected ? 1.0 : 0.7
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        zone1StatusItem = item

        let hosting = NSPopover()
        hosting.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: viewModel)
        )
        hosting.contentSize = NSSize(width: 280, height: 400)
        // During first-run the popover must stay open so the user can complete
        // the pairing flow without it dismissing on focus loss.
        hosting.behavior = viewModel.isFirstRun ? .applicationDefined : .transient
        popover = hosting
    }

    @objc private func togglePopover() {
        guard let button = zone1StatusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover's window key so clicks register immediately
            // without needing an extra activation click first.
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Zone 2: preset text → dropdown menu

    private func setupZone2() {
        FileLog.debug("setupZone2: creating variable-length status item", category: "ui")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = zone2Title()
        item.button?.action = #selector(showPresetMenu)
        item.button?.target = self
        zone2StatusItem = item
    }

    @objc private func showPresetMenu() {
        let menu = buildPresetMenu()
        zone2StatusItem?.menu = menu
        zone2StatusItem?.button?.performClick(nil)
        zone2StatusItem?.menu = nil
    }

    // MARK: - View model observation

    private func startObservingViewModel() {
        // objectWillChange fires before the mutation, so we schedule the
        // refresh on the next main-queue cycle to read updated values.
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refreshZones()
            }
        }
    }

    private func refreshZones() {
        updateZone1Icon()
        updateZone2Visibility()
        updateZone2Title()
        updatePopoverBehavior()
    }

    private func updateZone1Icon() {
        zone1StatusItem?.button?.image = zone1Image(for: viewModel.connectionState)
        zone1StatusItem?.button?.alphaValue = viewModel.connectionState == .connected ? 1.0 : 0.7
    }

    private func updateZone2Visibility() {
        let shouldShow = viewModel.showZone2
        let isShown = zone2StatusItem != nil
        if shouldShow && !isShown {
            setupZone2()
        } else if !shouldShow && isShown {
            teardownZone2()
        }
    }

    private func teardownZone2() {
        if let item = zone2StatusItem {
            NSStatusBar.system.removeStatusItem(item)
            zone2StatusItem = nil
        }
    }

    private func updateZone2Title() {
        zone2StatusItem?.button?.title = zone2Title()
    }

    private func updatePopoverBehavior() {
        // Switch from applicationDefined → transient once first-run completes
        // so the popover dismisses normally on focus loss.
        if !viewModel.isFirstRun, popover?.behavior == .applicationDefined {
            popover?.behavior = .transient
        }
    }

    // MARK: - Helpers

    private func zone1Image(for state: ConnectionState) -> NSImage? {
        // "table.furniture" is available on macOS 13+ and resembles a desk.
        let name = "table.furniture"
        return NSImage(systemSymbolName: name, accessibilityDescription: "Desk")
    }

    private func zone2Title() -> String {
        switch viewModel.connectionState {
        case .connected:
            let heightText = viewModel.heightDisplay
            if let active = viewModel.activePreset {
                return "\(active)  \(heightText)"
            }
            return heightText
        case .connecting:
            return "Connecting…"
        case .scanning:
            return "Scanning…"
        case .disconnected:
            return "Not Connected"
        }
    }

    private func buildPresetMenu() -> NSMenu {
        let menu = NSMenu()
        for preset in viewModel.presets {
            menu.addItem(presetMenuItem(for: preset))
        }
        return menu
    }

    private func presetMenuItem(for preset: PresetPosition) -> NSMenuItem {
        let heightText = preset.heightMM.map { HeightConverter.display(mm: $0, unit: viewModel.unit) } ?? "—"
        let prefix = (preset.index == viewModel.targetPreset) ? "→ " : ""
        let title = "\(prefix)\(preset.index)  \(heightText)"

        let item = NSMenuItem(title: title, action: #selector(presetMenuItemSelected(_:)), keyEquivalent: "")
        item.tag = preset.index
        item.target = self
        item.state = (preset.index == viewModel.activePreset) ? .on : .off
        return item
    }

    @objc private func presetMenuItemSelected(_ sender: NSMenuItem) {
        viewModel.goToPreset(index: sender.tag)
    }
}
