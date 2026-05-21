// LinakControlScreenshotTests.swift
// LinakControlUITests — captures documentation screenshots via XCUITest.
//
// Assumes ~/Library/Application Support/LinakControl/config.json has a valid
// paired_desk_uuid and that the desk is powered on and reachable. No demo BLE
// mocking — see docs/ai/handoff/screenshot-tests.md for the rationale.

import XCTest

final class LinakControlScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // Wait for zone 1 status item to appear (signals app finished launching).
        let zone1 = app.statusItems["linak.menubar.zone1.icon"]
        XCTAssertTrue(
            zone1.waitForExistence(timeout: 10),
            "zone1 status item never appeared — is the app launching cleanly?"
        )

        // Give the connect-on-launch task time to reach .connected so the
        // popover and preset menu reflect real desk state.
        Thread.sleep(forTimeInterval: 4)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func test_screenshot_menubar_popover() throws {
        let zone1 = app.statusItems["linak.menubar.zone1.icon"]
        zone1.click()
        Thread.sleep(forTimeInterval: 0.5)
        attach(name: "menubar-popover", screenshot: XCUIScreen.main.screenshot())
    }

    func test_screenshot_preset_menu() throws {
        let zone2 = app.statusItems["linak.menubar.zone2.text"]
        zone2.click()
        Thread.sleep(forTimeInterval: 0.3)
        attach(name: "menubar-preset-menu", screenshot: XCUIScreen.main.screenshot())
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private func attach(name: String, screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
