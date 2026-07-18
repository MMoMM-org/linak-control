// DeskManagerStateStreamTests.swift
// LinakControlTests — Verifies that stateStream is multicast: multiple
// subscribers (the UI and the notification observer) each receive every
// snapshot, rather than competing for a single AsyncStream's elements.

import XCTest
@testable import LinakControlKit

final class DeskManagerStateStreamMulticastTests: XCTestCase {

    func testMultipleSubscribersEachReceiveEveryUpdate() async throws {
        let mock = MockBLEController()
        let manager = DeskManager(bleController: mock, configStore: makeTempConfigStore())

        var iteratorA = await manager.stateStream.makeAsyncIterator()
        var iteratorB = await manager.stateStream.makeAsyncIterator()

        // Each subscriber receives the current snapshot immediately on subscribe.
        let firstA = await iteratorA.next()
        let firstB = await iteratorB.next()
        XCTAssertEqual(firstA?.connectionState, .disconnected)
        XCTAssertEqual(firstB?.connectionState, .disconnected)

        // A state change after subscription must fan out to BOTH subscribers.
        _ = await manager.scan() // sets connectionState = .scanning

        let nextA = await iteratorA.next()
        let nextB = await iteratorB.next()
        XCTAssertEqual(nextA?.connectionState, .scanning, "Subscriber A must receive the update")
        XCTAssertEqual(nextB?.connectionState, .scanning, "Subscriber B must receive the update")
    }
}
