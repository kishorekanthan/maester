import XCTest

final class PanelFocusTests: XCTestCase {
    private let rowIDs = ["alpha", "beta", "gamma"]
    private var app: XCUIApplication!
    private var actionLog: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let appPath = try XCTUnwrap(env["MAESTER_UI_APP"], "MAESTER_UI_APP is not set")
        let configDir = try XCTUnwrap(env["MAESTER_UI_CONFIG_DIR"], "MAESTER_UI_CONFIG_DIR is not set")
        actionLog = URL(fileURLWithPath: configDir).appendingPathComponent("do.log")
        app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launchEnvironment["MAESTER_CONFIG_DIR"] = configDir
        app.launch()
        try openPanel()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testArrowKeysMoveTheKeyboardRow() throws {
        try clickRowBody("gamma")
        app.typeKey(.downArrow, modifierFlags: [])
        let first = settledSelection()
        app.typeKey(.downArrow, modifierFlags: [])
        let second = settledSelection()
        XCTAssertEqual(first, ["alpha"])
        XCTAssertEqual(second, ["beta"])
    }

    func testClickingARowBodyRingsNoRow() throws {
        try clickRowBody("beta")
        XCTAssertEqual(settledSelection(), [])
    }

    func testReturnFiresTheKeyboardRowsFirstAction() throws {
        try clickRowBody("gamma")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(settledSelection(), ["beta"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(waitForActionLog(), "open beta\n")
    }

    func testReopeningThePanelRingsNoRow() throws {
        try clickRowBody("gamma")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(settledSelection(), ["alpha"])
        try closePanel()
        try openPanel()
        XCTAssertEqual(settledSelection(), [])
    }

    private func statusItem() throws -> XCUIElement {
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "no status item")
        return item
    }

    private func clickStatusItem() throws {
        let item = try statusItem()
        let topEdge = CGVector(dx: 0.5, dy: -item.frame.minY / item.frame.height)
        item.coordinate(withNormalizedOffset: topEdge).hover()
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "the menu bar never showed the status item")
        item.click()
    }

    private func panel() -> XCUIElement {
        app.dialogs.firstMatch
    }

    private func row(_ id: String) -> XCUIElement {
        panel().descendants(matching: .any)["item.rows.\(id)"].firstMatch
    }

    private func openPanel() throws {
        XCTAssertTrue(try clickUntilPanelOpens(attempts: 3), "the panel never opened")
        XCTAssertTrue(row("alpha").waitForExistence(timeout: 10), "panel rows never appeared\n\(panel().debugDescription)")
    }

    private func clickUntilPanelOpens(attempts: Int) throws -> Bool {
        for _ in 0..<attempts {
            try clickStatusItem()
            if panel().waitForExistence(timeout: 4) {
                return true
            }
        }
        return false
    }

    private func closePanel() throws {
        try clickStatusItem()
        let gone = NSPredicate(format: "exists == false")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: panel())
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, "panel did not close")
    }

    private func clickRowBody(_ id: String) throws {
        let target = row(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).click()
    }

    private func selectedRows() -> [String] {
        rowIDs.filter { row($0).isSelected }
    }

    private func settledSelection() -> [String] {
        var last = selectedRows()
        var stableSince = Date()
        let deadline = stableSince.addingTimeInterval(6)
        while Date() < deadline, Date().timeIntervalSince(stableSince) < 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let now = selectedRows()
            if now != last {
                last = now
                stableSince = Date()
            }
        }
        return last
    }

    private func waitForActionLog() -> String? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let text = try? String(contentsOf: actionLog, encoding: .utf8), !text.isEmpty {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }
}
