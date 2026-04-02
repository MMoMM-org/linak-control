// Logger.swift
// LinakControlKit -- Unified + file logging for debug builds.

import Foundation
import os

// MARK: - Category loggers (unified logging)

public enum Log {
    public static let ble  = os.Logger(subsystem: "com.linakcontrol", category: "ble")
    public static let ipc  = os.Logger(subsystem: "com.linakcontrol", category: "ipc")
    public static let core = os.Logger(subsystem: "com.linakcontrol", category: "core")
    public static let ui   = os.Logger(subsystem: "com.linakcontrol", category: "ui")
}

// MARK: - File logger for debug builds

/// Appends timestamped lines to ~/Library/Logs/LinakControl/debug.log.
///
/// All writes are serialised on a dedicated queue. The log file is
/// created automatically on first write and truncated at 1 MB to
/// prevent unbounded growth across debug sessions.
public enum FileLog {

    private static let queue = DispatchQueue(label: "com.linakcontrol.filelog")
    private static let maxBytes = 1_000_000
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var logURL: URL? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LinakControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    /// Write a single log line. No-op in release builds.
    public static func debug(_ message: @autoclosure () -> String, category: String = "general") {
        #if DEBUG
        let text = message()
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [\(category)] \(text)\n"

        queue.async {
            guard let url = logURL else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                // Truncate if over limit
                let size = handle.seekToEndOfFile()
                if size > maxBytes {
                    handle.truncateFile(atOffset: 0)
                    handle.seek(toFileOffset: 0)
                }
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
        #endif
    }

    /// Truncates the log file. Call at app launch for a clean session.
    public static func reset() {
        #if DEBUG
        queue.async {
            guard let url = logURL else { return }
            try? Data().write(to: url, options: .atomic)
        }
        #endif
    }
}
