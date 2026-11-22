import XCTest

/// Redesign: placing a piece from the catalogue makes it obvious (banner, selected, room in view),
/// and a placed piece can be dragged and turned directly in the 3D view.
final class FurniturePlacementTests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testPlaceThenDragIn3D() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoReset", "-demoRoom", "-demoTab", "plan", "-forceLight"]
        app.launch()
        XCTAssertTrue(app.buttons["Redesign"].waitForExistence(timeout: 15))

        // 1. Place the first catalogue piece.
        let place = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Place '")).firstMatch
        var tries = 0
        while !place.isHittable && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(place.exists, "no catalogue piece to place")
        let pieceName = place.label.replacingOccurrences(of: "Place ", with: "").components(separatedBy: ",").first ?? ""
        place.tap()
        let banner = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Added '")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "no “Added …” banner")
        print("BANNER:", banner.label)
        attach(app, "1 placed (banner, highlight)")
        // The room view is back on screen (scrolled up), with the piece's bar.
        XCTAssertTrue(app.buttons["3D"].isHittable, "the room view isn't in view after placing")
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertTrue(app.buttons["Rotate 90°"].exists, "piece bar not shown for \(pieceName)")
        sleep(2)
        attach(app, "2 placed, after the pulse")

        // 2. Drag it in 3D.
        app.buttons["3D"].tap()
        let marker = app.otherElements["debug-selected-piece"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "selected piece not found in 3D")
        sleep(1)
        attach(app, "3 in 3D, selected")
        let before = marker.label
        let start = marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -70, dy: 40))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        let after = app.otherElements["debug-selected-piece"].label
        print("MOVED:", before, "→", after)
        XCTAssertNotEqual(before, after, "dragging the piece didn't move it")
        attach(app, "4 after dragging in 3D")

        // 2b. Drag it onto other furniture: the bar says what it overlaps.
        let m2 = app.otherElements["debug-selected-piece"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        m2.press(forDuration: 0.15, thenDragTo: m2.withOffset(CGVector(dx: -150, dy: -10)), withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        let problem = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Overlaps' OR label == 'Goes through a wall'")).firstMatch
        print("PROBLEM:", problem.exists ? problem.label : "none", app.otherElements["debug-selected-piece"].label)
        XCTAssertTrue(problem.exists, "dragging onto furniture didn't say what it overlaps")
        attach(app, "4b dragged onto other furniture")

        // 3. Rotate with the bar's button (the non-gesture alternative).
        let rotate = app.buttons["Rotate 90°"]
        if !rotate.isHittable { app.swipeUp() }
        rotate.tap()
        sleep(1)
        let turned = app.otherElements["debug-selected-piece"].label
        print("ROTATED:", after, "→", turned)
        XCTAssertNotEqual(after.split(separator: ",").last, turned.split(separator: ",").last, "Rotate 90° didn't turn it")
        XCTAssertFalse(app.staticTexts["Goes through a wall"].exists, "rotating pushed it through a wall")
        attach(app, "5 after Rotate 90°")
    }
}
