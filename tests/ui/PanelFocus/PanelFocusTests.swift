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

    private func panel() -> XCUIElement {
        app.dialogs.firstMatch
    }

    private func row(_ id: String) -> XCUIElement {
        panel().descendants(matching: .any)["item.rows.\(id)"].firstMatch
    }

    private func openPanel() throws {
        try statusItem().click()
        XCTAssertTrue(panel().waitForExistence(timeout: 10), "the panel never opened")
        XCTAssertTrue(row("alpha").waitForExistence(timeout: 10), "panel rows never appeared\n\(panel().debugDescription)")
    }

    private func closePanel() throws {
        try statusItem().click()
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
