//
//  SafetyMenuUITests.swift
//  ClickUITests
//
//  Regression test for FINDINGS §4: on a card with 2+ photos, the photo
//  paging overlay used to hit-test above the safety menu, so tapping the
//  ellipsis paged the photo instead of opening report/block. Every seeded
//  profile gets two photos in this mode, so whichever card is on top, the
//  menu must still open.
//

import XCTest

final class SafetyMenuUITests: XCTestCase {

    @MainActor
    func testSafetyMenuOpensOnMultiPhotoCard() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-signed-in",
            "--uitest-photos",
            "-onboardingCompleted", "YES",
            "-welcomePopupShown", "YES"
        ]
        app.launch()

        let menuButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Safety options for'")
        ).firstMatch
        XCTAssertTrue(
            menuButton.waitForExistence(timeout: 10),
            "Swipe deck should show a card with its safety menu"
        )

        menuButton.tap()

        XCTAssertTrue(
            app.buttons["Report"].waitForExistence(timeout: 5),
            "Tapping the ellipsis on a multi-photo card must open the safety menu, not page the photo"
        )
    }
}
