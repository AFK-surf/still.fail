import SwiftUI
import UIKit

struct HistoryTimelineRow: Equatable, Identifiable {
    enum Kind: Equatable { case markdown, disclosure, notice, older, loading, empty, usage }
    let id: String
    let kind: Kind
    var text = ""
    var title = ""
    var detail = ""
    var symbol = ""
    var place: JSONValue = .null
    var depth = 0
    var expanded = false
    var streaming = false
    var failed = false
    var toolName: String? = nil
    /// For a tool step's result: the call it answers (its arguments name the file it read).
    var toolCall: String? = nil
    var toolFailed = false
    var toolSaid = false
}

/// Closed groups never construct their Markdown views. Expanded content is split
/// into independently reusable rows, rather than a huge SwiftUI self-sizing tree.
enum HistoryTimeline {
    static func rows(value: JSONValue, expanded: Set<String>) -> [HistoryTimelineRow] {
        var rows: [HistoryTimelineRow] = []
        if value.flag("more") { rows.append(HistoryTimelineRow(id: "older", kind: .older, title: L10n.text("加载更早的记录"))) }
        if !value.flag("loaded") { rows.append(HistoryTimelineRow(id: "loading", kind: .loading, title: L10n.text("正在读取执行历史…"))) }
        if !value.text("edge").isEmpty { rows.append(HistoryTimelineRow(id: "edge", kind: .notice, title: L10n.projected(value.text("edge")))) }
        if value.flag("empty") { rows.append(HistoryTimelineRow(id: "empty", kind: .empty, title: L10n.text("暂无执行历史"), symbol: "list.bullet.rectangle")) }
        for record in ViewRecord.decode(value["items"].arrayValue, key: "key") {
            let item = record.value, content = item["body"]["content"], id = "item:\(record.id)"
            switch item["body"].text("kind") {
            case "received":
                if !content.text("note").isEmpty { rows.append(HistoryTimelineRow(id: id + ":note", kind: .markdown, text: content.text("note"), title: "StillFail", symbol: "arrow.down.left")) }
                for message in ViewRecord.decode(content["messages"].arrayValue, key: "key") {
                    rows.append(HistoryTimelineRow(id: id + ":received:\(message.id)", kind: .markdown, text: message.value.text("text"), title: message.value["from"].text("name"), symbol: "arrow.down.left", place: message.value["place"]))
                }
            case "text":
                rows.append(HistoryTimelineRow(id: id, kind: .markdown, text: content.text("text"), title: content.flag("subagent") ? L10n.text("协同 agent") : "", symbol: content.flag("subagent") ? "person.2" : ""))
            case "post":
                let detail = content.flag("failed") ? L10n.text("发送失败") : content.flag("block") ? L10n.text("等待回复") : ""
                rows.append(HistoryTimelineRow(id: id, kind: .markdown, text: content.text("text"), title: L10n.text("发送到"), detail: detail, symbol: "arrow.up.right", place: content["place"], failed: content.flag("failed")))
            case "mark":
                rows.append(HistoryTimelineRow(id: id, kind: .notice, title: content.text("text"), symbol: content["wait"].objectValue.isEmpty ? "bookmark" : "hourglass"))
            case "group":
                var details = [L10n.projected(content.text("title"))].filter { !$0.isEmpty }
                if let failures = content["failures"].intValue, failures > 0 { details.append(L10n.format("%d 项失败", failures)) }
                if let pending = content["pending"].intValue, pending > 0 { details.append(L10n.format("%d 项进行中", pending)) }
                rows.append(HistoryTimelineRow(id: id, kind: .disclosure, title: L10n.projected(content.text("summary", fallback: L10n.text("工具调用"))), detail: details.joined(separator: " · "), symbol: "terminal", expanded: expanded.contains(id), failed: (content["failures"].intValue ?? 0) > 0))
                guard expanded.contains(id) else { continue }
                for thought in ViewRecord.decode(content["thinking"].arrayValue) {
                    let thoughtID = id + ":thinking:\(thought.id)"
                    rows.append(HistoryTimelineRow(id: thoughtID, kind: .disclosure, title: thought.value.text("first", fallback: L10n.text("思考")), symbol: "brain", depth: 1, expanded: expanded.contains(thoughtID)))
                    if expanded.contains(thoughtID) { rows.append(HistoryTimelineRow(id: thoughtID + ":body", kind: .markdown, text: thought.value.text("text"), depth: 2)) }
                }
                for (index, step) in content["steps"].arrayValue.enumerated() {
                    let stepID = id + ":step:\(index)"
                    let details = [step.text("hint"), L10n.projected(step.text("meta"))].filter { !$0.isEmpty }.joined(separator: "\n")
                    rows.append(HistoryTimelineRow(id: stepID, kind: .disclosure, title: step.text("said", fallback: step.text("name", fallback: L10n.text("工具调用"))), detail: details, symbol: step.flag("failed") ? "exclamationmark.circle" : "terminal", depth: 1, expanded: expanded.contains(stepID), failed: step.flag("failed")))
                    if expanded.contains(stepID) {
                        rows.append(HistoryTimelineRow(id: stepID + ":call", kind: .markdown, text: step.text("call"), depth: 2, toolName: step.text("name"), toolSaid: step["said"].stringValue != nil))
                        if let result = step["result"].stringValue { rows.append(HistoryTimelineRow(id: stepID + ":result", kind: .markdown, text: result, depth: 2, toolName: step.text("name"), toolCall: step.text("call"), toolFailed: step.flag("failed"))) }
                    }
                }
            default:
                if !content.text("text").isEmpty { rows.append(HistoryTimelineRow(id: id, kind: .markdown, text: content.text("text"))) }
            }
        }
        for record in ViewRecord.decode(value["live"].arrayValue) {
            rows.append(HistoryTimelineRow(id: "live:\(record.id)", kind: .markdown, text: record.value.text("text"), streaming: true))
        }
        if !value["phase"].text("text").isEmpty { rows.append(HistoryTimelineRow(id: "phase", kind: .notice, title: L10n.projected(value["phase"].text("text")), symbol: "circle.dotted")) }
        if !value["usage"].arrayValue.isEmpty {
            rows.append(HistoryTimelineRow(id: "usage.header", kind: .notice, title: L10n.text("上下文与用量")))
            for record in ViewRecord.decode(value["usage"].arrayValue, key: "label") {
                rows.append(HistoryTimelineRow(id: "usage:\(record.id)", kind: .usage, title: L10n.projected(record.value.text("label")), detail: L10n.projected(record.value.text("value"))))
            }
        }
        return rows
    }
}

