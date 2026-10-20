import XCTest

/// Runs against SpringBoard and the real WidgetKit extension. The main app is
/// explicitly terminated before either timeline request and must remain stopped.
@MainActor final class WidgetExtensionUITests: XCTestCase {
    func testWidgetFetchesChangedStatisticsWithMainAppTerminated() async throws {
        guard let origin = Bundle(for: Self.self).object(forInfoDictionaryKey: "WidgetFixtureOrigin") as? String,
              origin.hasPrefix("http://127.0.0.1:") else { throw XCTSkip("Run the isolated widget E2E script") }
        continueAfterFailure = false
        let main = XCUIApplication(bundleIdentifier: Bundle(for: Self.self).object(forInfoDictionaryKey: "WidgetMainBundleID") as? String ?? "fail.still.iphone")
        main.terminate()
        XCUIDevice.shared.press(.home)
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        print("SPRINGBOARD_INITIAL\n" + spring.debugDescription)
        addWidget(in: spring)
        XCTAssertTrue(spring.staticTexts["2"].waitForExistence(timeout: 30), "widget must fetch the initial count itself")
        XCTAssertEqual(main.state, .notRunning)
        let first = XCTAttachment(screenshot: spring.screenshot()); first.name = "Widget count 2, main app stopped"; first.lifetime = .keepAlways; add(first)
        var request = URLRequest(url: URL(string: origin + "/test/update")!)
        request.httpMethod = "POST"; request.httpBody = Data(#"{"count":7}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        _ = try await URLSession.shared.data(for: request)
        // WidgetKit can reuse a cached static timeline when a widget is readded.
        // The extension's refresh intent requests a fresh timeline immediately;
        // it runs in the extension and must not launch the application.
        let refresh = spring.buttons["widget.refresh"]
        if refresh.waitForExistence(timeout: 5) { refresh.tap() }
        else { spring.buttons["Refresh"].firstMatch.tap() }
        XCTAssertTrue(spring.staticTexts["7"].waitForExistence(timeout: 30), "new statistics must arrive with the main process stopped")
        XCTAssertEqual(main.state, .notRunning)
        let last = XCTAttachment(screenshot: spring.screenshot()); last.name = "Widget count 7, main app still stopped"; last.lifetime = .keepAlways; add(last)
        print("WIDGET_FINAL\n" + spring.debugDescription)
    }

    private func addWidget(in spring: XCUIApplication) {
        let homeIcon = spring.icons["Safari"]
        XCTAssertTrue(homeIcon.waitForExistence(timeout: 5))
        homeIcon.press(forDuration: 1.2)
        print("HOME_MENU\n" + spring.debugDescription)
        let editHome = spring.buttons["Edit Home Screen"]
        if editHome.waitForExistence(timeout: 3) { editHome.tap() }
        let edit = spring.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) { edit.tap() }
        let add = spring.buttons["Add Widget"]
        if add.waitForExistence(timeout: 3) { add.tap() }
        else {
            let plural = spring.buttons["Add Widgets"]
            XCTAssertTrue(plural.waitForExistence(timeout: 3)); plural.tap()
        }
        let search = spring.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("still.fail")
        print("WIDGET_SEARCH\n" + spring.debugDescription)
        let app = spring.buttons["still.fail"]
        if app.waitForExistence(timeout: 3) { app.tap() }
        else { spring.staticTexts["still.fail"].firstMatch.tap() }
        print("WIDGET_GALLERY\n" + spring.debugDescription)
        let stats = spring.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Task stats")).firstMatch
        for _ in 0..<10 {
            if stats.exists && stats.isHittable { break }
            let preview = spring.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "still.fail,")).allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(preview, "gallery preview must be visible")
            preview?.swipeLeft()
        }
        XCTAssertTrue(stats.exists && stats.isHittable, "statistics widget must be selected")
        let addWidget = spring.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5)); addWidget.tap()
        let done = spring.buttons["Done"]
        if done.waitForExistence(timeout: 5) { done.tap() }
        print("WIDGET_ADDED\n" + spring.debugDescription)
    }
}
