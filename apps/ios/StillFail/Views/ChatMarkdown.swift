import SwiftUI
import UIKit
import CoreText
import Litext
import MarkdownParser
import MarkdownView

/// Parsing is shared and bounded; live text never parses on the scrolling thread.
private final class MarkdownParseCache: @unchecked Sendable {
    final class Entry { let parsed: MarkdownParser.ParseResult; init(_ parsed: MarkdownParser.ParseResult) { self.parsed = parsed } }
    static let shared = MarkdownParseCache()
    let queue = DispatchQueue(label: "fail.still.markdown", qos: .userInitiated)
    private let cache = NSCache<NSString, Entry>()
    private let prefetchLock = NSLock()
    private var prefetched: Set<String> = []
    private init() { cache.countLimit = 128; cache.totalCostLimit = 8 * 1024 * 1024 }
    func cached(_ text: String) -> MarkdownParser.ParseResult? { cache.object(forKey: text as NSString)?.parsed }
    func parse(_ text: String) -> MarkdownParser.ParseResult {
        if let cached = cache.object(forKey: text as NSString) { return cached.parsed }
        let parsed = MarkdownParser().parse(text)
        cache.setObject(Entry(parsed), forKey: text as NSString, cost: text.utf8.count)
        return parsed
    }
    func prefetch(_ text: String) {
        // A few upcoming documents, not the full history. Large outputs retain
        // their normal visible-row path and never delay live parsing behind a backlog.
        guard !text.isEmpty, text.utf8.count <= 32 * 1024, cached(text) == nil else { return }
        prefetchLock.lock()
        guard prefetched.count < 8, prefetched.insert(text).inserted else { prefetchLock.unlock(); return }
        prefetchLock.unlock()
        queue.async {
            _ = self.parse(text)
            self.prefetchLock.lock(); self.prefetched.remove(text); self.prefetchLock.unlock()
        }
    }

}

enum MarkdownPrefetch {
    static func prepare(_ texts: [String]) { texts.forEach { MarkdownParseCache.shared.prefetch($0) } }
    static func isPrepared(_ text: String) -> Bool { MarkdownParseCache.shared.cached(text) != nil }
}

/// Math images and code highlight setup are part of rendering, not parsing.
/// Retain those results independently of a cell so an evicted view can reuse them.
@MainActor private final class MarkdownContentCache {
    final class Entry {
        let theme: MarkdownTheme; let content: MarkdownContent
        init(theme: MarkdownTheme, content: MarkdownContent) { self.theme = theme; self.content = content }
    }
    static let shared = MarkdownContentCache()
    private let cache = NSCache<NSString, Entry>()
    private init() { cache.countLimit = 128; cache.totalCostLimit = 12 * 1024 * 1024 }
    func content(text: String, parsed: MarkdownParser.ParseResult, theme: MarkdownTheme, reusable: Bool) -> MarkdownContent {
        if reusable, let entry = cache.object(forKey: text as NSString), entry.theme == theme { return entry.content }
        let content = MarkdownContent(blocks: parsed.document, rendered: parsed.renderedContent(theme: theme), highlightMaps: parsed.highlightMaps(theme: theme))
        if reusable { cache.setObject(Entry(theme: theme, content: content), forKey: text as NSString, cost: max(1024, text.utf8.count * 4)) }
        return content
    }
}

