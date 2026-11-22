import XCTest

/// Deciding from the Sort list: rows keep their place, the next row doesn't move, the count
/// updates, Undo works, "Hide decided" waits until the person moves on, and things regroup
/// only after leaving Sort.
final class StableDecisionsTests: XCTestCase {
    private var shots = 0

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let a = XCTAttachment(screenshot: shot); a.name = name; a.lifetime = .keepAlways; add(a)
        shots += 1
        if let dir = ProcessInfo.processInfo.environment["SORT_SHOTS_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/stable-\(shots).png"))
        }
    }

    /// Alex's view of the demo room: Bed, Desk, Guitar and Trophies are theirs to decide.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoReset", "-demoRoom", "-demoAsGuest", "-demoTab", "sort", "-forceLight"]
        app.launch()
        XCTAssertTrue(sortTab(app).waitForExistence(timeout: 15))
        let asList = app.buttons["Show as a list"]
        if asList.waitForExistence(timeout: 3) { asList.tap() }
        return app
    }

    /// The tab's label carries its badge ("Sort, 3").
    private func sortTab(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sort'")).firstMatch
    }

    /// Rows that were on screen both times keep their order.
    private func assertSameOrder(_ before: [String], _ after: [String], file: StaticString = #filePath, line: UInt = #line) {
        let n = min(before.count, after.count)
        XCTAssertEqual(Array(after.prefix(n)), Array(before.prefix(n)), "rows reordered", file: file, line: line)
    }

    private func chevrons(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show choices for ' OR label BEGINSWITH 'Hide choices for '"))
            .allElementsBoundByIndex.filter { $0.frame.height > 0 && $0.frame.minY > 0 && $0.frame.maxY < app.frame.height }.sorted { $0.frame.minY < $1.frame.minY }
    }

    private func names(_ app: XCUIApplication) -> [String] {
        chevrons(app).map { $0.label.replacingOccurrences(of: "Show choices for ", with: "").replacingOccurrences(of: "Hide choices for ", with: "") }
    }

    private func progress(_ app: XCUIApplication) -> String {
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' decided'")).firstMatch.label
    }

    /// Scrolls so the first two rows are on screen, with room below.
    private func showRows(_ app: XCUIApplication) {
        var tries = 0
        while chevrons(app).count < 2 && tries < 8 { app.swipeUp(); tries += 1 }
        let first = chevrons(app).first!
        // Put the first row in the upper part of the screen.
        if first.frame.minY > app.frame.height * 0.45 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            sleep(1)
        }
    }

    func testDecisionStaysInPlaceAndRegroupsLater() throws {
        let app = launch()
        showRows(app)
        let before = names(app)
        XCTAssertGreaterThanOrEqual(before.count, 2, "need two rows on screen")
        let first = before[0], second = before[1]
        let startCount = progress(app)
        attach(app, "start")

        // Open the first row and decide.
        app.buttons["Show choices for \(first)"].tap()
        let keep = app.buttons["Keep"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 3))
        sleep(1)
        let nextTop = app.buttons["Show choices for \(second)"].frame.minY
        let firstTop = app.buttons["Hide choices for \(first)"].frame.minY
        keep.tap()
        let banner = app.staticTexts["Marked “Keep”"]
        XCTAssertTrue(banner.waitForExistence(timeout: 2), "no Marked Keep banner")
        XCTAssertGreaterThan(banner.frame.minY, app.frame.height / 2, "banner isn't at the bottom")
        sleep(1)
        attach(app, "decided")

        // Nothing moves: the row stays open in the same place, and so does the row after it.
        let openRow = app.buttons["Hide choices for \(first)"]
        XCTAssertTrue(openRow.exists, "\(first) closed or left the list")
        print("DECIDED ROW TOP before \(firstTop) after \(openRow.frame.minY); NEXT ROW before \(nextTop) after \(app.buttons["Show choices for \(second)"].frame.minY)")
        XCTAssertEqual(openRow.frame.minY, firstTop, accuracy: 1, "the decided row moved")
        XCTAssertEqual(app.buttons["Show choices for \(second)"].frame.minY, nextTop, accuracy: 1, "the row changed height")
        assertSameOrder(before, names(app))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Staying'")).firstMatch.exists,
                      "no Staying tag on the row")
        XCTAssertNotEqual(progress(app), startCount, "decided count didn't change")

        // Clear it, decide again, then Undo: back to undecided, still in place.
        keep.tap()
        XCTAssertTrue(app.staticTexts["Decision cleared"].waitForExistence(timeout: 2))
        keep.tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.tap()
        sleep(1)
        XCTAssertEqual(progress(app), startCount, "Undo didn't clear the decision")
        XCTAssertEqual(openRow.frame.minY, firstTop, accuracy: 1)
        attach(app, "undone")

        // Decide again, then leave Sort and come back: now it's regrouped into Decided.
        keep.tap()
        sleep(1)
        XCTAssertTrue(openRow.exists)
        app.buttons["Room"].firstMatch.tap()
        sleep(1)
        sortTab(app).tap()
        sleep(1)
        var tries = 0
        while chevrons(app).isEmpty && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertFalse(names(app).contains(first), "\(first) still under For you to decide after coming back")
        attach(app, "regrouped")
    }

    func testHideDecidedWaitsUntilMovingOn() throws {
        let app = launch()
        let toggle = app.switches["Hide decided"].firstMatch
        var tries = 0
        while !(toggle.exists && toggle.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(toggle.exists, "no Hide decided switch")
        toggle.tap()
        showRows(app)
        let before = names(app)
        let first = before[0], second = before[1]

        app.buttons["Show choices for \(first)"].tap()
        app.buttons["Keep"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Hide choices for \(first)"].exists, "hidden the moment it was decided")
        attach(app, "decided, still shown")

        // Moving on: open the next row. The decided one fades out; the opened row stays put.
        // (Bring it fully on screen first: XCUITest scrolls anything half-hidden before tapping it.)
        var drags = 0
        while !app.buttons["Show choices for \(second)"].isHittable && drags < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            sleep(1); drags += 1
        }
        let secondTop = app.buttons["Show choices for \(second)"].frame.minY
        attach(app, "before moving on")
        app.buttons["Show choices for \(second)"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Show choices for \(first)"].exists || app.buttons["Hide choices for \(first)"].exists,
                       "decided row didn't hide after moving on")
        let secondAfter = app.buttons["Hide choices for \(second)"].frame.minY
        print("OPENED ROW TOP before \(secondTop) after \(secondAfter)")
        XCTAssertEqual(secondAfter, secondTop, accuracy: 2, "the row being opened moved when the other one hid")
        attach(app, "moved on, hidden")
    }

    func testExpandingKeepsPlace() throws {
        let app = launch()
        showRows(app)
        let rows = names(app)
        let first = rows[0], second = rows[1]

        // One row: it doesn't move; the row below moves down.
        let top = app.buttons["Show choices for \(first)"].frame.minY
        app.buttons["Show choices for \(first)"].tap()
        sleep(1)
        print("TAPPED ROW TOP before \(top) after \(app.buttons["Hide choices for \(first)"].frame.minY)")
        XCTAssertEqual(app.buttons["Hide choices for \(first)"].frame.minY, top, accuracy: 1, "the tapped row moved")
        app.buttons["Hide choices for \(first)"].tap()
        sleep(1)
        XCTAssertEqual(app.buttons["Show choices for \(first)"].frame.minY, top, accuracy: 1, "the row moved when closing")

        // Expand all: the row at the top stays at the top; the label switches.
        let all = app.buttons["Expand all items"]
        XCTAssertTrue(all.isHittable, "Expand all isn't on screen")
        let firstTop = app.buttons["Show choices for \(first)"].frame.minY
        all.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Collapse all items"].exists)
        print("TOP ROW before \(firstTop) after \(app.buttons["Hide choices for \(first)"].frame.minY)")
        XCTAssertEqual(app.buttons["Hide choices for \(first)"].frame.minY, firstTop, accuracy: 1, "the list jumped on Expand all")
        XCTAssertTrue(app.buttons["Hide choices for \(second)"].exists || !app.buttons["Show choices for \(second)"].exists)
        attach(app, "expand all")
        app.buttons["Collapse all items"].tap()
        sleep(1)
        XCTAssertEqual(app.buttons["Show choices for \(first)"].frame.minY, firstTop, accuracy: 1, "the list jumped on Collapse all")
    }

    /// For recording: Expand all then Collapse all, with pauses (not run in the normal suite).
    func testRecordExpandAll() throws {
        guard ProcessInfo.processInfo.environment["RECORD_EXPAND"] != nil else { throw XCTSkip("recording only") }
        let app = launch()
        showRows(app)
        let all = app.buttons["Expand all items"]
        sleep(3)
        NSLog("REC tap expand")
        all.tap()
        sleep(3)
        NSLog("REC tap collapse")
        app.buttons["Collapse all items"].tap()
        sleep(3)
    }
}
