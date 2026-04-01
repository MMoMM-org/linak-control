// FirstRunView.swift
// LinakControlKit — First-run onboarding flow: welcome → scanning → selecting.

import SwiftUI

// MARK: - FirstRunView

/// Onboarding view shown when no desk has been paired yet.
///
/// States progress from welcome → scanning, driven by `DeskViewModel.isFirstRun`
/// and `DeskViewModel.discoveredDesks`.
public struct FirstRunView: View {

    @ObservedObject public var viewModel: DeskViewModel

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.connectionState == .connected {
                FirstRunCompleteView(viewModel: viewModel)
            } else if viewModel.connectionState == .connecting {
                FirstRunConnectingView(viewModel: viewModel)
            } else if viewModel.connectionState == .scanning || !viewModel.discoveredDesks.isEmpty {
                FirstRunScanningView(viewModel: viewModel)
            } else {
                FirstRunWelcomeView(viewModel: viewModel)
            }
        }
        .frame(width: 280)
        .padding()
    }
}

// MARK: - FirstRunWelcomeView

/// Welcome screen shown before scanning begins.
struct FirstRunWelcomeView: View {

    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "rectangle.and.hand.point.up.left")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("LinakControl")
                    .font(.title2.weight(.semibold))

                Text("Control your LINAK desk from the menu bar.\nWe'll scan for your desk and pair it now.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Get Started") {
                viewModel.startScan()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }
}

// MARK: - FirstRunScanningView

/// Scanning screen showing spinner and list of discovered desks.
struct FirstRunScanningView: View {

    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 0) {
            scanningHeader
                .padding(.bottom, 12)

            if viewModel.discoveredDesks.isEmpty {
                Spacer()
                Text("Searching for desks nearby…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                deskList
                Divider()
                    .padding(.vertical, 8)
                Text("Tap a desk to connect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scanningHeader: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning for desks…")
                .font(.headline)
        }
    }

    private var deskList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.discoveredDesks, id: \.peripheralId) { desk in
                DeskRowView(desk: desk) {
                    viewModel.selectDesk(desk)
                }
                Divider()
            }
        }
    }
}

// MARK: - FirstRunConnectingView

/// Shown while the BLE connection and handshake are in progress.
struct FirstRunConnectingView: View {

    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Connecting to \(viewModel.selectedDeskName ?? "desk")…")
                .font(.headline)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }
}

// MARK: - FirstRunCompleteView

/// Shown after a successful connection. Lets the user confirm and dismiss first-run.
struct FirstRunCompleteView: View {

    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(spacing: 6) {
                Text("Connected!")
                    .font(.title2.weight(.semibold))

                Text(viewModel.deskName ?? "Your desk")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Current height: \(viewModel.heightDisplay)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Tip: Save your current position as a preset in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button("Done") {
                viewModel.completeFirstRun()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }
}

// MARK: - DeskRowView

/// Single row showing a discovered desk's name and RSSI signal bars.
private struct DeskRowView: View {

    let desk: DiscoveredDesk
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                SignalBarsView(rssi: desk.rssi)
                    .frame(width: 24)

                Text(desk.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SignalBarsView

/// Renders 1–4 signal strength bars based on RSSI value.
///
/// RSSI mapping: -30…-49 → 4 bars, -50…-64 → 3 bars, -65…-79 → 2 bars, -80…-90 → 1 bar.
private struct SignalBarsView: View {

    let rssi: Int

    private var activeBars: Int {
        switch rssi {
        case (-49)...: return 4
        case (-64)...: return 3
        case (-79)...: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 4, height: CGFloat(bar * 4))
                    .foregroundColor(bar <= activeBars ? .accentColor : Color.secondary.opacity(0.3))
            }
        }
    }
}
