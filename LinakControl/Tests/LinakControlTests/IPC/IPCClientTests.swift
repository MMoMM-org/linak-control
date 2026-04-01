// IPCClientTests.swift
// LinakControlTests — Verifies IPCClient connection error mapping and server response handling.

import XCTest
import Darwin
@testable import LinakControlKit

// MARK: - Test Socket Server

/// Minimal Unix domain socket server that handles a single connection in the background.
/// Reads one framed request, calls the handler with the decoded request, writes the framed response, then closes.
private final class TestSocketServer {
    let socketPath: String
    private var serverFD: Int32 = -1
    private var thread: Thread?

    init() {
        socketPath = NSTemporaryDirectory() + "ipc-test-\(UUID().uuidString).sock"
    }

    /// Start listening. Blocks until the socket is bound and ready to accept connections.
    func start(handler: @escaping (IPCRequest) throws -> IPCResponse) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestServerError.socketFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { src in
                _ = Darwin.strlcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src, 104)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw TestServerError.bindFailed }
        guard listen(fd, 1) == 0 else { close(fd); throw TestServerError.listenFailed }
        serverFD = fd

        // Socket is bound and listening — safe for the client to connect now.
        let t = Thread {
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }

            guard let request = Self.readRequest(from: clientFD) else { return }
            do {
                let response = try handler(request)
                Self.writeResponse(response, to: clientFD)
            } catch {}
        }
        t.start()
        thread = t
    }

    func stop() {
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(socketPath)
    }

    // MARK: - Server I/O Helpers

    private static func readRequest(from fd: Int32) -> IPCRequest? {
        var buffer = Data()
        var chunk = Data(count: 4096)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress!, 4096) }
            if n <= 0 { break }
            buffer.append(chunk.prefix(n))
            if let (msg, _) = IPCFraming.deframe(buffer) {
                return try? JSONDecoder().decode(IPCRequest.self, from: msg)
            }
        }
        return nil
    }

    private static func writeResponse(_ response: IPCResponse, to fd: Int32) {
        guard let payload = try? JSONEncoder().encode(response) else { return }
        let framed = IPCFraming.frame(payload)
        _ = framed.withUnsafeBytes { write(fd, $0.baseAddress!, framed.count) }
    }
}

private enum TestServerError: Error {
    case socketFailed, bindFailed, listenFailed
}

// MARK: - Factories

private func makeStatusResult(
    connected: Bool = true,
    heightMM: Int? = 1105
) -> StatusResult {
    StatusResult(
        connected: connected,
        deskName: "LINAK Desk",
        heightMM: heightMM,
        heightDisplay: heightMM.map { String(format: "%.1f", Double($0) / 10) },
        unit: "cm",
        presets: [PresetInfo(index: 1, heightMM: 730, label: "Sit")],
        activePreset: nil
    )
}

private func makeStatusResponse(id: String, status: StatusResult) -> IPCResponse {
    IPCResponse(id: id, result: .status(status), error: nil)
}

private func makeOkResponse(id: String, targetMM: Int? = nil) -> IPCResponse {
    IPCResponse(id: id, result: .ok(targetMM: targetMM), error: nil)
}

private func makeErrorResponse(id: String, code: Int, message: String) -> IPCResponse {
    IPCResponse(id: id, result: nil, error: IPCErrorPayload(code: code, message: message))
}

// MARK: - Error Mapping Tests

final class IPCClientErrorMappingTests: XCTestCase {

    func testSocketNotFound_throwsDaemonNotRunning() {
        let path = NSTemporaryDirectory() + "no-such-socket-\(UUID().uuidString).sock"
        let client = makeClient(socketPath: path)
        XCTAssertThrowsError(try client.getStatus()) { error in
            XCTAssertEqual(error as? IPCClientError, .daemonNotRunning)
        }
    }

    func testConnectionRefused_throwsDaemonNotRunning() throws {
        // Create a socket file that exists but has no listener (connection refused).
        let path = NSTemporaryDirectory() + "refused-\(UUID().uuidString).sock"
        let tmpFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard tmpFD >= 0 else { throw XCTSkip("Cannot create test socket") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                _ = Darwin.strlcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src, 104)
            }
        }
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(tmpFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(tmpFD)
        defer { unlink(path) }

        let client = makeClient(socketPath: path)
        XCTAssertThrowsError(try client.getStatus()) { error in
            XCTAssertEqual(error as? IPCClientError, .daemonNotRunning)
        }
    }
}

// MARK: - Server Error Response Tests

final class IPCClientServerErrorTests: XCTestCase {

