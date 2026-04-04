// ConfigCommand.swift
// deskctl config <reset|show>

import ArgumentParser
import Foundation
import LinakControlKit

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage LinakControl configuration.",
        subcommands: [
            ConfigShowCommand.self,
            ConfigResetCommand.self,
        ]
    )
}

// MARK: - deskctl config show

struct ConfigShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the current configuration."
    )

    func run() throws {
        let store = ConfigStore()
        let config = try store.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}

// MARK: - deskctl config reset

struct ConfigResetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset configuration to defaults (clears pairing, offset, and all settings)."
    )

    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force: Bool = false

    func run() throws {
        if !force {
            print("This will reset all settings including pairing info.")
            print("The app will need to re-pair with the desk on next launch.")
            print("Continue? [y/N] ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Aborted.")
                return
            }
        }

        let store = ConfigStore()
        try store.save(.default)
        print("Configuration reset to defaults.")
    }
}
