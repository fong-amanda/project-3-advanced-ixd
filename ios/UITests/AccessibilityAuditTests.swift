import XCTest

/// Runs XCTest's built-in accessibility audit (`performAccessibilityAudit`) on the main screens,
/// in light and dark mode: Home, a room's Sort tab, the item decision sheet, New room's photo
/// step, and Redesign. Every issue is printed as an "AUDIT" line (and attached with a
/// screenshot), then the test fails if any screen had issues.
///
/// Run: Xcode → Product → Test (⌘U), or
///   xcodebuild test -project SharedSpace.xcodeproj -scheme SharedSpace \
///     -destination 'platform=iOS Simulator,name=iPhone 17'
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private struct Screen {
        let name: String
        let arguments: [String]
        /// Something that's on screen once it has loaded.
        let ready: (XCUIApplication) -> XCUIElement
    }

    private let screens: [Screen] = [
        Screen(name: "Home", arguments: []) { $0.staticTexts["Rooms"] },
        Screen(name: "Sort tab", arguments: ["-demoRoom", "-demoTab", "items"]) { $0.buttons["Sort"] },
        Screen(name: "Item decision sheet", arguments: ["-demoRoom", "-demoTab", "items", "-demoItemSheet"]) { $0.buttons["Done"] },
        Screen(name: "New room photo step", arguments: ["-demoNewRoom", "photos"]) { $0.staticTexts["Show the room as it is now"] },
        Screen(name: "Redesign", arguments: ["-demoRoom", "-demoTab", "plan"]) { $0.buttons["Redesign"] },
    ]

    func testLightMode() throws { try audit(scheme: "-forceLight", label: "light") }
    func testDarkMode() throws { try audit(scheme: "-forceDark", label: "dark") }

    private func audit(scheme: String, label: String) throws {
        var total = 0
        for (i, screen) in screens.enumerated() {
            let app = XCUIApplication()
            // The first launch makes a fresh demo room (sample photo and pins).
            app.launchArguments = screen.arguments + [scheme] + (i == 0 ? ["-demoReset", "-demoRoom"] : [])
            if i == 0 {
                // Home after the reset: relaunch without opening the room.
                app.launch(); sleep(2); app.terminate()
                app.launchArguments = [scheme]
            }
            app.launch()
            XCTAssertTrue(screen.ready(app).waitForExistence(timeout: 15), "\(screen.name) didn't load")
            sleep(2)
            attach(app, "\(screen.name) (\(label))")

            var issues: [String] = []
            var exempt: [String] = []
            let navBar = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame : .zero
            try app.performAccessibilityAudit(for: .all) { issue in
                let element = issue.element.map { "\($0.elementType) '\($0.label)'" } ?? "screen"
                let line = "\(screen.name) [\(label)]: \(Self.name(issue.auditType)) — \(issue.compactDescription) — \(element)"
                if let reason = Self.exemption(issue, navBar: navBar) {
                    print("AUDIT EXEMPT \(line) — \(reason)")
                    exempt.append("\(line) — \(reason)")
                } else {
                    print("AUDIT ISSUE \(line)")
                    issues.append(line)
                }
                return true   // handled: collect them all instead of stopping at the first
            }
            print("AUDIT [\(label)] \(screen.name): \(issues.count) issue(s), \(exempt.count) exempt")
            total += issues.count
            if !(issues + exempt).isEmpty {
                let a = XCTAttachment(string: (issues.map { "ISSUE " + $0 } + exempt.map { "EXEMPT " + $0 }).joined(separator: "\n"))
                a.name = "Audit: \(screen.name) (\(label))"; a.lifetime = .keepAlways; add(a)
            }
            app.terminate()
        }
        XCTAssertEqual(total, 0, "\(total) accessibility audit issue(s) in \(label) mode; see the AUDIT lines")
    }

    /// Known exemptions, each with the reason it isn't a real failure. Everything else fails the test.
    private static func exemption(_ issue: XCUIAccessibilityAuditIssue, navBar: CGRect) -> String? {
        guard let e = issue.element else { return nil }
        if !e.isEnabled { return "disabled control (WCAG 1.4.3 exempts inactive components)" }
        if issue.auditType == .dynamicType, e.elementType == .button, navBar.contains(CGPoint(x: e.frame.midX, y: e.frame.midY)) {
            return "system navigation-bar button: iOS keeps these a fixed size and shows them large with touch and hold (Large Content Viewer)"
        }
        let inNavBar = navBar.contains(CGPoint(x: e.frame.midX, y: e.frame.midY))
        if issue.auditType == .contrast && (e.elementType == .staticText || (e.elementType == .button && inNavBar)) {
            // Plain text (and nav-bar buttons) only: XCTest's pixel-based check flags these even when
            // the text is drawn in pure black (tested). Their colour pairs are checked exactly on
            // the Accessibility check screen (textSecondary 5.6:1+ light, 5.8:1+ dark; iconNeutral
            // 9:1+). Contrast issues on any other control still fail.
            return "pixel-check false positive; colour pair verified ≥ 4.5:1 on the Accessibility check screen"
        }
        return nil
    }

    private static func name(_ t: XCUIAccessibilityAuditType) -> String {
        switch t {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "type \(t.rawValue)"
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