    func testServerError_throwsServerErrorWithCorrectCode() throws {
        let server = TestSocketServer()
        try server.start { request in
            makeErrorResponse(id: request.id, code: 3, message: "desk not connected")
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertThrowsError(try client.getStatus()) { error in
            XCTAssertEqual(error as? IPCClientError, .serverError(code: 3, message: "desk not connected"))
        }
    }

    func testServerError_timeoutCode_preservedInError() throws {
        let server = TestSocketServer()
        try server.start { request in
            makeErrorResponse(id: request.id, code: 5, message: "operation timed out")
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertThrowsError(try client.stop()) { error in
            XCTAssertEqual(error as? IPCClientError, .serverError(code: 5, message: "operation timed out"))
        }
    }
}

// MARK: - Round-Trip Tests

final class IPCClientRoundTripTests: XCTestCase {

    func testGetStatus_returnsStatusFromServer() throws {
        let expected = makeStatusResult(connected: true, heightMM: 730)
        let server = TestSocketServer()
        try server.start { request in
            XCTAssertEqual(request.method, .getStatus)
            return makeStatusResponse(id: request.id, status: expected)
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        let status = try client.getStatus()

        XCTAssertTrue(status.connected)
        XCTAssertEqual(status.heightMM, 730)
        XCTAssertEqual(status.deskName, "LINAK Desk")
    }

    func testMove_sendsCorrectMethodAndParams() throws {
        let server = TestSocketServer()
        try server.start { request in
            XCTAssertEqual(request.method, .move)
            guard case .move(let direction, let mode) = request.params else {
                XCTFail("Expected .move params"); return makeOkResponse(id: request.id)
            }
            XCTAssertEqual(direction, "up")
            XCTAssertEqual(mode, "continuous")
            return makeOkResponse(id: request.id)
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertNoThrow(try client.move(direction: "up", mode: "continuous"))
    }

    func testMove_nilMode_accepted() throws {
        let server = TestSocketServer()
        try server.start { request in makeOkResponse(id: request.id) }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertNoThrow(try client.move(direction: "down", mode: nil))
    }

    func testStop_sendsStopMethod() throws {
        let server = TestSocketServer()
        try server.start { request in
            XCTAssertEqual(request.method, .stop)
            XCTAssertNil(request.params)
            return makeOkResponse(id: request.id)
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertNoThrow(try client.stop())
    }

    func testGoPreset_returnsTargetMM() throws {
        let server = TestSocketServer()
        try server.start { request in
            XCTAssertEqual(request.method, .goPreset)
            guard case .preset(let index) = request.params else {
                XCTFail("Expected .preset params"); return makeOkResponse(id: request.id, targetMM: nil)
            }
            XCTAssertEqual(index, 2)
            return makeOkResponse(id: request.id, targetMM: 1105)
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        let targetMM = try client.goPreset(index: 2)
        XCTAssertEqual(targetMM, 1105)
    }

    func testGoPreset_nilTargetMM_returnedAsNil() throws {
        let server = TestSocketServer()
        try server.start { request in makeOkResponse(id: request.id, targetMM: nil) }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        let targetMM = try client.goPreset(index: 1)
        XCTAssertNil(targetMM)
    }

    func testSavePreset_returnsHeightMM() throws {
        let server = TestSocketServer()
        try server.start { request in
            XCTAssertEqual(request.method, .savePreset)
            return makeOkResponse(id: request.id, targetMM: 730)
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        let heightMM = try client.savePreset(index: 1)
        XCTAssertEqual(heightMM, 730)
    }

    func testRequestIsFramedCorrectly_serverReceivesValidJSON() throws {
        var receivedRequest: IPCRequest?
        let server = TestSocketServer()
        try server.start { request in
            receivedRequest = request
            return makeStatusResponse(id: request.id, status: makeStatusResult())
        }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        _ = try client.getStatus()

        XCTAssertNotNil(receivedRequest)
        XCTAssertEqual(receivedRequest?.method, .getStatus)
        XCTAssertFalse(receivedRequest?.id.isEmpty ?? true)
    }
}

// MARK: - Invalid Response Tests

final class IPCClientInvalidResponseTests: XCTestCase {

    func testGetStatus_withOkResult_throwsInvalidResponse() throws {
        let server = TestSocketServer()
        try server.start { request in makeOkResponse(id: request.id) }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertThrowsError(try client.getStatus()) { error in
            XCTAssertEqual(error as? IPCClientError, .invalidResponse)
        }
    }

    func testStop_withStatusResult_throwsInvalidResponse() throws {
        let server = TestSocketServer()
        try server.start { request in makeStatusResponse(id: request.id, status: makeStatusResult()) }
        defer { server.stop() }

        let client = makeClient(socketPath: server.socketPath)
        XCTAssertThrowsError(try client.stop()) { error in
            XCTAssertEqual(error as? IPCClientError, .invalidResponse)
        }
    }
}

// MARK: - Factory

private func makeClient(socketPath: String) -> IPCClient {
    IPCClient(socketPath: socketPath)
}