struct HistoryMessageList: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let value: JSONValue
    let busy: Bool
    let older: () -> Void
    func makeUIViewController(context: Context) -> HistoryTimelineController { HistoryTimelineController() }
    func updateUIViewController(_ controller: HistoryTimelineController, context: Context) {
        controller.older = older
        controller.update(value, language: locale.identifier, busy: busy)
    }
}

final class HistoryTimelineController: UIViewController, UITableViewDelegate {
    let table = UITableView(frame: .zero, style: .plain)
    var older: (() -> Void)?
    private var dataSource: UITableViewDiffableDataSource<Int, String>!
    private var records: [String: HistoryTimelineRow] = [:]
    private var expanded: Set<String> = []
    private var value: JSONValue = .null
    private var language = ""
    private var busy = false
    private var previousRows: [HistoryTimelineRow] = []
    private var estimatedHeights: [String: CGFloat] = [:]
    private var resizeScheduled = false
    private var resizingIDs: Set<String> = []
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(table); table.backgroundColor = .clear; table.delegate = self
        table.separatorStyle = .none; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 100
        table.contentInsetAdjustmentBehavior = .always; table.keyboardDismissMode = .interactive
        table.accessibilityIdentifier = "history.page"
        table.register(HistoryTimelineCell.self, forCellReuseIdentifier: "history")
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: table) { [weak self] table, path, id in
            guard let self, let row = self.records[id] else { return nil }
            let cell = table.dequeueReusableCell(withIdentifier: "history", for: path) as! HistoryTimelineCell
            cell.changedHeight = { [weak self] in self?.scheduleResize(id: id) }
            cell.configure(row, scroll: table, busy: self.busy)
            return cell
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if table.frame != view.bounds { table.frame = view.bounds } }
    func update(_ value: JSONValue, language: String, busy: Bool = false) {
        loadViewIfNeeded()
        guard self.value != value || self.language != language || self.busy != busy else { return }
        self.value = value; self.language = language; self.busy = busy
        applyRows()
    }
    private func applyRows() {
        let rows = HistoryTimeline.rows(value: value, expanded: expanded)
        let before = records
        // Capture the reader's row rather than the entire table's estimated height.
        let capturedOffset = table.contentOffset.y
        let anchor = table.indexPathsForVisibleRows?.first.flatMap { path -> (String, CGFloat)? in
            guard let id = dataSource.itemIdentifier(for: path) else { return nil }
            return (id, table.rectForRow(at: path).minY - table.contentOffset.y)
        }
        records = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        estimatedHeights = estimatedHeights.filter { records[$0.key] != nil }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(rows.map(\.id))
        snapshot.reconfigureItems(rows.filter { before[$0.id] != nil && (before[$0.id] != $0 || $0.kind == .older) }.map(\.id))
        previousRows = rows
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }; self.table.layoutIfNeeded()
            if abs(self.table.contentOffset.y - capturedOffset) < 0.5, let anchor, let path = self.dataSource.indexPath(for: anchor.0) {
                self.table.contentOffset.y = self.table.rectForRow(at: path).minY - anchor.1
            }
        }
    }
    private func scheduleResize(id: String) {
        resizingIDs.insert(id)
        guard !resizeScheduled else { return }; resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.resizeScheduled = false
            let paths = self.resizingIDs.compactMap { self.dataSource.indexPath(for: $0) }
            self.resizingIDs.removeAll(keepingCapacity: true)
            guard !paths.isEmpty else { return }
            let capturedOffset = self.table.contentOffset.y
            let anchor = self.table.indexPathsForVisibleRows?.first.flatMap { path -> (String, CGFloat)? in
                guard let id = self.dataSource.itemIdentifier(for: path) else { return nil }
                return (id, self.table.rectForRow(at: path).minY - self.table.contentOffset.y)
            }
            // begin/endUpdates invalidates sizing for the entire table. Native
            // reconfiguration remeasures only the documents that actually grew,
            // preserving the existing cell, its attributed runs and CoreText cache.
            UIView.performWithoutAnimation {
                var snapshot = self.dataSource.snapshot()
                snapshot.reconfigureItems(paths.compactMap { self.dataSource.itemIdentifier(for: $0) })
                self.dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                    guard let self else { return }
                    self.table.layoutIfNeeded()
                    for path in paths {
                        if let id = self.dataSource.itemIdentifier(for: path), let cell = self.table.cellForRow(at: path) { self.estimatedHeights[id] = cell.bounds.height }
                    }
                    // UIKit may already have compensated for self-sizing, or the
                    // reader may have dragged since the snapshot was scheduled.
                    // Never snap an actively advancing viewport back to old offset.
                    if abs(self.table.contentOffset.y - capturedOffset) < 0.5, let anchor, let path = self.dataSource.indexPath(for: anchor.0) {
                        self.table.contentOffset.y = self.table.rectForRow(at: path).minY - anchor.1
                    }
                }
            }
        }
    }
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = records[id] else { return 100 }
        return estimatedHeights[id] ?? (row.kind == .markdown ? 160 : row.kind == .disclosure ? 72 : 50)
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let id = dataSource.itemIdentifier(for: indexPath) { estimatedHeights[id] = cell.bounds.height }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = records[id] else { return }
        if row.kind == .older { if !busy { older?() }; return }
        if row.kind == .disclosure {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            applyRows()
        } else if let url = URL(string: row.place.text("url")), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
    }
}