/// Close only incomplete inline delimiters in the live tail. GFM already renders
/// unfinished fenced code at EOF; changing that source would damage code content.
enum MarkdownStreamingRepair {
    static func repair(_ text: String) -> String {
        var fence: (Character, Int)?
        for line in text.components(separatedBy: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            while trimmed.hasPrefix(">") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let marker = trimmed.range(of: #"^(?:[-+*]|\d+[.)])\s+"#, options: .regularExpression) { trimmed.removeSubrange(marker) }
            guard let marker = trimmed.first, marker == "`" || marker == "~" else { continue }
            let count = trimmed.prefix(while: { $0 == marker }).count
            guard count >= 3 else { continue }
            if let active = fence {
                if active.0 == marker, count >= active.1, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else { fence = (marker, count) }
        }
        if fence != nil { return text }
        let tail = text.components(separatedBy: "\n\n").last ?? text
        let chars = Array(tail)
        var delimiters: [String] = [], i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\\" { i += 2; continue }
            if !["`", "*", "_", "~", "$"].contains(char) { i += 1; continue }
            // Asterisks introducing list items and underscores inside words are
            // ordinary source characters, not open emphasis.
            if char == "*", (i == 0 || chars[i - 1] == "\n"), i + 1 < chars.count, chars[i + 1] == " " { i += 1; continue }
            if char == "_", i > 0, i + 1 < chars.count, chars[i - 1].isLetter, chars[i + 1].isLetter { i += 1; continue }
            var end = i + 1
            while end < chars.count && chars[end] == char { end += 1 }
            let token = String(chars[i..<end])
            if delimiters.last?.hasPrefix("`") == true && char != "`" { i = end; continue }
            if (char == "~" || char == "$") && token.count < 2 { i = end; continue }
            if delimiters.last == token { delimiters.removeLast() } else { delimiters.append(token) }
            i = end
        }
        var result = text + delimiters.reversed().joined()
        if result.range(of: #"\[[^\]\n]+\]\([^\)\n]*$"#, options: .regularExpression) != nil { result += ")" }
        return result
    }
}

/// Each tick redraws only the appended glyphs; it never rebuilds text or layout.
private final class StreamingTextLayout: TextLabel.Layout {
    var appendedRange: () -> NSRange = { NSRange(location: 0, length: 0) }
    var began: () -> CFTimeInterval = { 0 }
    override func draw(line: CTLine, at index: Int, in context: CGContext) {
        let range = appendedRange(), elapsed = CACurrentMediaTime() - began()
        guard range.length > 0, elapsed < 0.38 else { CTLineDraw(line, context); return }
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            func alpha(_ glyph: Int) -> CGFloat {
                let at = indices[glyph]
                guard NSLocationInRange(at, range) else { return 1 }
                let delay = min(0.16, Double(at - range.location) * 0.005)
                return CGFloat(max(0, min(1, (elapsed - delay) / 0.22)))
            }
            var start = 0, opacity = alpha(0)
            for glyph in 1...count {
                let next = glyph < count ? alpha(glyph) : -1
                if next == opacity { continue }
                context.saveGState(); context.setAlpha(opacity)
                CTRunDraw(run, context, CFRange(location: start, length: glyph - start))
                context.restoreGState()
                start = glyph; opacity = next
            }
        }
    }
}

private final class StreamingTextLabel: TextLabelView {
    var animateNext = false
    private var appended = NSRange(location: 0, length: 0)
    private var began: CFTimeInterval = 0
    private var ticker: CADisplayLink?
    private weak var drawingLayout: StreamingTextLayout?
    private var dirtyRect: CGRect?
    private var dirtySize: CGSize = .zero
    override var attributedText: NSAttributedString {
        didSet {
            ticker?.invalidate(); ticker = nil; dirtyRect = nil
            guard animateNext, window != nil, !UIAccessibility.isReduceMotionEnabled else { appended.length = 0; return }
            let old = oldValue.string, new = attributedText.string
            let prefix = zip(old, new).prefix(while: { pair in pair.0 == pair.1 }).map { String($0.0) }.joined().utf16.count
            appended = NSRange(location: prefix, length: max(0, attributedText.length - prefix)); began = CACurrentMediaTime()
            guard appended.length > 0 else { return }
            // A fade of a fraction of a second reads the same at 30 fps; a 60 Hz timer
            // per streaming block kept CoreText redrawing for the whole stream.
            let link = CADisplayLink(target: StreamingTick(self), selector: #selector(StreamingTick.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            ticker = link
        }
    }
    fileprivate func tick() {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled, CACurrentMediaTime() - began < 0.4 else {
            ticker?.invalidate(); ticker = nil; appended.length = 0; setNeedsDisplay(); return
        }
        redrawAppend()
    }
    override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
        let layout = StreamingTextLayout(attributedString: attributedText)
        drawingLayout = layout
        layout.appendedRange = { [weak self] in self?.appended ?? NSRange(location: 0, length: 0) }
        layout.began = { [weak self] in self?.began ?? 0 }
        return layout
    }
    private func redrawAppend() {
        guard let layout = drawingLayout, layout.containerSize == bounds.size else { setNeedsDisplay(); return }
        if dirtyRect == nil || dirtySize != bounds.size {
            dirtySize = bounds.size
            let area = layout.rects(for: appended).reduce(CGRect.null) { $0.union($1) }
            if !area.isNull { dirtyRect = CGRect(x: 0, y: bounds.height - area.maxY - 4, width: bounds.width, height: area.height + 8).intersection(bounds) }
        }
        if let dirtyRect { setNeedsDisplay(dirtyRect) } else { setNeedsDisplay() }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { ticker?.invalidate(); ticker = nil; appended.length = 0 }
    }
    deinit { ticker?.invalidate() }
}

/// The display link retains its target; this keeps the label free to deallocate.
private final class StreamingTick: NSObject {
    weak var label: StreamingTextLabel?
    init(_ label: StreamingTextLabel) { self.label = label }
    @objc func tick(_ link: CADisplayLink) {
        guard let label else { link.invalidate(); return }
        MainActor.assumeIsolated { label.tick() }
    }
}

/// MarkdownTextView eagerly asks for layout during content replacement. A new
/// cell does not have its final bounds yet; do not typeset against zero width and
/// then typeset the whole document a second time after the cell is measured.
private final class DeferredMarkdownTextView: MarkdownTextView {
    var replacingContent = false
    override func layoutSubviews() {
        guard !replacingContent, bounds.width > 0, bounds.height > 1 else { return }
        super.layoutSubviews()
    }
}

/// The same CoreText renderer as lody-ios. Unchanged live blocks keep their native
/// views and selection/layout, while code, tables, task lists and math stay native.
final class NativeMarkdownView: UIView {
    private struct Block {
        var node: MarkdownBlockNode
        let label: StreamingTextLabel
        let view: MarkdownTextView
    }
    private var blocks: [Block] = []
    private var source = ""
    private var streaming = false
    private var request = 0
    private var parsing = false
    private var parsed: MarkdownParser.ParseResult?
    private var parsedRequest = -1
    private var renderedTheme: MarkdownTheme?
    private var renderedRequest = -1
    private var renderedFontCategory: UIContentSizeCategory?
    private var renderedInterfaceStyle: UIUserInterfaceStyle?
    private var measurements: [CGFloat: [CGFloat]] = [:]
    private var widthMeasurements: [CGFloat: CGFloat] = [:]
    // Counts real work (not layout requests), used by scrolling regression tests.
    private(set) var documentBuildCount = 0
    private(set) var measurementCount = 0
    var measuredWidths: [CGFloat] { Array(measurements.keys) }
    var renderedPlainText: String { blocks.map { $0.label.attributedText.string }.joined(separator: "\n") }
    var cacheSource: String { source }
    var renderingMemoryEstimate: Int {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : UIScreen.main.scale
        let pixels = max(0, bounds.width) * max(0, bounds.height) * scale * scale
        return min(24 * 1024 * 1024, max(8_192, Int(pixels * 4) + source.utf8.count * 24))
    }
    var hasRenderedContent: Bool { renderedRequest >= 0 && (renderedRequest == request || streaming) && !blocks.isEmpty }
    var canCache: Bool { !streaming && hasRenderedContent && !parsing }
    var onHeightChange: (() -> Void)?
    weak var trackedScrollView: UIScrollView? { didSet { blocks.forEach { $0.view.trackedScrollView = trackedScrollView } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (view: NativeMarkdownView, _: UITraitCollection) in view.render() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(text: String, streaming: Bool = false) {
        guard source != text || self.streaming != streaming || (parsed == nil && !parsing) else {
            // A pooled view may move into a different Dynamic Type / appearance
            // environment before its registered trait callback is delivered.
            if renderedFontCategory != traitCollection.preferredContentSizeCategory || renderedInterfaceStyle != traitCollection.userInterfaceStyle { render() }
            return
        }
        if source != text && !streaming {
            // A warm renderer can serve a different message. Its native code/table
            // views stay reusable, but its old message must never flash while parsing.
            blocks.forEach { $0.view.isHidden = true }
        }
        source = text; self.streaming = streaming; request += 1
        if !parsing {
            if !streaming, let cached = MarkdownParseCache.shared.cached(text) {
                parsed = cached; parsedRequest = request; render()
            } else { parseLatest() }
        }
    }
    private func parseLatest() {
        parsing = true
        let expected = request, text = source, live = streaming
        // At most one parse is in flight per row. Fast token arrivals coalesce to
        // the latest source, rather than building a queue of obsolete documents.
        MarkdownParseCache.shared.queue.async { [weak self] in
            let parsed = MarkdownParseCache.shared.parse(live ? MarkdownStreamingRepair.repair(text) : text)
            DispatchQueue.main.async {
                guard let self else { return }
                self.parsing = false
                guard self.request == expected else { self.parseLatest(); return }
                self.parsed = parsed; self.parsedRequest = expected; self.render()
            }
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, trackedScrollView == nil {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView { trackedScrollView = scroll; break }
                ancestor = view.superview
            }
        }
    }
    func clear() {
        request += 1; source = ""; parsed = nil; parsedRequest = -1; renderedRequest = -1; measurements.removeAll(); widthMeasurements.removeAll()
        blocks.forEach { $0.view.removeFromSuperview() }; blocks = []
        invalidateIntrinsicContentSize()
    }
    override func tintColorDidChange() { super.tintColorDidChange(); render() }
    private func render() {
        guard let parsed, parsedRequest == request else { return }
        renderedFontCategory = traitCollection.preferredContentSizeCategory
        renderedInterfaceStyle = traitCollection.userInterfaceStyle
        var theme = MarkdownTheme()
        theme.fonts.body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        theme.align(to: theme.fonts.body.pointSize)
        theme.spacings.final = 0; theme.spacings.paragraph = 10; theme.spacings.headingBefore = 10
        // Headings step up from the body instead of rendering as bold body text.
        let body = theme.fonts.body.pointSize
        theme.fonts.title = UIFont.systemFont(ofSize: round(body * 1.15), weight: .semibold)
        theme.fonts.largeTitle = UIFont.systemFont(ofSize: round(body * 1.3), weight: .bold)
        theme.colors.highlight = tintColor; theme.colors.emphasis = .label
        guard renderedRequest != request || renderedTheme != theme else { return }
        documentBuildCount += 1
        measurements.removeAll(); widthMeasurements.removeAll()
        let context = MarkdownContentCache.shared.content(text: source, parsed: parsed, theme: theme, reusable: !streaming)
        // Completed documents use one selection span. Streams isolate blocks to
        // avoid rebuilding completed paragraphs for every appended token.
        let nodes = streaming ? parsed.document : Array(parsed.document.prefix(1))
        let sameTheme = renderedTheme == theme
        while blocks.count > nodes.count { blocks.removeLast().view.removeFromSuperview() }
        for (index, node) in nodes.enumerated() {
            let isNew = index == blocks.count
            if isNew {
                let label = StreamingTextLabel()
                let view = DeferredMarkdownTextView(textLabelView: label)
                view.throttleInterval = nil; view.trackedScrollView = trackedScrollView
                view.linkHandler = { payload, _, _ in
                    let url: URL?
                    switch payload { case .url(let value): url = value; case .string(let value): url = URL(string: value) }
                    if let url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
                }
                blocks.append(Block(node: node, label: label, view: view)); addSubview(view)
            } else if blocks[index].node == node && sameTheme && streaming { continue }
            let block = blocks[index]
            block.label.animateNext = streaming && !isNew && !UIAccessibility.isReduceMotionEnabled
            let content = streaming ? MarkdownContent(blocks: [node], rendered: context.rendered, highlightMaps: context.highlightMaps) : context
            UIView.performWithoutAnimation {
                (block.view as? DeferredMarkdownTextView)?.replacingContent = true
                block.view.setContentImmediately(content, theme: theme)
                (block.view as? DeferredMarkdownTextView)?.replacingContent = false
                block.view.setNeedsLayout()
            }
            if isNew && streaming && window != nil && !UIAccessibility.isReduceMotionEnabled {
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.18; block.view.layer.add(fade, forKey: "stream")
            }
            blocks[index].node = node
            blocks[index].view.isHidden = false
        }
        renderedTheme = theme; renderedRequest = request
        invalidateIntrinsicContentSize(); setNeedsLayout(); onHeightChange?()
    }
    private func blockHeights(width: CGFloat) -> [CGFloat] {
        let width = max(1, width)
        if let heights = measurements[width] { return heights }
        measurementCount += 1
        let heights = blocks.map { ceil($0.view.boundingSize(for: width).height) }
        // iPad rotation / split resizing should not grow an unbounded width cache.
        if measurements.count >= 4 { measurements.removeAll(keepingCapacity: true) }
        measurements[width] = heights
        return heights
    }
    /// The widest laid-out line when wrapped at `maxWidth`, for bubbles that hug their text.
    func measuredWidth(maxWidth: CGFloat) -> CGFloat {
        guard hasRenderedContent else { return 0 }
        let maxWidth = max(1, maxWidth)
        if let width = widthMeasurements[maxWidth] { return width }
        let width = min(maxWidth, blocks.map { ceil($0.view.boundingSize(for: maxWidth).width) }.max() ?? 0)
        if widthMeasurements.count >= 4 { widthMeasurements.removeAll(keepingCapacity: true) }
        widthMeasurements[maxWidth] = width
        return width
    }
    func measuredHeight(width: CGFloat) -> CGFloat {
        guard hasRenderedContent else { return 0 }
        let heights = blockHeights(width: width)
        return heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 12
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight(width: bounds.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard hasRenderedContent else { return }
        let heights = blockHeights(width: bounds.width)
        var y: CGFloat = 0
        for (index, block) in blocks.enumerated() {
            if index > 0 { y += 12 }
            let frame = CGRect(x: 0, y: y, width: bounds.width, height: heights[index])
            if block.view.frame != frame { block.view.frame = frame }
            y += heights[index]
        }
    }

}

/// A cell returning to the viewport retains its native CoreText layout, code / table
/// views and math images. Parse caching alone cannot avoid rebuilding these on main.
/// Only detached, completed documents are pooled; a live view has exactly one owner.
@MainActor final class NativeMarkdownReusePool {
    static let shared = NativeMarkdownReusePool()
    private struct Entry { let view: NativeMarkdownView; let cost: Int; let access: Int }
    private var entries: [String: [Entry]] = [:]
    private var clock = 0
    private var totalCost = 0
    private var memoryObserver: NSObjectProtocol?
    private let countLimit = 48
    private let costLimit = 24 * 1024 * 1024
    private(set) var hitCount = 0
    private(set) var missCount = 0
    private(set) var warmReuseCount = 0
    init() {
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }
    deinit { if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) } }
    func take(text: String) -> NativeMarkdownView {
        if var matching = entries[text], let entry = matching.popLast() {
            if matching.isEmpty { entries.removeValue(forKey: text) } else { entries[text] = matching }
            totalCost -= entry.cost; hitCount += 1
            return entry.view
        }
        missCount += 1
        // Exact document hits preserve all measured lines. On a miss, reusing the
        // oldest detached renderer preserves the heavyweight UIKit selection
        // interactions and table/code cell managers instead of allocating them
        // for every unique message during a cold scroll.
        if let reusable = entries.flatMap({ key, values in values.enumerated().map { (key, $0.offset, $0.element) } }).min(by: { $0.2.access < $1.2.access }) {
            entries[reusable.0]?.remove(at: reusable.1)
            if entries[reusable.0]?.isEmpty == true { entries.removeValue(forKey: reusable.0) }
            totalCost -= reusable.2.cost; warmReuseCount += 1
            return reusable.2.view
        }
        return NativeMarkdownView(frame: .zero)
    }
    func put(_ view: NativeMarkdownView) {
        view.onHeightChange = nil; view.trackedScrollView = nil; view.removeFromSuperview()
        guard view.canCache, !view.cacheSource.isEmpty else { return }
        // Account for attributed runs and CoreText/table backing storage, not source alone.
        let cost = view.renderingMemoryEstimate
        guard cost <= costLimit / 2 else { return }
        clock += 1
        entries[view.cacheSource, default: []].append(Entry(view: view, cost: cost, access: clock)); totalCost += cost
        while entries.values.reduce(0, { $0 + $1.count }) > countLimit || totalCost > costLimit {
            guard let oldest = entries.flatMap({ key, values in values.enumerated().map { (key, $0.offset, $0.element) } }).min(by: { $0.2.access < $1.2.access }) else { break }
            entries[oldest.0]?.remove(at: oldest.1); totalCost -= oldest.2.cost
            if entries[oldest.0]?.isEmpty == true { entries.removeValue(forKey: oldest.0) }
        }
    }
    func removeAll() { entries.removeAll(); totalCost = 0 }
}

struct MarkdownMessage: UIViewRepresentable {
    let text: String
    var streaming = false
    @State private var revision = 0
    func makeUIView(context: Context) -> NativeMarkdownView {
        let view = NativeMarkdownView(frame: .zero)
        view.onHeightChange = { DispatchQueue.main.async { revision += 1 } }
        return view
    }
    func updateUIView(_ uiView: NativeMarkdownView, context: Context) { _ = revision; uiView.update(text: text, streaming: streaming) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeMarkdownView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: max(1, uiView.measuredHeight(width: width)))
    }
}
