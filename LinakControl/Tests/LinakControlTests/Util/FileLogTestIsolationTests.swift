// FileLogTestIsolationTests.swift
// LinakControlTests — Verifies that the suite stays out of the user's real
// diagnostic log (issue #18). Before this guard, a full run interleaved fixture
// events — including fabricated E16/E26 faults that never happened on any
// hardware — into ~/Library/Logs/LinakControl/debug.log, the file
// docs/troubleshooting.md asks users to capture for a bug report.

import XCTest
@testable import LinakControlKit

final class FileLogTestIsolationTests: XCTestCase {

    private var realLog: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LinakControl/debug.log")
    }

    private func sizeOfRealLog() -> Int? {
        try? Data(contentsOf: realLog).count
    }

    func testTestProcessIsDetected() {
        XCTAssertTrue(
            FileLog.isRunningUnderTest,
            "The XCTest detection is what disables logging — if this ever goes false, the suite is writing to the real log again"
        )
    }

    /// The property that actually matters: logging from a test must leave the
    /// user's log byte-for-byte untouched, and must not create it if absent.
    func testLoggingFromATestDoesNotTouchTheRealLog() {
        let before = sizeOfRealLog()

        FileLog.debug("issue-18 regression probe — must never reach the real log", category: "test")
        FileLog.trace("issue-18 regression probe — trace variant", category: "test")
        FileLog.flushForTesting()

        let after = sizeOfRealLog()

        XCTAssertEqual(
            before, after,
            "Logging from a test must not write to ~/Library/Logs/LinakControl/debug.log"
        )
    }
}
