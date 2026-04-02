// PopoverView.swift
// LinakControlKit — Root SwiftUI view hosted in the Zone 1 NSPopover.

import SwiftUI

// MARK: - PopoverView

/// Root view for the Zone 1 NSPopover (280 pt wide, ~400 pt tall).
///
/// Renders different content depending on `viewModel.connectionState`:
/// - `.connected`: hero height + controls + presets
/// - `.disconnected` / `.scanning` / `.connecting`: disconnected state with retry button
public struct PopoverView: View {

    @ObservedObject public var viewModel: DeskViewModel

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if viewModel.isFirstRun {
            FirstRunView(viewModel: viewModel)
        } else if viewModel.showSettings {
            SettingsView(viewModel: viewModel)
        } else {
            VStack(spacing: 0) {
                switch viewModel.connectionState {
                case .connected:
                    ConnectedContent(viewModel: viewModel)
                case .disconnected, .scanning, .connecting:
                    DisconnectedContent(viewModel: viewModel)
                }
            }
            .frame(width: 280)
            .padding()
        }
    }
}

// MARK: - ConnectedContent

private struct ConnectedContent: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 16) {
            if let name = viewModel.deskName {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HeightHeroView(viewModel: viewModel)
            MovementControlView(viewModel: viewModel)
            PresetGridView(viewModel: viewModel)
            FooterView(viewModel: viewModel)
        }
    }
}

// MARK: - DisconnectedContent

private struct DisconnectedContent: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(stateTitle)
                .font(.headline)

            Text(stateSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if viewModel.connectionState == .disconnected {
                Button("Retry") { viewModel.retryConnection() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            MovementControlView(viewModel: viewModel)
            PresetGridView(viewModel: viewModel)
            FooterView(viewModel: viewModel)
        }
    }

    private var stateTitle: String {
        switch viewModel.connectionState {
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        default: return "Disconnected"
        }
    }

    private var stateSubtitle: String {
        switch viewModel.connectionState {
        case .scanning, .connecting: return "Looking for your desk"
        default: return "Reconnecting..."
        }
    }
}

// MARK: - HeightHeroView

private struct HeightHeroView: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if viewModel.isMoving, let direction = viewModel.moveDirection {
                    Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                Text(viewModel.heightDisplay)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - FooterView

private struct FooterView: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        HStack {
            Spacer()
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
}
