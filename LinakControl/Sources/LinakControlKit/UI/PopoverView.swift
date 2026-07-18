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
            if viewModel.needsReference {
                NeedsReferenceBanner(message: viewModel.faultMessage)
            }
            HeightHeroView(viewModel: viewModel)
            MovementControlView(viewModel: viewModel)
            PresetGridView(viewModel: viewModel)
            FooterView(viewModel: viewModel)
        }
    }
}

// MARK: - NeedsReferenceBanner

/// Compact warning shown when a movement stalled — the desk stopped responding.
/// The message is specific to the decoded fault code when the desk pushed one
/// (E16 = needs reset, E26 = possible leg/cable fault), else generic.
private struct NeedsReferenceBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}

// MARK: - DisconnectedContent

private struct DisconnectedContent: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.needsReference ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(viewModel.needsReference ? .orange : .secondary)

            Text(stateTitle)
                .font(.headline)

            Text(stateSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.connectionState == .disconnected {
                Button(viewModel.needsReference ? "Reconnect" : "Retry") { viewModel.retryConnection() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            MovementControlView(viewModel: viewModel)
            PresetGridView(viewModel: viewModel)
            FooterView(viewModel: viewModel)
        }
    }

    private var stateTitle: String {
        if viewModel.needsReference { return "Desk Paused" }
        switch viewModel.connectionState {
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        default: return "Disconnected"
        }
    }

    private var stateSubtitle: String {
        // After a fault the app stands down so the desk can be initialised on the
        // control box; tell the user what happened and how to resume.
        if viewModel.needsReference {
            return "\(viewModel.faultMessage) Initialise it on the control box, then Reconnect or move the desk."
        }
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
            if viewModel.connectionState == .connected {
                Button {
                    viewModel.disconnectFromDesk()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Disconnect from the desk")
                .accessibilityIdentifier("linak.popover.disconnect")
            }
            Spacer()
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .accessibilityIdentifier("linak.popover.settings.gear")
        }
        .padding(.top, 4)
    }
}
