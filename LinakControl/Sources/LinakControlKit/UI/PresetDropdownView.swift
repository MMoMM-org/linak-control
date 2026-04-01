// PresetDropdownView.swift
// LinakControlKit — NSMenu factory for the Zone 2 preset dropdown.

import AppKit

// MARK: - PresetDropdownView

/// Builds and returns an `NSMenu` representing the four preset slots.
///
/// This is a stateless factory, not a view class. `MenuBarController` calls
/// `build(from:)` each time the Zone 2 button is clicked so the menu always
/// reflects the latest view model state.
public enum PresetDropdownView {

    // MARK: - Public API

    /// Build a fresh `NSMenu` from the current view model state.
    ///
    /// - Parameter viewModel: Source of preset and connection state.
    /// - Returns: A configured `NSMenu` ready to display.
    public static func build(from viewModel: DeskViewModel, target: AnyObject?, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for preset in viewModel.presets {
            menu.addItem(item(for: preset, viewModel: viewModel, target: target, action: action))
        }
        return menu
    }

    // MARK: - Private

    private static func item(
        for preset: PresetPosition,
        viewModel: DeskViewModel,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let heightText = preset.heightMM
            .map { HeightConverter.display(mm: $0, unit: viewModel.unit) } ?? "—"
        let isTarget = preset.index == viewModel.targetPreset
        let prefix = isTarget ? "→ " : ""
        let title = "\(prefix)\(preset.index)  \(heightText)"

        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = preset.index
        item.target = target
        item.state = (preset.index == viewModel.activePreset) ? .on : .off
        return item
    }
}
