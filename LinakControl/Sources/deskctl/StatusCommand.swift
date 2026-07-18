// StatusCommand.swift
// deskctl status [--json]

import ArgumentParser
import Foundation
import LinakControlKit

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show desk and daemon status."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() throws {
        let status = try runIPC(json: json) { try $0.getStatus() }
        if json {
            printJSON(status)
        } else {
            printTable(status)
        }
    }

    // MARK: - Formatters

    private func printTable(_ status: StatusResult) {
        let connectionLabel = status.connected ? "connected" : "disconnected"
        let deskLabel = status.deskName ?? "unknown"
        let heightLabel = status.heightDisplay.map { "\($0) \(status.unit)" } ?? "unknown"
        let presetsLabel = formatPresets(status.presets, active: status.activePreset, unit: status.unit)

        print("LinakControl Daemon")
        print("  Connection: \(connectionLabel)")
        print("  Desk:       \(deskLabel)")
        print("  Height:     \(heightLabel)")
        if !presetsLabel.isEmpty {
            print("  Presets:    \(presetsLabel)")
        }
        if status.needsReference {
            print("  Warning:    \(warningText(faultCode: status.faultCode))")
        }
    }

    private func warningText(faultCode: Int?) -> String {
        switch faultCode {
        case 0x1d: return "desk needs re-initialisation — hold DOWN until it reaches the bottom and resets (control box shows Initialise)"
        case 0x1e: return "desk needs a reset on the control box (E16, illegal key combination)"
        case 0x17: return "possible hardware fault in a desk leg — check the cables (E26, channel 4 missing)"
        default:   return "desk stopped moving — may need a manual reset on the control box"
        }
    }

    private func formatPresets(_ presets: [PresetInfo], active: Int?, unit: String) -> String {
        guard !presets.isEmpty else { return "" }
        return presets.map { preset in
            let height = preset.heightMM.map { String(format: "%.1f", Double($0) / 10) } ?? "?"
            let marker = (preset.index == active) ? "*" : ""
            let name = preset.label.map { " \($0)" } ?? ""
            return "\(preset.index)=\(height)\(unit)\(marker)\(name)"
        }.joined(separator: "  ")
    }

    private func printJSON(_ status: StatusResult) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(status),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
