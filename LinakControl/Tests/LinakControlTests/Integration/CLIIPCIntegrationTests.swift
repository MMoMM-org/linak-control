// CLIIPCIntegrationTests.swift
// LinakControlTests — End-to-end integration: IPCClient → IPCServer → DeskManager → MockBLEController.

import XCTest
import CoreBluetooth
@testable import LinakControlKit

// MARK: - Factories

/// Returns a unique socket path in the system temp directory.
private func makeTempSocketPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cli-ipc-int-\(UUID().uuidString).sock")
        .path
}

// makeTempConfigStore is provided by TestHelpers.swift

/// Builds a DeskManager with a MockBLEController that produces no handshake (disconnected).
private func makeDisconnectedManager(configStore: ConfigStore) -> DeskManager {
    DeskManager(bleController: MockBLEController(), configStore: configStore)
}

/// Builds a DeskManager connected via a happy-path MockBLEController.
///
/// Preset heights after connection:
/// - Preset 1: 730 mm
/// - Preset 2: 1105 mm
/// - Preset 3: 900 mm
/// - Preset 4: unset
private func makeConnectedManager(configStore: ConfigStore) async throws -> DeskManager {
    let mock = MockBLEController()
    mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
    mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
    mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { continuation in
        for response in HandshakeFixtures.happyPathDPGResponses {
            continuation.yield(response)
        }
        continuation.finish()
    }
    mock.mockNotificationStreams[DeskUUID.height] = AsyncStream { continuation in
        continuation.yield(HandshakeFixtures.heightNotification730mm)
        continuation.finish()
    }
    let manager = DeskManager(bleController: mock, configStore: configStore)
    try await manager.connect(peripheralId: UUID())
    return manager
}

/// Starts an IPCServer and waits until the socket accepts connections.
private func startServer(_ server: IPCServer, socketPath: String) async throws {
    try server.start()
    await waitForSocket(at: socketPath)
}

/// Polls the socket path until a connection succeeds or the timeout elapses.
private func waitForSocket(at socketPath: String, timeout: TimeInterval = 1.0) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { break }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { src in
                _ = Darwin.strlcpy(
                    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                    src, 104
                )
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(fd)
        if result == 0 { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - testStatusCommandReturnsCorrectJSON

/// Verifies that a status request sent via IPCClient returns a well-formed JSON response
/// reflecting the DeskManager's connection state and height when the desk is connected.
final class CLIStatusCommandIntegrationTests: XCTestCase {

    func testStatusCommandReturnsCorrectJSON() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = try await makeConnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        let status = try client.getStatus()

        XCTAssertTrue(status.connected, "Status must report desk as connected")
        XCTAssertNotNil(status.heightMM, "Status must include a height reading when connected")
        XCTAssertEqual(status.heightMM, 730, "Height must match the fixture value of 730 mm")
        XCTAssertNotNil(status.heightDisplay, "Status must include a display height string")
        XCTAssertFalse(status.unit.isEmpty, "Status must include a non-empty unit string")
        XCTAssertEqual(status.presets.count, 4, "Status must include all 4 preset slots")
    }

    func testStatusCommandWhenDisconnectedReportsNotConnected() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = makeDisconnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        let status = try client.getStatus()

        XCTAssertFalse(status.connected, "Status must report desk as disconnected")
        XCTAssertNil(status.heightMM, "Disconnected status must have no height")
        XCTAssertNil(status.heightDisplay, "Disconnected status must have no height display")
    }
}

// MARK: - testPresetCommandRoutesToDeskManager

/// Verifies that a goPreset command travels through IPCClient → IPCServer → DeskManager and
/// produces BLE writes on the MockBLEController.
final class CLIPresetCommandIntegrationTests: XCTestCase {

    func testPresetCommandRoutesToDeskManager() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()

        let mock = MockBLEController()
        mock.mockReadResponses[DeskUUID.outputMask] = HandshakeFixtures.validOutputMask
        mock.mockReadResponses[DeskUUID.height] = HandshakeFixtures.heightNotification730mm
        mock.mockNotificationStreams[DeskUUID.dpg] = AsyncStream { continuation in
            for response in HandshakeFixtures.happyPathDPGResponses {
                continuation.yield(response)
            }
            continuation.finish()
        }
        mock.mockNotificationStreams[DeskUUID.height] = AsyncStream { continuation in
            continuation.yield(HandshakeFixtures.heightNotification730mm)
            continuation.finish()
        }
        let manager = DeskManager(bleController: mock, configStore: configStore)
        try await manager.connect(peripheralId: UUID())

        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let writeCountBefore = mock.writtenData.count

