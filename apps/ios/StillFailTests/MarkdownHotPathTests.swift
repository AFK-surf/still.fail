import XCTest
import UIKit
@testable import StillFail

final class MarkdownHotPathTests: XCTestCase {
    private let mixed = """
    ## A rendered document
    中文段落 with **emphasis**, `inline code`, and [a link](https://example.com).

    | Name | State |
    | :--- | ---: |
    | Parser | Ready |

    ```swift
    let updates = messages.filter { !$0.isEmpty }
    print(updates.count)
    ```

    > A quoted paragraph that wraps over several lines, without a second layout pass on every scroll.
    """
    @MainActor func testMeasuredDocumentReturnsFromReuseWithNativeLayoutIntact() async throws {
        let pool = NativeMarkdownReusePool()
        let view = pool.take(text: mixed)
        view.frame = CGRect(x: 0, y: 0, width: 358, height: 1000)
        view.update(text: mixed)
        try await Task.sleep(nanoseconds: 200_000_000)
        let height = view.measuredHeight(width: 358)
        XCTAssertGreaterThan(height, 100)
        view.frame.size.height = height
        let builds = view.documentBuildCount, measurements = view.measurementCount
        for _ in 0..<30 { XCTAssertEqual(view.measuredHeight(width: 358), height); view.setNeedsLayout(); view.layoutIfNeeded() }
        XCTAssertEqual(view.measurementCount, measurements, "Scrolling and self-sizing must reuse the measured width rather than typeset again")
        pool.put(view)
        let returning = pool.take(text: mixed)
        XCTAssertTrue(returning === view, "A returning cell should reuse its real code/table/CoreText views, not only its parse result")
        returning.update(text: mixed)
        XCTAssertEqual(returning.documentBuildCount, builds)
        XCTAssertEqual(returning.measuredHeight(width: 358), height)
        XCTAssertEqual(returning.measurementCount, measurements)
        _ = returning.measuredHeight(width: 700)
        XCTAssertEqual(returning.measurementCount, measurements + 1, "A changed iPad column width genuinely needs a new measurement")
    }
    @MainActor func testCompletedAndLiveDocumentsNeverHaveTwoOwners() async throws {
        let pool = NativeMarkdownReusePool()
        let first = pool.take(text: mixed)
        first.update(text: mixed)
        try await Task.sleep(nanoseconds: 150_000_000)
        let simultaneous = pool.take(text: mixed)
        XCTAssertFalse(first === simultaneous)
        first.update(text: mixed + "\n\nLive tail", streaming: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        pool.put(first)
        XCTAssertFalse(pool.take(text: mixed + "\n\nLive tail") === first, "A still-streaming renderer must not enter the completed view pool")
    }
    @MainActor func testColdScrollReusesNativeTableAndCodeViewsAcrossDifferentDocuments() async throws {
        let pool = NativeMarkdownReusePool(), original = pool.take(text: mixed)
        original.frame = CGRect(x: 0, y: 0, width: 358, height: 1)
        original.update(text: mixed)
        try await Task.sleep(nanoseconds: 150_000_000)
        original.frame.size.height = original.measuredHeight(width: 358)
        original.layoutIfNeeded()
        func nativeContexts(_ root: UIView) -> [String: ObjectIdentifier] {
            var result: [String: ObjectIdentifier] = [:]
            func visit(_ view: UIView) {
                let name = String(describing: type(of: view))
                if name == "TableView" || name == "CodeView" { result[name] = ObjectIdentifier(view) }
                view.subviews.forEach(visit)
            }
            visit(root); return result
        }
        let before = nativeContexts(original)
        XCTAssertNotNil(before["TableView"]); XCTAssertNotNil(before["CodeView"])
        pool.put(original)
        let different = mixed.replacingOccurrences(of: "Ready", with: "Reused") + "\n\nDifferent message " + UUID().uuidString
        let returning = pool.take(text: different)
        XCTAssertTrue(returning === original)
        XCTAssertEqual(pool.warmReuseCount, 1)
        returning.update(text: different)
        XCTAssertFalse(returning.hasRenderedContent, "An unrelated old message must stay hidden until the new source has parsed")
        try await Task.sleep(nanoseconds: 150_000_000)
        returning.frame.size.height = returning.measuredHeight(width: 358); returning.layoutIfNeeded()
        XCTAssertTrue(returning.renderedPlainText.contains("Different message"))
        XCTAssertEqual(nativeContexts(returning), before, "Cold scrolling should retain UIKit's expensive table/code selection interactions across unique documents")
    }
    @MainActor func testCachedMeasurementsInvalidateForDynamicType() async throws {
        // Detached UIViews do not resolve traitOverrides into inherited traits.
        // Exercise a real window environment, just as a reused on-screen cell does.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), host = UIViewController()
        window.frame = scene.screen.bounds; window.rootViewController = host
        host.traitOverrides.preferredContentSizeCategory = .large
        let view = NativeMarkdownView(frame: CGRect(x: 0, y: 0, width: 358, height: 1000))
        host.view.addSubview(view); window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        window.layoutIfNeeded(); view.update(text: mixed)
        try await Task.sleep(nanoseconds: 150_000_000)
        let height = view.measuredHeight(width: 358), builds = view.documentBuildCount
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        window.setNeedsLayout(); window.layoutIfNeeded()
        view.update(text: mixed)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraLarge)
        XCTAssertGreaterThan(view.documentBuildCount, builds)
        XCTAssertGreaterThan(view.measuredHeight(width: 358), height, "A cached width must not return old typography after the accessibility font changes")
    }
    @MainActor func testPrefetchedStaticDocumentAvoidsPendingPreviewAndSecondHeightPass() async throws {
        let text = mixed + "\n\nPrefetched " + UUID().uuidString
        MarkdownPrefetch.prepare([text, text, text])
        for _ in 0..<20 where !MarkdownPrefetch.isPrepared(text) { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(MarkdownPrefetch.isPrepared(text))
        let view = NativeMarkdownView(frame: CGRect(x: 0, y: 0, width: 358, height: 1))
        view.update(text: text)
        XCTAssertTrue(view.hasRenderedContent, "The entering row can use its warm native renderer immediately, without raw preview then async self-sizing")
        XCTAssertEqual(view.documentBuildCount, 1)
    }
    func testClosedHistoryGroupDoesNotMaterializeToolResultsOrThinking() {
        let value: JSONValue = .object(["loaded": .bool(true), "items": .array([
            .object(["key": .string("group"), "body": .object(["kind": .string("group"), "content": .object([
                "summary": .string("Read files"), "thinking": .array([.object(["text": .string(String(repeating: "thought ", count: 10_000))])]),
                "steps": .array([.object(["name": .string("read"), "call": .string("{\"path\":\"a.swift\"}"), "result": .string(String(repeating: "result ", count: 10_000))])])
            ])])])
        ])])
        let closed = HistoryTimeline.rows(value: value, expanded: [])
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.kind, .disclosure)
        XCTAssertFalse(closed.contains { $0.kind == .markdown })
        let groupID = try! XCTUnwrap(closed.first?.id)
        let expanded = HistoryTimeline.rows(value: value, expanded: [groupID])
        XCTAssertEqual(expanded.count, 3, "Opening a group shows child summaries, without formatting all of their bodies")
        XCTAssertFalse(expanded.contains { $0.kind == .markdown })
        let toolID = try! XCTUnwrap(expanded.last?.id)
        let tool = HistoryTimeline.rows(value: value, expanded: [groupID, toolID])
        XCTAssertEqual(tool.filter { $0.kind == .markdown }.count, 2)
        XCTAssertEqual(tool.last?.toolName, "read")
    }
}
