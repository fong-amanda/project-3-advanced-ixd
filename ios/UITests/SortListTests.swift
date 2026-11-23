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

    /// The floating tab bar must never cover the end of a page.
    func testBottomOfPageClearsTabBar() throws {
        let app = launch()
        for _ in 0..<8 { app.swipeUp() }
        sleep(1)
        attach(app, "bottom of Sort")
        let add = app.buttons["Add something"]
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sort'")).firstMatch
        XCTAssertTrue(add.exists && add.isHittable, "Add something can't be tapped")
        print("ADD maxY", add.frame.maxY, "BAR minY", bar.frame.minY)
        XCTAssertLessThanOrEqual(add.frame.maxY, bar.frame.minY + 1, "Add something is under the tab bar")
        // The other tabs: scroll to the bottom by dragging near the top (away from the floor plan).
        for tab in ["Redesign", "People", "Room"] {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tab)).firstMatch.tap()
            sleep(1)
            for _ in 0..<14 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.8))
                    .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)))
            }
            sleep(1)
            attach(app, "bottom of \(tab)")
        }
    }

    /// The room's large title keeps its left margin when a room is opened from Rooms.
    func testRoomTitleMargin() throws {
        let app = launch()
        attach(app, "opened directly")
        app.buttons["Back to rooms"].firstMatch.tap()
        sleep(1)
        for i in 0..<3 {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alex'")).firstMatch.tap()
            sleep(2)
            let title = app.staticTexts["Alex’s old room"].firstMatch
            print("TITLE minX", i, title.exists ? title.frame.minX : -1)
            attach(app, "reopened \(i)")
            app.buttons["Back to rooms"].firstMatch.tap()
            sleep(1)
        }
        // From the Sort tab's empty state (no items for this person), as on the guest's phone.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alex'")).firstMatch.tap()
        sleep(2)
        attach(app, "final")
    }

    /// Tapping an empty spot on the room photo opens "Add something" at that spot.
    func testTapPhotoToAdd() throws {
        let app = launch()
        let photo = app.descendants(matching: .any)["Photo of the room"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "no room photo")
        // Top-left of the photo: wall, away from the pins.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.15)).tap()
        sleep(2)
        attach(app, "after tapping the photo")
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Add'")).firstMatch.exists
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Add something'")).firstMatch.exists
                      || app.textFields.firstMatch.exists, "tapping the photo didn't open Add something")
    }

    /// The furniture catalogue in Redesign: real pieces, placed and drawn with their 3D model.
    func testFurnitureCatalogue() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoReset", "-demoRoom", "-demoTab", "plan", "-demo3D", "-forceLight"]
        app.launch()
        sleep(3)
        let loveseat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Place Midtown loveseat'")).firstMatch
        var tries = 0
        while !(loveseat.exists && loveseat.isHittable) && tries < 12 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.3)))
            tries += 1
        }
        attach(app, "catalogue")
        XCTAssertTrue(loveseat.exists, "catalogue doesn't list the Midtown loveseat")
        loveseat.tap()
        sleep(4)
        attach(app, "placed in 3D")
        for _ in 0..<12 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.2)))
        }
        let credits = app.buttons["Furniture credits"]
        XCTAssertTrue(credits.exists, "no Furniture credits button")
        credits.tap()
        sleep(2)
        attach(app, "credits")
    }
}
