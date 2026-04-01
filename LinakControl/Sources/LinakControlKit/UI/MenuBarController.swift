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
    public func setup() {
        setupZone1()
        setupZone2()
        startObservingViewModel()
    }

    // MARK: - Zone 1: desk icon → popover

    private func setupZone1() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = zone1Image(for: viewModel.connectionState)
        item.button?.image?.isTemplate = true
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        zone1StatusItem = item

        let hosting = NSPopover()
        hosting.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: viewModel)
        )
        hosting.contentSize = NSSize(width: 280, height: 400)
        hosting.behavior = .transient
        popover = hosting
    }

    @objc private func togglePopover() {
        guard let button = zone1StatusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Zone 2: preset text → dropdown menu

    private func setupZone2() {
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
        updateZone2Title()
    }

    private func updateZone1Icon() {
        zone1StatusItem?.button?.image = zone1Image(for: viewModel.connectionState)
        zone1StatusItem?.button?.alphaValue = viewModel.connectionState == .disconnected ? 0.4 : 1.0
    }

    private func updateZone2Title() {
        zone2StatusItem?.button?.title = zone2Title()
    }

    // MARK: - Helpers

    private func zone1Image(for state: ConnectionState) -> NSImage? {
        let name = "rectangle.split.3x1"
        return NSImage(systemSymbolName: name, accessibilityDescription: "Desk")
    }

    private func zone2Title() -> String {
        guard viewModel.connectionState == .connected else { return "—" }
        let heightText = viewModel.heightDisplay
        if let active = viewModel.activePreset {
            return "\(active)  \(heightText)"
        }
        return heightText
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
