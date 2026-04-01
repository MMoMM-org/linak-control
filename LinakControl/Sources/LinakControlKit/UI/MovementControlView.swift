// MovementControlView.swift
// LinakControlKit — Up / Down movement buttons with hold and auto-run modes.

import SwiftUI

// MARK: - MovementControlView

/// Up and Down buttons adapting to `DeskViewModel.autoRunUp/Down`.
///
/// Manual mode: hold 150 ms to start, release to stop. Shows "(hold)".
/// Auto mode: single tap to start; transforms to Stop during movement. Shows "(auto)".
/// Both buttons are disabled when disconnected.
public struct MovementControlView: View {

    @ObservedObject public var viewModel: DeskViewModel

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
    }

    private var isConnected: Bool { viewModel.connectionState == .connected }

    public var body: some View {
        HStack(spacing: 16) {
            MovementButton(
                direction: .up,
                viewModel: viewModel,
                isConnected: isConnected
            )
            MovementButton(
                direction: .down,
                viewModel: viewModel,
                isConnected: isConnected
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MovementButton

private struct MovementButton: View {

    let direction: MoveDirection
    @ObservedObject var viewModel: DeskViewModel
    let isConnected: Bool

    // Tracks whether we have started a manual hold.
    @State private var isHolding: Bool = false

    private var mode: RunMode {
        direction == .up ? viewModel.autoRunUp : viewModel.autoRunDown
    }

    private var isMovingThisDirection: Bool {
        viewModel.isMoving && viewModel.moveDirection == direction
    }

    private var isOppositeMoving: Bool {
        viewModel.isMoving && viewModel.moveDirection != direction
    }

    private var isAutoAndMoving: Bool {
        mode == .auto && viewModel.isMoving
    }

    private var label: String {
        if isAutoAndMoving { return "Stop" }
        return direction == .up ? "▲" : "▼"
    }

    private var modeLabel: String {
        mode == .auto ? "(auto)" : "(hold)"
    }

    var body: some View {
        VStack(spacing: 4) {
            if mode == .auto {
                autoButton
            } else {
                manualButton
            }
            Text(modeLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .opacity(buttonOpacity)
    }

    private var buttonOpacity: Double {
        if !isConnected { return 0.35 }
        if isOppositeMoving { return 0.35 }
        return 1.0
    }

    // MARK: Auto mode button

    private var autoButton: some View {
        Button(label) {
            if viewModel.isMoving {
                viewModel.stop()
            } else {
                triggerMove()
            }
        }
        .buttonStyle(.bordered)
        .disabled(!isConnected)
        .frame(minWidth: 64)
    }

    // MARK: Manual mode button

    private var manualButton: some View {
        Button(label) {}
            .buttonStyle(.bordered)
            .frame(minWidth: 64)
            .disabled(!isConnected)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isConnected, !isHolding else { return }
                        isHolding = true
                        triggerMove()
                    }
                    .onEnded { _ in
                        guard isHolding else { return }
                        isHolding = false
                        viewModel.stop()
                    }
            )
    }

    // MARK: Shared

    private func triggerMove() {
        if direction == .up {
            viewModel.moveUp()
        } else {
            viewModel.moveDown()
        }
    }
}
