import XCTest
import UIKit
@testable import StillFail

/// Exercise actual reuse, drawing and self-sizing on a display-linked scroll.
/// Simulator timings are diagnostic data, not a device frame-rate guarantee.
@MainActor
private final class ScrollFrameSampler: NSObject {
    private let scroll: UIScrollView
    private let root: UIView
    private let frameCount: Int
    private var link: CADisplayLink?
    private var completion: CheckedContinuation<Void, Never>?
    private var lastTimestamp: CFTimeInterval?
    private var step = 0
    private var gaps: [Double] = []
    private var layoutTimes: [Double] = []
    init(scroll: UIScrollView, root: UIView, frameCount: Int = 180) {
        self.scroll = scroll; self.root = root; self.frameCount = frameCount
    }
    func run() async {
        scroll.delegate?.scrollViewWillBeginDragging?(scroll)
        await withCheckedContinuation { continuation in
            completion = continuation
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            self.link = link; link.add(to: .main, forMode: .common)
        }
    }
    @objc private func frame(_ link: CADisplayLink) {
        if let lastTimestamp { gaps.append((link.timestamp - lastTimestamp) * 1000) }
        lastTimestamp = link.timestamp
        let started = CACurrentMediaTime()
        let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let distance = min(bottom, max(0, scroll.contentOffset.y + 42))
        scroll.setContentOffset(CGPoint(x: 0, y: distance), animated: false)
        root.layoutIfNeeded()
        layoutTimes.append((CACurrentMediaTime() - started) * 1000)
        step += 1
        if step >= frameCount {
            link.invalidate(); self.link = nil
            completion?.resume(); completion = nil
        }
    }
    var summary: [String: Double] {
        func percentile(_ values: [Double], _ percent: Double) -> Double {
            let ordered = values.sorted()
            guard !ordered.isEmpty else { return 0 }
            return ordered[min(ordered.count - 1, Int(Double(ordered.count - 1) * percent))]
        }
        return ["frames": Double(step), "frame_gap_p50_ms": percentile(gaps, 0.5), "frame_gap_p95_ms": percentile(gaps, 0.95),
                "main_layout_p50_ms": percentile(layoutTimes, 0.5), "main_layout_p95_ms": percentile(layoutTimes, 0.95),
                "main_layout_max_ms": layoutTimes.max() ?? 0,
                "gaps_over_33ms": Double(gaps.filter { $0 > 33.5 }.count)]
    }
}

@MainActor
final class NativeScrollingPerformanceTests: XCTestCase {
    private func document(_ index: Int) -> String {
        """
        ## Checkpoint \(index)

        Review the **native rendering path** while a long conversation is scrolling.

        - Keep completed documents available for reuse.
        - Measure each width only when its content changes.

        | Component | Status | Count |
        | --- | --- | --- |
        | Timeline | Native | \(index) |
        | History | Reused | 700 |

        ```swift
        struct Result {
            let index = \(index)
            let cache = "bounded"
        }
        ```

        > Native selection, tables, code and paragraphs should stay responsive.
        """
    }

    func testContinuousRichConversationAndExecutionHistoryScrolling() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.screen.bounds
        defer { window.isHidden = true; previous?.makeKey() }
        var metrics: [String: [String: Double]] = [:]

        let chat = ChatTimelineController()
        window.rootViewController = chat; window.makeKeyAndVisible()
        let rows = (0..<700).map { index in
            ChatTimelineRow(id: "rich:\(index)", kind: .message, value: .object([
                "seq": .number(Double(index)), "authorKind": .string("agent"), "author": .string("agent"),
                "by": .object(["name": .string("GPT-6"), "maker": .object(["id": .string("openai")])]),
                "text": .string(document(index))]))
        }
        chat.update(rows, language: "en", initialSeq: 0, initialOffset: 0)
        try await Task.sleep(for: .milliseconds(600))
        let collection = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? UICollectionView }.first)
        print("NATIVE_SCROLL_PROFILE_READY")
        try await Task.sleep(for: .seconds(2))
        let chatSampler = ScrollFrameSampler(scroll: collection, root: chat.view)
        await chatSampler.run(); metrics["conversation"] = chatSampler.summary
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 700)
        XCTAssertLessThan(collection.visibleCells.count, 40)
        XCTAssertGreaterThan(collection.contentOffset.y, 1000, "The test must scroll across actual rich documents")

        let history = HistoryTimelineController()
        window.rootViewController = history; window.makeKeyAndVisible()
        let items: [JSONValue] = (0..<700).map { index in
            .object(["key": .string("history:\(index)"), "body": .object(["kind": .string("text"), "content": .object(["text": .string(document(index))])])])
        }
        history.update(.object(["loaded": .bool(true), "items": .array(items), "live": .array([]), "usage": .array([])]), language: "en")
        try await Task.sleep(for: .milliseconds(600))
        let historySampler = ScrollFrameSampler(scroll: history.table, root: history.view)
        await historySampler.run(); metrics["execution_history"] = historySampler.summary
        XCTAssertLessThan(history.table.visibleCells.count, 40)
        XCTAssertGreaterThan(history.table.contentOffset.y, 1000)

        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "native-scroll-metrics"; attachment.lifetime = .keepAlways; add(attachment)
        print("NATIVE_SCROLL_METRICS \(String(decoding: data, as: UTF8.self))")
    }
}