private final class HistoryTimelineCell: UITableViewCell {
    var changedHeight: (() -> Void)?
    private var row: HistoryTimelineRow?
    private let title = UILabel(), detail = UILabel(), preview = UILabel()
    private let icon = UIImageView(), chevron = UIImageView(), quoteBar = UIView()
    /// A group's icon sits on a tile; nested steps hang from a guide line under it.
    private let tile = UIView(), guide = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var markdown = NativeMarkdownView(frame: .zero)
    private weak var list: UIScrollView?
    private var isConfiguring = false
    private var transformRequest = 0
    private var geometryCache: (CGFloat, CGFloat)?
    private var appliedGeometryWidth: CGFloat?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear; selectionStyle = .none
        [guide, tile, title, detail, preview, icon, chevron, quoteBar, spinner].forEach { contentView.addSubview($0) }
        tile.backgroundColor = ChatPalette.tile; tile.layer.cornerRadius = 8; tile.layer.cornerCurve = .continuous
        guide.backgroundColor = .separator
        chevron.contentMode = .center
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        title.numberOfLines = 2; title.font = .preferredFont(forTextStyle: .subheadline)
        detail.numberOfLines = 3; detail.font = .preferredFont(forTextStyle: .caption1); detail.textColor = .secondaryLabel
        preview.numberOfLines = 12; preview.font = .preferredFont(forTextStyle: .body)
        icon.tintColor = .secondaryLabel; icon.contentMode = .scaleAspectFit
        chevron.tintColor = .tertiaryLabel; quoteBar.backgroundColor = .separator; quoteBar.layer.cornerRadius = 1
        [title, detail, preview].forEach { $0.adjustsFontForContentSizeCategory = true }
        bindMarkdown()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: HistoryTimelineCell, _: UITraitCollection) in
            if let row = cell.row { cell.title.font = cell.font(for: row) }
            cell.detail.font = .preferredFont(forTextStyle: .caption1, compatibleWith: cell.traitCollection)
            cell.preview.font = .preferredFont(forTextStyle: .body, compatibleWith: cell.traitCollection)
            cell.geometryCache = nil; cell.appliedGeometryWidth = nil; cell.setNeedsLayout(); cell.changedHeight?()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func bindMarkdown() { markdown.onHeightChange = { [weak self] in self?.preview.isHidden = true; self?.geometryCache = nil; self?.appliedGeometryWidth = nil; self?.setNeedsLayout(); if self?.isConfiguring != true { self?.changedHeight?() } } }
    override func prepareForReuse() {
        super.prepareForReuse(); transformRequest += 1; row = nil
        NativeMarkdownReusePool.shared.put(markdown); markdown = NativeMarkdownView(frame: .zero)
    }
    func configure(_ value: HistoryTimelineRow, scroll: UIScrollView, busy: Bool) {
        list = scroll
        if row == value { title.alpha = value.kind == .older && busy ? 0.4 : 1; return }
        // A synchronous cached parse is already ready for the row's first sizing
        // pass; notifying a second height update would schedule a redundant snapshot.
        isConfiguring = true; defer { isConfiguring = false }
        transformRequest += 1
        row = value; geometryCache = nil; appliedGeometryWidth = nil
        [title, detail, preview, icon, chevron, quoteBar, spinner, tile, guide].forEach { $0.isHidden = true }
        markdown.isHidden = true
        title.alpha = value.kind == .older && busy ? 0.4 : 1
        title.textColor = value.failed ? .systemRed : value.kind == .older ? tintColor : .label
        title.font = font(for: value)
        tile.isHidden = !(value.kind == .disclosure && value.depth == 0)
        guide.isHidden = value.depth == 0
        detail.textAlignment = value.kind == .usage ? .right : .natural
        if value.kind == .usage { title.textColor = .secondaryLabel }
        title.text = [value.title, value.place.text("name")].filter { !$0.isEmpty }.joined(separator: " · ")
        title.isHidden = title.text?.isEmpty != false
        detail.text = value.detail; detail.isHidden = value.detail.isEmpty
        detail.textColor = value.failed ? .systemRed : .secondaryLabel
        icon.image = value.symbol.isEmpty ? nil : UIImage(systemName: value.symbol); icon.isHidden = value.symbol.isEmpty
        icon.tintColor = value.failed ? .systemRed : value.kind == .disclosure && value.depth == 0 ? .label : .secondaryLabel
        chevron.image = value.kind == .disclosure ? UIImage(systemName: value.expanded ? "chevron.down" : "chevron.right") : nil; chevron.isHidden = value.kind != .disclosure
        spinner.isHidden = value.kind != .loading
        if !spinner.isHidden { spinner.startAnimating() } else { spinner.stopAnimating() }
        accessibilityIdentifier = "history.\(value.id)"
        if value.kind == .markdown {
            quoteBar.isHidden = value.symbol != "arrow.up.right" && value.symbol != "arrow.down.left"
            if value.toolName != nil {
                if let cached = ToolStepRendering.cached(value) { showMarkdown(cached, value: value, scroll: scroll) }
                else {
                    // JSON formatting/fence repair belongs off the scrolling thread,
                    // even when an expanded tool result is several megabytes long.
                    let expected = transformRequest
                    preview.text = ""; spinner.isHidden = false; spinner.startAnimating()
                    DispatchQueue.global(qos: .userInitiated).async { [weak self, weak scroll] in
                        let rendered = ToolStepRendering.render(value)
                        DispatchQueue.main.async {
                            guard let self, let scroll, self.transformRequest == expected else { return }
                            self.spinner.stopAnimating(); self.spinner.isHidden = true
                            self.showMarkdown(rendered, value: value, scroll: scroll); self.geometryCache = nil; self.appliedGeometryWidth = nil; self.setNeedsLayout(); self.changedHeight?()
                        }
                    }
                }
            } else { showMarkdown(value.text, value: value, scroll: scroll) }
        }

        setNeedsLayout()
    }
    private func showMarkdown(_ text: String, value: HistoryTimelineRow, scroll: UIScrollView) {
        if markdown.cacheSource != text || markdown.superview == nil {
            NativeMarkdownReusePool.shared.put(markdown); markdown = NativeMarkdownReusePool.shared.take(text: text)
            bindMarkdown(); contentView.addSubview(markdown)
        }
        markdown.isHidden = false; markdown.trackedScrollView = scroll; markdown.update(text: text, streaming: value.streaming)
        preview.text = String(text.prefix(1200)); preview.isHidden = markdown.hasRenderedContent || text.isEmpty
    }
    private func font(for row: HistoryTimelineRow) -> UIFont {
        switch row.kind {
        case .markdown: return .preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        case .disclosure where row.depth == 0:
            return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold), compatibleWith: traitCollection)
        case .notice where row.id == "usage.header":
            return UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), compatibleWith: traitCollection)
        default: return .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        }
    }
    private func geometry(width: CGFloat, apply: Bool) -> CGFloat {
        guard let row else { return 1 }
        if let cached = geometryCache, cached.0 == width, !apply || appliedGeometryWidth == width { return cached.1 }
        let outer = min(780, max(1, width - 32)), base = (width - outer) / 2
        let step: CGFloat = 22
        let left = base + CGFloat(row.depth) * step
        let available = max(1, outer - CGFloat(row.depth) * step)
        let grouped = !tile.isHidden
        let iconWidth: CGFloat = grouped ? 30 : 18
        let titleX = left + (icon.isHidden && spinner.isHidden ? 0 : iconWidth + (grouped ? 10 : 7))
        let titleWidth = max(1, available - (titleX - left) - (chevron.isHidden ? 0 : 24))
        var y: CGFloat = row.kind == .disclosure && row.depth == 0 ? 14 : row.id == "usage.header" ? 22 : 8
        if row.kind == .usage {
            let valueSize = detail.sizeThatFits(CGSize(width: available * 0.6, height: .greatestFiniteMagnitude))
            let labelHeight = ceil(title.sizeThatFits(CGSize(width: available - ceil(valueSize.width) - 12, height: .greatestFiniteMagnitude)).height)
            let h = max(labelHeight, ceil(valueSize.height))
            if apply {
                title.frame = CGRect(x: left, y: y, width: available - ceil(valueSize.width) - 12, height: labelHeight)
                detail.frame = CGRect(x: left + available - ceil(valueSize.width), y: y, width: ceil(valueSize.width), height: ceil(valueSize.height))
            }
            let height = ceil(y + h + 8)
            geometryCache = (width, height); if apply { appliedGeometryWidth = width }
            return height
        }
        if !title.isHidden {
            let height = ceil(title.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height)
            let line = max(height, grouped ? 30 : 20)
            if apply {
                title.frame = CGRect(x: titleX, y: y + (line - height) / 2, width: titleWidth, height: height)
                let iconFrame = CGRect(x: left, y: y + (grouped ? 0 : (line - 20) / 2), width: iconWidth, height: grouped ? 30 : 20)
                tile.frame = iconFrame
                icon.frame = grouped ? iconFrame.insetBy(dx: 7, dy: 7) : iconFrame
                spinner.frame = iconFrame
                chevron.frame = CGRect(x: left + available - 14, y: y + (line - 18) / 2, width: 12, height: 18)
            }
            y += line + (row.kind == .markdown ? 6 : 0)
        }
        if row.kind == .markdown {
            let x = left + (quoteBar.isHidden ? 0 : 12), width = max(1, available - (x - left))
            let rendered = markdown.measuredHeight(width: width)
            let height = rendered > 0 ? rendered : ceil(preview.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            if apply {
                markdown.frame = CGRect(x: x, y: y, width: width, height: max(1, rendered)); preview.frame = CGRect(x: x, y: y, width: width, height: height)
                quoteBar.frame = CGRect(x: left, y: y, width: 2, height: height)
            }
            y += height
        }
        if !detail.isHidden {
            let detailX = row.kind == .disclosure ? titleX : left
            let detailWidth = max(1, available - (detailX - left) - (chevron.isHidden ? 0 : 24))
            let height = ceil(detail.sizeThatFits(CGSize(width: detailWidth, height: .greatestFiniteMagnitude)).height)
            y += row.kind == .disclosure && row.depth == 0 ? 2 : 4
            if apply { detail.frame = CGRect(x: detailX, y: y, width: detailWidth, height: height) }
            y += height
        }
        let height = max(row.kind == .disclosure ? 40 : 32, ceil(y + (row.kind == .disclosure && row.depth == 0 ? 12 : 8)))
        if apply { guide.frame = CGRect(x: base + 14.5, y: 0, width: 1, height: height) }
        geometryCache = (width, height); if apply { appliedGeometryWidth = width }
        return height
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        // UIKit may ask for an unconstrained fitting size before assigning the
        // reused cell's frame. A zero-width Markdown measurement is both wrong
        // and very expensive: tables and prose are then typeset again at row width.
        let width = targetSize.width > 1 && targetSize.width.isFinite ? targetSize.width : (list?.bounds.width ?? bounds.width)
        return CGSize(width: width, height: geometry(width: width, apply: false))
    }
    override func layoutSubviews() { super.layoutSubviews(); _ = geometry(width: contentView.bounds.width, apply: true) }
}
