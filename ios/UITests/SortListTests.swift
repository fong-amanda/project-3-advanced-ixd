import XCTest

/// Sort list: deciding in place (chevron), "Expand all", and swipe-to-delete with Undo.
final class SortListTests: XCTestCase {
    private var shots = 0

    /// Screenshots go into the test report, and also to `SORT_SHOTS_DIR` when it's set.
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let a = XCTAttachment(screenshot: shot); a.name = name; a.lifetime = .keepAlways; add(a)
        shots += 1
        if let dir = ProcessInfo.processInfo.environment["SORT_SHOTS_DIR"] {
            let test = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(test)-\(shots).png"))
        }
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoReset", "-demoRoom", "-demoTab", "sort", "-forceLight"]
        app.launch()
        XCTAssertTrue(app.buttons["Sort"].waitForExistence(timeout: 15))
        return app
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 10 { app.swipeUp(); tries += 1 }
    }

    /// The list loads rows as they scroll in, so scroll down to the first one.
    private func firstChevron(_ app: XCUIApplication) -> XCUIElement {
        // The demo host has nothing of their own to decide; Alex's things are under "Waiting".
        let waiting = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for '")).firstMatch
        scrollUntilHittable(waiting, in: app)
        waiting.tap()
        let chevron = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show choices for '")).firstMatch
        scrollUntilHittable(chevron, in: app)
        if !chevron.exists {
            attach(app, "no chevron after scrolling")
            print("TREE:", app.debugDescription.components(separatedBy: "\n").filter { $0.contains("Button") || $0.contains("Cell") }.prefix(60).joined(separator: "\n"))
        }
        XCTAssertTrue(chevron.exists, "no rows with a chevron")
        return chevron
    }

    func testPinTapScrollsToRow() throws {
        let app = launch()
        let waiting = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for '")).firstMatch
        scrollUntilHittable(waiting, in: app)
        waiting.tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1, '")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5) && pin.isHittable, "pin 1 not on screen")
        let name = pin.label.components(separatedBy: ", ").dropFirst().first ?? ""
        pin.tap()
        sleep(2)
        attach(app, "pin tapped")
        XCTAssertTrue(app.buttons["Show choices for \(name)"].isHittable, "tapping pin 1 didn't scroll to \(name)'s row")
    }

    func testDecideInPlaceAndExpandAll() throws {
        let app = launch()
        let chevron = firstChevron(app)
        let name = chevron.label.replacingOccurrences(of: "Show choices for ", with: "")
        chevron.tap()
        let keep = app.buttons["Suggest: Keep"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 3), "decision buttons didn't open")
        XCTAssertTrue(app.buttons["Hide choices for \(name)"].exists)
        attach(app, "one row open")

        keep.tap()
        sleep(1)
        // The row stays open and in place after a decision.
        XCTAssertTrue(app.buttons["Hide choices for \(name)"].exists, "row closed or left the list after deciding")
        XCTAssertTrue(keep.isSelected, "Keep isn't shown as selected")
        attach(app, "kept, still open")

        // Tapping the same decision again clears it.
        keep.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Suggest: Keep"].firstMatch.isSelected, "tapping Keep again didn't clear it")
        attach(app, "cleared")

        // Expand all: every row opens, and stays open after a decision.
        let all = app.buttons["Expand all items"]
        app.swipeDown(); app.swipeDown()
        scrollUntilHittable(all, in: app)
        all.tap()
        XCTAssertTrue(app.buttons["Collapse all items"].waitForExistence(timeout: 3))
        sleep(1)
        // The list only exposes rows on screen, so collect the open ones while scrolling.
        var open = Set<String>()
        var closed = Set<String>()
        for _ in 0..<6 {
            open.formUnion(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hide choices for '")).allElementsBoundByIndex.map(\.label))
            closed.formUnion(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show choices for '")).allElementsBoundByIndex.map(\.label))
            app.swipeUp()
        }
        print("EXPANDED ROWS:", open.sorted(), "CLOSED:", closed.sorted())
        XCTAssertGreaterThan(open.count, 1)
        XCTAssertTrue(closed.isEmpty, "some rows stayed closed with Expand all on")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        scrollUntilHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hide choices for '")).firstMatch, in: app)
        attach(app, "expand all")
        let firstOpen = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hide choices for '")).element(boundBy: 0)
        let openName = firstOpen.label.replacingOccurrences(of: "Hide choices for ", with: "")
        app.buttons.matching(NSPredicate(format: "label == 'Suggest: Throw out'")).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Hide choices for \(openName)"].exists, "row closed after deciding with Expand all on")
        attach(app, "expand all, decided, still open")
    }

    func testSwipeDeleteAndUndo() throws {
        let app = launch()
        let chevron = firstChevron(app)
        let name = chevron.label.replacingOccurrences(of: "Show choices for ", with: "")
        let cell = app.cells.containing(.button, identifier: "Show choices for \(name)").firstMatch
        XCTAssertTrue(cell.exists, "row isn't a list cell")
        cell.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "no Delete swipe action")
        attach(app, "swiped")
        delete.tap()
        XCTAssertTrue(app.staticTexts["Item deleted"].waitForExistence(timeout: 3), "no undo banner")
        XCTAssertFalse(app.buttons["Show choices for \(name)"].exists, "row still there after delete")
        attach(app, "deleted, banner")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Show choices for \(name)"].waitForExistence(timeout: 3), "Undo didn't bring it back")
        attach(app, "undone")
    }
}
