// ConfigStore.swift
// LinakControlKit

import Foundation

// MARK: - ConfigStore

/// Reads and writes `AppConfig` as `config.json`.
///
/// Default storage location: `~/Library/Application Support/LinakControl/`
/// The directory is created on first save with mode 0o700;
/// the file is written with mode 0o600.
public final class ConfigStore {

    // MARK: Properties

    private let directoryURL: URL
    private let fileURL: URL

    // MARK: Init

    /// Create a store targeting the given directory.
    ///
    /// - Parameter directoryURL: Directory that will contain `config.json`.
    ///   Pass `nil` to use `~/Library/Application Support/LinakControl/`.
    public init(directoryURL: URL? = nil) {
        let resolved = directoryURL ?? Self.defaultDirectoryURL()
        self.directoryURL = resolved
        self.fileURL = resolved.appendingPathComponent("config.json")
    }

    // MARK: Public API

    /// Load persisted settings from disk.
    ///
    /// Returns `AppConfig.default` when no config file exists yet.
    /// Throws on JSON decoding errors or unreadable files.
    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: fileURL)
        return try makeDecoder().decode(AppConfig.self, from: data)
    }

    /// Persist settings to disk.
    ///
    /// Creates the directory (mode 0o700) and file (mode 0o600) if needed.
    /// Throws on encoding errors or file-system failures.
    public func save(_ config: AppConfig) throws {
        try createDirectoryIfNeeded()
        let data = try makeEncoder().encode(config)
        try writeFile(data: data)
    }

    // MARK: Private helpers

    private func createDirectoryIfNeeded() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directoryURL.path) else { return }
        try fm.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func writeFile(data: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } else {
            fm.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func defaultDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("LinakControl")
    }
}