        let client = IPCClient(socketPath: socketPath)
        _ = try client.goPreset(index: 2)

        // Allow async BLE writes to propagate.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(
            mock.writtenData.count, writeCountBefore,
            "goPreset must trigger at least one BLE write to the desk"
        )
    }

    func testPresetCommandReturnsTargetHeightFromPresetTable() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = try await makeConnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        let targetMM = try client.goPreset(index: 1)

        // Preset 1 is 730 mm from the happy-path fixture.
        XCTAssertEqual(targetMM, 730, "goPreset response must carry the preset's configured height")
    }
}

// MARK: - testHeightCommandReturnsValidJSON

/// Verifies that reading height via getStatus returns a well-formed response with the
/// required height_mm, height_display, and unit fields.
final class CLIHeightCommandIntegrationTests: XCTestCase {

    func testHeightCommandReturnsValidJSON() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = try await makeConnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        let status = try client.getStatus()

        XCTAssertNotNil(status.heightMM, "height_mm must be present when connected")
        XCTAssertNotNil(status.heightDisplay, "height_display must be present when connected")
        XCTAssertFalse(status.unit.isEmpty, "unit must be a non-empty string")

        // height_display must contain a numeric value and the unit label.
        if let display = status.heightDisplay {
            let hasDigit = display.contains(where: { $0.isNumber })
            XCTAssertTrue(hasDigit, "height_display '\(display)' must contain numeric digits")
        }
    }

    func testHeightUnitReflectsConfiguredUnit() async throws {
        let socketPath = makeTempSocketPath()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIIPCIntegrationTests-unit-\(UUID().uuidString)")
        let configStore = ConfigStore(directoryURL: tempDir)
        var config = AppConfig.default
        config.unit = .inch
        try configStore.save(config)

        let manager = try await makeConnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        let status = try client.getStatus()

        XCTAssertEqual(status.unit, "inch", "unit field must reflect the configured unit preference")
    }
}

// MARK: - testCommandWhenDisconnectedReturnsError

/// Verifies that control commands sent while the desk is disconnected produce a structured
/// error response with the notConnected error code.
final class CLIDisconnectedErrorIntegrationTests: XCTestCase {

    func testGoPresetWhenDisconnectedReturnsServerError() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = makeDisconnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        XCTAssertThrowsError(try client.goPreset(index: 1)) { error in
            guard case IPCClientError.serverError(let code, _) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(
                code, IPCErrorCode.notConnected.rawValue,
                "goPreset while disconnected must return notConnected error code"
            )
        }
    }

    func testMoveWhenDisconnectedReturnsServerError() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = makeDisconnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        XCTAssertThrowsError(try client.move(direction: "up", mode: nil)) { error in
            guard case IPCClientError.serverError(let code, _) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(
                code, IPCErrorCode.notConnected.rawValue,
                "move while disconnected must return notConnected error code"
            )
        }
    }

    func testStopWhenDisconnectedReturnsServerError() async throws {
        let socketPath = makeTempSocketPath()
        let configStore = makeTempConfigStore()
        let manager = makeDisconnectedManager(configStore: configStore)
        let server = IPCServer(deskManager: manager, configStore: configStore, socketPath: socketPath)
        try await startServer(server, socketPath: socketPath)
        defer { server.stop() }

        let client = IPCClient(socketPath: socketPath)
        XCTAssertThrowsError(try client.stop()) { error in
            guard case IPCClientError.serverError(let code, _) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(
                code, IPCErrorCode.notConnected.rawValue,
                "stop while disconnected must return notConnected error code"
            )
        }
    }

    func testClientCannotConnectWhenDaemonNotRunning() {
        let socketPath = makeTempSocketPath()
        let client = IPCClient(socketPath: socketPath)
        XCTAssertThrowsError(try client.getStatus()) { error in
            XCTAssertEqual(
                error as? IPCClientError, .daemonNotRunning,
                "Client must throw daemonNotRunning when no server is listening"
            )
        }
    }
}
