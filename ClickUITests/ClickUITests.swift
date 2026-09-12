//
//  ClickUITests.swift
//  Click
//

import XCTest

final class ClickUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        // The --uitest flag keeps DemoPhotos off the network in tests.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["--uitest"]
            app.launch()
        }
    }
}
