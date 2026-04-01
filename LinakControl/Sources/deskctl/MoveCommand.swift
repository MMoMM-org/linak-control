// MoveCommand.swift
// deskctl up [--auto|--manual]
// deskctl down [--auto|--manual]
// deskctl stop

import ArgumentParser
import LinakControlKit

// MARK: - MoveOptions

/// Shared move mode options used by UpCommand and DownCommand.
struct MoveOptions: ParsableArguments {
    @Flag(name: .long, help: "Use automatic (continuous) movement mode.")
    var auto = false

    @Flag(name: .long, help: "Use manual movement mode.")
    var manual = false

    /// Resolved IPC mode string. Nil means let the daemon use its configured default.
    func resolvedMode() throws -> String? {
        if auto && manual {
            throw ValidationError("--auto and --manual are mutually exclusive.")
        }
        if auto { return "auto" }
        if manual { return "manual" }
        return nil
    }
}

// MARK: - UpCommand

struct UpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Move the desk up."
    )

    @OptionGroup var options: MoveOptions

    func run() throws {
        let mode = try options.resolvedMode()
        _ = try runIPC { try $0.move(direction: "up", mode: mode) }
        print("Moving up\(mode.map { " (\($0))" } ?? "").")
    }
}

// MARK: - DownCommand

struct DownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Move the desk down."
    )

    @OptionGroup var options: MoveOptions

    func run() throws {
        let mode = try options.resolvedMode()
        _ = try runIPC { try $0.move(direction: "down", mode: mode) }
        print("Moving down\(mode.map { " (\($0))" } ?? "").")
    }
}

// MARK: - StopCommand

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop desk movement."
    )

    func run() throws {
        _ = try runIPC { try $0.stop() }
        print("Stopped.")
    }
}
