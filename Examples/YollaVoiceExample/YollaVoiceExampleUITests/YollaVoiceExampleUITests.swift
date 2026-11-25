//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import XCTest

final class YollaVoiceExampleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    /// The dialer's number field brings up the phone pad, which has no return key: the screen must keep the field
    /// clear of the title while the keyboard is up, and offer a way to put the keyboard away.
    @MainActor
    func testDialerKeyboardLeavesTheTitleAloneAndCanBeDismissed() throws {
        let app = XCUIApplication()
        app.launch()

        let field = app.textFields["Phone number"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "The keyboard did not open")

        let title = app.staticTexts["Yolla Voice"]
        if title.exists {
            XCTAssertFalse(title.frame.intersects(field.frame), "The number field overlaps the title")
        }
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, "The number field is under the keyboard")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2), "Nothing to dismiss the keyboard with")
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "The keyboard is still open")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
