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
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("debug.log")
    }()

    /// Persistent file handle — opened once, reused for all writes.
    /// Avoids file-descriptor churn at ~10Hz during desk movement.
    private static var fileHandle: FileHandle?

    /// Write a single log line. No-op in release builds.
    public static func debug(_ message: @autoclosure () -> String, category: String = "general") {
        #if DEBUG
        let text = message()
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [\(category)] \(text)\n"

        queue.async {
            guard let url = logURL else { return }
            let handle = openHandleIfNeeded(url: url)
            guard let handle else { return }
            let size = handle.seekToEndOfFile()
            if size > maxBytes {
                handle.truncateFile(atOffset: 0)
                handle.seek(toFileOffset: 0)
            }
            handle.write(Data(line.utf8))
        }
        #endif
    }

    /// Truncates the log file. Call at app launch for a clean session.
    public static func reset() {
        #if DEBUG
        queue.async {
            guard let url = logURL else { return }
            fileHandle?.closeFile()
            fileHandle = nil
            try? Data().write(to: url, options: .atomic)
        }
        #endif
    }

    /// Opens or returns the existing persistent file handle.
    /// Creates the file with 0600 permissions if it doesn't exist.
    private static func openHandleIfNeeded(url: URL) -> FileHandle? {
        if let handle = fileHandle { return handle }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path, contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        return fileHandle
    }
}
