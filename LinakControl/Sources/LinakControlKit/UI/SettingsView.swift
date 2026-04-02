// SettingsView.swift
// LinakControlKit — Settings panel pushed within the popover.
//
// Renders inside the popover when `DeskViewModel.showSettings` is true.
// Sections: display unit, movement mode, presets, connection, system, about.

import SwiftUI

// MARK: - SettingsView

/// Full settings panel displayed inside the Zone 1 popover.
///
/// Navigation is simulated: a Back button sets `viewModel.showSettings = false`,
/// returning to the normal popover content.
public struct SettingsView: View {

    @ObservedObject public var viewModel: DeskViewModel

    public init(viewModel: DeskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderView(viewModel: viewModel)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DisplayUnitSection(viewModel: viewModel)
                    SettingsDivider()
                    DeskOffsetSection(viewModel: viewModel)
                    SettingsDivider()
                    MovementModeSection(viewModel: viewModel)
                    SettingsDivider()
                    PresetsSection(viewModel: viewModel)
                    SettingsDivider()
                    ConnectionSection(viewModel: viewModel)
                    SettingsDivider()
                    SystemSection(viewModel: viewModel)
                    SettingsDivider()
                    AboutSection()
                }
                .padding()
            }
        }
        .frame(width: 280)
    }
}

// MARK: - SettingsHeaderView

private struct SettingsHeaderView: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        HStack {
            Button {
                viewModel.showSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Text("Settings")
                .font(.headline)

            Spacer()

            // Invisible spacer to balance the Back button and center the title
            Text("Back")
                .opacity(0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - SettingsDivider

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

// MARK: - SectionHeader

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }
}

// MARK: - DisplayUnitSection

private struct DisplayUnitSection: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Display Unit")

            Picker("Unit", selection: Binding(
                get: { viewModel.unit },
                set: { viewModel.updateUnit($0) }
            )) {
                Text("cm").tag(HeightUnit.cm)
                Text("inch").tag(HeightUnit.inch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - DeskOffsetSection

private struct DeskOffsetSection: View {
    @ObservedObject var viewModel: DeskViewModel
    @State private var offsetText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Desk Offset")

            HStack {
                Text("Offset:")
                    .foregroundColor(.secondary)
                TextField("cm", text: $offsetText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onAppear { offsetText = formatCM(viewModel.deskOffsetMM) }
                    .onSubmit { applyOffset() }
                    .onChange(of: viewModel.deskOffsetMM) { _ in
                        offsetText = formatCM(viewModel.deskOffsetMM)
                    }
                Text("cm")
                    .foregroundColor(.secondary)
            }

            Text("Height at lowest desk position")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formatCM(_ mm: Int) -> String {
        let cm = Double(mm) / 10.0
        let fractional = cm.truncatingRemainder(dividingBy: 1)
        if abs(fractional) < 0.05 {
            return "\(Int(cm.rounded()))"
        }
        return String(format: "%.1f", cm)
    }

    private func applyOffset() {
        let cleaned = offsetText.replacingOccurrences(of: ",", with: ".")
        guard let cm = Double(cleaned) else { return }
        let mm = Int((cm * 10).rounded())
        let clamped = max(0, min(mm, 15000))
        viewModel.updateDeskOffset(clamped)
    }
}

// MARK: - MovementModeSection

private struct MovementModeSection: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Movement Mode")

            HStack {
                Text("Up:")
                    .frame(width: 36, alignment: .leading)
                Picker("Up mode", selection: Binding(
                    get: { viewModel.autoRunUp },
                    set: { viewModel.updateAutoRunUp($0) }
                )) {
                    Text("hold").tag(RunMode.manual)
                    Text("auto").tag(RunMode.auto)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("Down:")
                    .frame(width: 36, alignment: .leading)
                Picker("Down mode", selection: Binding(
                    get: { viewModel.autoRunDown },
                    set: { viewModel.updateAutoRunDown($0) }
                )) {
                    Text("hold").tag(RunMode.manual)
                    Text("auto").tag(RunMode.auto)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

// MARK: - PresetsSection

private struct PresetsSection: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Presets")

            ForEach(viewModel.presets, id: \.index) { preset in
                PresetRowView(preset: preset) {
                    viewModel.savePreset(index: preset.index)
                }
            }
        }
    }
}

// MARK: - PresetRowView

private struct PresetRowView: View {
    let preset: PresetPosition
    let onSave: () -> Void

    var body: some View {
        HStack {
            Text("\(preset.index):")
                .frame(width: 16, alignment: .leading)

            if let heightMM = preset.heightMM {
                Text(HeightConverter.display(mm: heightMM, unit: .cm))
                    .font(.body)
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Save current", action: onSave)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - ConnectionSection

private struct ConnectionSection: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Connection")

            HStack {
                Text("Desk:")
                    .foregroundColor(.secondary)
                Text(viewModel.deskName ?? "Unknown")
                    .lineLimit(1)
                Spacer()
                if viewModel.connectionState == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            Button("Forget & Re-scan") {
                viewModel.forgetAndRescan()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }
}

// MARK: - SystemSection

private struct SystemSection: View {
    @ObservedObject var viewModel: DeskViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Start at login", isOn: Binding(
                get: { viewModel.startAtLogin },
                set: { viewModel.updateStartAtLogin($0) }
            ))

            Toggle("Global hotkeys", isOn: Binding(
                get: { viewModel.hotkeysEnabled },
                set: { viewModel.updateHotkeysEnabled($0) }
            ))
        }
    }
}

// MARK: - AboutSection

private struct AboutSection: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About LinakControl v\(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
    }
}
