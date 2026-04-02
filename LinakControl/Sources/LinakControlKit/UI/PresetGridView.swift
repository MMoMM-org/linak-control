// PresetGridView.swift
// LinakControlKit — 2x2 grid of preset buttons in the popover.

import SwiftUI

// MARK: - PresetGridView

/// A two-column grid showing all four preset slots.
///
/// Each cell displays the preset index and its stored height.
/// The active preset is highlighted with an accent border.
/// The target preset pulses during movement.
/// Tapping an unset preset is a no-op (the button is disabled).
public struct PresetGridView: View {

    @ObservedObject public var viewModel: DeskViewModel

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(viewModel.presets, id: \.index) { preset in
                PresetCell(
                    preset: preset,
                    isActive: preset.index == viewModel.activePreset,
                    isTarget: preset.index == viewModel.targetPreset,
                    unit: viewModel.unit,
                    isConnected: viewModel.connectionState == .connected,
                    onTap: { viewModel.goToPreset(index: preset.index) }
                )
            }
        }
    }
}

// MARK: - PresetCell

private struct PresetCell: View {

    let preset: PresetPosition
    let isActive: Bool
    let isTarget: Bool
    let unit: HeightUnit
    let isConnected: Bool
    let onTap: () -> Void

    @State private var isPulsing: Bool = false

    private var heightText: String {
        preset.heightMM.map { HeightConverter.display(mm: $0, unit: unit) } ?? "—"
    }

    private var hasHeight: Bool { preset.heightMM != nil }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(preset.index)")
                .font(.headline)
            Text(heightText)
                .font(.caption)
                .foregroundColor(.secondary)
            if isTarget {
                Text("Moving...")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isPulsing ? 0.96 : 1.0)
        .opacity(cellOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isConnected, hasHeight else { return }
            onTap()
        }
        .onChange(of: isTarget) { newValue in
            withAnimation(newValue ? pulseAnimation : .default) {
                isPulsing = newValue
            }
        }
    }

    private var cellOpacity: Double {
        if !isConnected { return 0.4 }
        if !hasHeight { return 0.4 }
        return 1.0
    }

    private var cellBackground: Color {
        if isActive { return Color.accentColor.opacity(0.15) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var pulseAnimation: Animation {
        Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    }
}
