import SwiftUI
import UIKit
import ImageIO

extension JSONValue {
    var numberValue: Double? { if case .number(let value) = self { return value }; return nil }
}

struct ChatTimelineRow: Equatable, Identifiable {
    enum Kind: Equatable { case message, decision, older, newer, empty }
    let id: String
    let kind: Kind
    var value: JSONValue = .null
    /// The first entry of a run by one speaker carries the avatar and name.
    var showsAuthor = true
    /// The last entry of a run carries the time.
    var lastInGroup = true
    var streaming = false
    var isPerson: Bool { value.text("authorKind") == "person" }
    var isMine: Bool { value.flag("mine") }
}

enum ChatTimeline {
    static func matches(_ draft: ChatDraft, message: JSONValue) -> Bool {
        message.text("text") == draft.text && message["quotes"].arrayValue == draft.quotes && message["attachments"].arrayValue == draft.files
    }
    static func contains(_ draft: ChatDraft, value: JSONValue) -> Bool {
        value["outbox"].arrayValue.contains { matches(draft, message: $0) } || value["messages"].arrayValue.contains { $0.flag("mine") && matches(draft, message: $0) }
    }
    static func timestamp(_ value: JSONValue, includeDate: Bool = false) -> String {
        let stamp = value["time"]["createdAt"]
        let raw = value["createdAt"] == .null ? stamp["at"] : value["createdAt"]
        if case .number(let milliseconds) = raw, milliseconds.isFinite, milliseconds > 0 {
            let date = Date(timeIntervalSince1970: milliseconds / 1000)
            return date.formatted(Date.FormatStyle(date: includeDate ? .abbreviated : .omitted, time: .shortened, locale: L10n.locale))
        }
        return L10n.projected(stamp.text("ago", fallback: stamp.text("full", fallback: stamp.text("text"))))
    }
    static func opening(_ rows: [ChatTimelineRow], seq: Int?, offset: Double?) -> (id: String, offset: CGFloat)? {
        guard let seq, let row = rows.first(where: { $0.kind == .message && ($0.value["seq"].intValue ?? -1) >= seq }) else { return nil }
        // If the original entry disappeared, the next one opens at the top.
        let exact = row.value["seq"].intValue == seq
        let shift = exact && offset?.isFinite == true ? CGFloat(offset!) : 0
        return (row.id, shift)
    }
    /// Consecutive entries by one speaker form a run. My own entries, including
    /// ones still in the outbox, are one speaker; ember notices never join a run.
    static func speaker(_ message: JSONValue) -> String? {
        if message.flag("system") { return nil }
        if message.flag("mine") { return "mine" }
        return message.text("authorKind") + "|" + message.text("author")
    }
    static func rows(value: JSONValue, initialOutgoing: ChatDraft?, lives: [String: JSONValue]) -> [ChatTimelineRow] {
        var rows: [ChatTimelineRow] = []
        if value.flag("more") { rows.append(ChatTimelineRow(id: "older", kind: .older)) }
        for record in ViewRecord.decode(value["messages"].arrayValue, key: "seq") {
            let message = record.value
            let outgoing = message.text("outgoing")
            let id = outgoing.isEmpty ? "message:\(record.id)" : "outgoing:\(outgoing)"
            rows.append(ChatTimelineRow(id: id, kind: .message, value: message))
            if !message["card"].objectValue.isEmpty && !message["decision"].flag("resolved") {
                rows.append(ChatTimelineRow(id: "decision:\(record.id)", kind: .decision, value: message))
            }
        }
        for record in ViewRecord.decode(value["outbox"].arrayValue) {
            var outgoing = record.value.objectValue
            outgoing["mine"] = .bool(true); outgoing["authorKind"] = .string("person")
            rows.append(ChatTimelineRow(id: "outgoing:\(record.id)", kind: .message, value: .object(outgoing)))
        }
        if let draft = initialOutgoing, !contains(draft, value: value) {
            rows.append(ChatTimelineRow(id: "initialOutgoing", kind: .message, value: .object([
                "text": .string(draft.text), "quotes": .array(draft.quotes), "attachments": .array(draft.files),
                "mine": .bool(true), "authorKind": .string("person"), "state": .string("sending")
            ])))
        }
        for agent in value["agents"].arrayValue {
            let session = agent["session"], key = session.text("key", fallback: agent.text("key"))
            guard let live = lives[key] else { continue }
            for record in ViewRecord.decode(live["steps"].arrayValue) where !record.value.flag("ended") {
                let step = record.value, kind = step.text("step")
                let input = step.text("input")
                guard !input.isEmpty else { continue }
                var message: [String: JSONValue] = ["authorKind": .string("agent"), "author": .string(key), "text": .string(kind == "tool" ? HistoryRendering.fence(input, language: "text") : input),
                    "by": .object(["name": .string(session.text("agentText")), "maker": session["maker"], "runtime": session["runtime"]]), "liveStep": .string(kind)]
                if kind == "thinking" { message["status"] = .string(L10n.text("思考中")) }
                rows.append(ChatTimelineRow(id: "live:\(key):\(record.id)", kind: .message, value: .object(message), streaming: true))
            }
        }
        // Runs are computed over the final order, so the outbox and live tails join
        // the run they continue. Decision cards and pagination rows end a run.
        for index in rows.indices where rows[index].kind == .message {
            let speaker = speaker(rows[index].value)
            let previous = index > 0 && rows[index - 1].kind == .message ? Self.speaker(rows[index - 1].value) : nil
            let next = index + 1 < rows.count && rows[index + 1].kind == .message ? Self.speaker(rows[index + 1].value) : nil
            rows[index].showsAuthor = speaker == nil || previous != speaker
            rows[index].lastInGroup = speaker == nil || next != speaker
        }
        if rows.isEmpty { rows.append(ChatTimelineRow(id: "empty", kind: .empty)) }
        if value.flag("newer") { rows.append(ChatTimelineRow(id: "newer", kind: .newer)) }
        return rows
    }
    /// The core labels an agent "Model · effort". The effort is shown as its own chip.
    static func agentLabel(_ name: String) -> (model: String, effort: String?) {
        let parts = name.components(separatedBy: " · ")
        guard parts.count > 1, let last = parts.last, !last.isEmpty, last.count <= 12 else { return (name, nil) }
        return (parts.dropLast().joined(separator: " · "), last)
    }
}

struct ChatMessageList: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let rows: [ChatTimelineRow]
    let store: AppStore
    let route: ChatRoute
    let thread: Int?
    let busy: Bool
    let jumpToEnd: Int
    @Binding var atEnd: Bool
    let quote: (JSONValue) -> Void
    let download: (JSONValue) -> Void
    let retry: (JSONValue) -> Void
    let page: (String) -> Void
    var initialSeq: Int? = nil
    var initialOffset: Double? = nil
    var newer = false
    var topicLoaded = true
    var rememberPlace: (Int?, Double?) -> Void = { _, _ in }
    var positionReady: () -> Void = {}
    var footerHeight: CGFloat = 0
    func makeUIViewController(context: Context) -> ChatTimelineController { ChatTimelineController() }
    func updateUIViewController(_ controller: ChatTimelineController, context: Context) {
        controller.store = store; controller.route = route; controller.thread = thread; controller.busy = busy
        controller.quote = quote; controller.download = download; controller.retry = retry; controller.page = page
        controller.newer = newer; controller.rememberPlace = rememberPlace
        controller.positionReady = { DispatchQueue.main.async { positionReady() } }
        controller.endChanged = { end in DispatchQueue.main.async { if atEnd != end { atEnd = end } } }
        controller.updateFooterHeight(footerHeight)
        controller.followEndIfRequested(jumpToEnd)
        controller.update(rows, language: locale.identifier, initialSeq: initialSeq, initialOffset: initialOffset, loaded: topicLoaded)
    }
}

final class ChatTimelineController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    var store: AppStore?
    var route: ChatRoute?
    var thread: Int?
    var busy = false
    var quote: ((JSONValue) -> Void)?
    var download: ((JSONValue) -> Void)?
    var retry: ((JSONValue) -> Void)?
    var page: ((String) -> Void)?
    var endChanged: ((Bool) -> Void)?
    var rememberPlace: ((Int?, Double?) -> Void)?
    var positionReady: (() -> Void)?
    var newer = false
    private var positionEstablished = false
    // Estimated collection heights settle as the opening window's native text
    // parses. Keep the explicit entry anchor until the reader starts scrolling.
    private var openingAnchor: (String, CGFloat)?
    private var lastPlace: (Int?, Double?)?
    private var records: [String: ChatTimelineRow] = [:]
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var language = ""
    private var atEnd = true
    private var initialized = false
    private var previousRows: [ChatTimelineRow] = []
    private var previousBusy = false
    private var followRequest = 0
    private var layoutScheduled = false
    private var resizedRows: Set<String> = []
    private let collection: UICollectionView
    init() {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0)
        collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collection); collection.backgroundColor = .clear; collection.delegate = self; collection.prefetchDataSource = self
        collection.keyboardDismissMode = .interactive; collection.alwaysBounceVertical = true
        collection.contentInsetAdjustmentBehavior = .always
        collection.topEdgeEffect.isHidden = true; collection.bottomEdgeEffect.isHidden = true
        collection.selfSizingInvalidation = .enabled
        collection.accessibilityIdentifier = "chat.messages"
        collection.register(ChatTimelineCell.self, forCellWithReuseIdentifier: "message")
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "decision")
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { [weak self] collection, path, id in
            guard let self, let row = self.records[id] else { return nil }
            if row.kind == .decision, let store = self.store, let route = self.route {
                let cell = collection.dequeueReusableCell(withReuseIdentifier: "decision", for: path)
                cell.contentConfiguration = UIHostingConfiguration {
                    DecisionReplyView(message: row.value, station: route.station, thread: self.thread).environment(store).padding(.horizontal, 18)
                }
                return cell
            }
            let cell = collection.dequeueReusableCell(withReuseIdentifier: "message", for: path) as! ChatTimelineCell
            cell.heightChanged = { [weak self] in self?.scheduleLayout(id: id) }
            cell.configure(row, scroll: collection, busy: self.busy, download: self.download, retry: self.retry, page: self.page)
            return cell
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if collection.frame != view.bounds { collection.frame = view.bounds; collection.collectionViewLayout.invalidateLayout(); collection.layoutIfNeeded(); alignShortConversation(); if atEnd { toEnd() } }
        if let openingAnchor { restore(openingAnchor) }
    }
    func update(_ rows: [ChatTimelineRow], language: String, initialSeq: Int? = nil, initialOffset: Double? = nil, loaded: Bool = true) {
        loadViewIfNeeded()
        guard rows != previousRows || self.language != language || previousBusy != busy || (!positionEstablished && loaded) else { return }
        let changedBusy = previousBusy != busy
        previousRows = rows; previousBusy = busy
        let before = records
        let top = collection.indexPathsForVisibleItems.sorted().first
        let topID = top.flatMap { dataSource.itemIdentifier(for: $0) }
        let offset = top.flatMap { collection.layoutAttributesForItem(at: $0)?.frame.minY }.map { $0 - collection.contentOffset.y }
        let changedLanguage = self.language != language; self.language = language
        records = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(rows.map(\.id))
        snapshot.reconfigureItems(rows.filter { before[$0.id] != nil && (before[$0.id] != $0 || changedLanguage || (changedBusy && ($0.kind == .older || $0.kind == .newer || $0.value.text("state") == "failed"))) }.map(\.id))
        let opening = !positionEstablished && loaded ? ChatTimeline.opening(rows, seq: initialSeq, offset: initialOffset) : nil
        if let openingAnchor, !rows.contains(where: { $0.id == openingAnchor.0 }) { self.openingAnchor = nil }
        let establish = !positionEstablished && loaded
        let follow = opening == nil && (atEnd || !initialized); initialized = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.collection.layoutIfNeeded(); self.alignShortConversation()
            if let opening {
                self.openingAnchor = (opening.id, opening.offset); self.atEnd = false; self.endChanged?(false)
                if let path = self.dataSource.indexPath(for: opening.id) {
                    self.collection.scrollToItem(at: path, at: .top, animated: false)
                    self.collection.layoutIfNeeded()
                }
                self.restore((opening.id, opening.offset))
            }
            else if let openingAnchor = self.openingAnchor { self.restore(openingAnchor) }
            else if follow { self.toEnd() }
            else if let topID, let offset, let path = self.dataSource.indexPath(for: topID), let attrs = self.collection.layoutAttributesForItem(at: path) {
                self.collection.contentOffset.y = attrs.frame.minY - offset
            }
            self.reportPosition()
            if establish { self.positionEstablished = true; self.positionReady?() }
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); rememberReaderPlace() }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { openingAnchor = nil }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { rememberReaderPlace() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { rememberReaderPlace() }
    private func rememberReaderPlace() {
        guard positionEstablished else { return }
        let seq: Int?, offset: Double?
        if atEnd && !newer { seq = nil; offset = nil }
        else {
            let message = collection.indexPathsForVisibleItems.sorted().first { path in
                guard let id = dataSource.itemIdentifier(for: path), let row = records[id] else { return false }
                return row.kind == .message && row.value["seq"].intValue != nil
            }
            guard let path = message, let id = dataSource.itemIdentifier(for: path), let row = records[id], let frame = collection.layoutAttributesForItem(at: path)?.frame else { return }
            seq = row.value["seq"].intValue; offset = Double(((frame.minY - collection.contentOffset.y) * 10).rounded() / 10)
        }
        if let lastPlace, lastPlace.0 == seq && lastPlace.1 == offset { return }
        lastPlace = (seq, offset); rememberPlace?(seq, offset)
    }
    private func scheduleLayout(id: String) {
        resizedRows.insert(id)
        guard !layoutScheduled else { return }; layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.layoutScheduled = false
            let follow = self.atEnd
            let anchor = self.openingAnchor ?? self.anchor()
            let paths = self.resizedRows.compactMap { self.dataSource.indexPath(for: $0) }
            self.resizedRows.removeAll(keepingCapacity: true)
            if !paths.isEmpty {
                let contextType = type(of: self.collection.collectionViewLayout).invalidationContextClass as! UICollectionViewLayoutInvalidationContext.Type
                let context = contextType.init(); context.invalidateItems(at: paths)
                self.collection.collectionViewLayout.invalidateLayout(with: context)
            }
            self.collection.layoutIfNeeded(); self.alignShortConversation()
            if follow { self.toEnd() } else if let anchor { self.restore(anchor) }; self.reportPosition()
        }
    }
    func updateFooterHeight(_ height: CGFloat) {
        loadViewIfNeeded()
        let height = max(0, height)
        guard abs(collection.contentInset.bottom - height) > 0.5 else { return }
        let readerAnchor = openingAnchor ?? anchor()
        let follow = atEnd
        collection.contentInset.bottom = height
        collection.verticalScrollIndicatorInsets.bottom = height
        collection.layoutIfNeeded(); alignShortConversation()
        if follow { toEnd() } else if let readerAnchor { restore(readerAnchor) }
    }
    func followEndIfRequested(_ request: Int) {
        guard followRequest != request else { return }; followRequest = request; openingAnchor = nil; atEnd = true; if isViewLoaded { toEnd() }
    }
    private func anchor() -> (String, CGFloat)? {
        guard let path = collection.indexPathsForVisibleItems.sorted().first,
              let id = dataSource.itemIdentifier(for: path), let frame = collection.layoutAttributesForItem(at: path)?.frame else { return nil }
        return (id, frame.minY - collection.contentOffset.y)
    }
    private func restore(_ anchor: (String, CGFloat)) {
        guard let path = dataSource.indexPath(for: anchor.0), let frame = collection.layoutAttributesForItem(at: path)?.frame else { return }
        let offset = frame.minY - anchor.1
        if abs(collection.contentOffset.y - offset) > 0.5 { collection.contentOffset.y = offset }
    }
    private func alignShortConversation() {
        let empty = records.values.contains { $0.kind == .empty }
        // Automatic safe-area insets belong to the translucent chrome. Additional
        // empty-space alignment must not count those insets as available message space.
        let systemTop = max(0, collection.adjustedContentInset.top - collection.contentInset.top)
        let gap = max(0, collection.bounds.height - systemTop - collection.adjustedContentInset.bottom - collection.contentSize.height)
        let padding = empty ? gap / 2 : gap
        if abs(collection.contentInset.top - padding) > 0.5 { collection.contentInset.top = padding }
    }
    private func toEnd() {
        let bottom = max(-collection.adjustedContentInset.top, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
        collection.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { reportPosition() }
    private func reportPosition() {
        let end = collection.contentOffset.y + collection.bounds.height - collection.adjustedContentInset.bottom >= collection.contentSize.height - 50
        guard end != atEnd else { return }; atEnd = end; endChanged?(end)
    }
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let upcoming = indexPaths.prefix(8).compactMap { path -> String? in
            guard let id = dataSource.itemIdentifier(for: path), let row = records[id], row.kind == .message, !row.streaming else { return nil }
            return row.value.text("text")
        }
        MarkdownPrefetch.prepare(upcoming)
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = records[id], row.kind == .message else { return nil }
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: L10n.text("复制"), image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = row.value.text("text") },
                UIAction(title: L10n.text("引用"), image: UIImage(systemName: "quote.bubble")) { _ in self?.quote?(row.value) }
            ])
        }
    }
}

/// Bubble and chrome colors shared by the timeline and the new-chat handoff.
enum ChatPalette {
    static let myBubble = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.953, green: 0.949, blue: 0.941, alpha: 1) }
    static let theirBubble = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor.white }
    static let theirBorder = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.08) }
    static let tile = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.045) }
}

/// A speaker's picture: a model's mark on a rounded tile, or a person's portrait or initial.
final class ChatAvatarView: UIView {
    private let image = UIImageView()
    private let initial = UILabel()
    private var task: URLSessionDataTask?
    private var address: URL?
    private var isAgent = false
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>(); cache.countLimit = 100; cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    private static let tones: [UIColor] = [
        UIColor(red: 0.79, green: 0.58, blue: 0.30, alpha: 1), UIColor(red: 0.44, green: 0.56, blue: 0.75, alpha: 1),
        UIColor(red: 0.49, green: 0.60, blue: 0.44, alpha: 1), UIColor(red: 0.69, green: 0.48, blue: 0.61, alpha: 1),
        UIColor(red: 0.55, green: 0.51, blue: 0.78, alpha: 1), UIColor(red: 0.78, green: 0.49, blue: 0.42, alpha: 1)]
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true; layer.cornerCurve = .continuous
        image.contentMode = .scaleAspectFit; image.clipsToBounds = true
        initial.textAlignment = .center; initial.textColor = .white
        initial.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(image); addSubview(initial)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if isAgent {
            layer.cornerRadius = bounds.width * 0.3
            image.frame = bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2)
        } else {
            layer.cornerRadius = bounds.width / 2
            image.frame = bounds
        }
        initial.frame = bounds
    }
    func showAgent(maker: String, runtime: String) {
        reset(); isAgent = true
        backgroundColor = ChatPalette.tile
        image.contentMode = .scaleAspectFit; image.tintColor = .label
        image.image = ModelLogo.image(maker: maker, runtime: runtime) ?? UIImage(systemName: "sparkle")
        initial.isHidden = true; setNeedsLayout()
    }
    func showPerson(name: String, id: String, picture: String) {
        reset(); isAgent = false
        image.contentMode = .scaleAspectFill
        let hash = id.utf16.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
        backgroundColor = Self.tones[Int(hash % UInt32(Self.tones.count))]
        let words = name.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_./@"))).filter { !$0.isEmpty }
        initial.text = String((words.first ?? name).prefix(1)).uppercased()
        if initial.text?.isEmpty != false { initial.text = "?" }
        initial.isHidden = false; setNeedsLayout()
        guard let url = URL(string: picture), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        address = url
        if let cached = Self.cache.object(forKey: url as NSURL) { image.image = cached; initial.isHidden = true; return }
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return }
            let loaded = UIImage(cgImage: thumbnail)
            Self.cache.setObject(loaded, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            DispatchQueue.main.async { guard let self, self.address == url else { return }; self.image.image = loaded; self.initial.isHidden = true }
        }
        task?.resume()
    }
    func reset() { task?.cancel(); task = nil; address = nil; image.image = nil }
}

/// A capsule of secondary text, used for an agent's reasoning effort.
private final class ChipLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 7, dy: 0)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(CGSize(width: max(1, size.width - 14), height: size.height))
        return CGSize(width: ceil(base.width) + 14, height: max(20, ceil(base.height) + 4))
    }
}

/// Three message shapes, laid out by hand so measuring never builds a view tree:
/// my words in a bubble on the right; a teammate's run on the left with one
/// portrait and name; an agent's reply unbubbled under its model, name and effort.
private final class ChatTimelineCell: UICollectionViewCell {
    var heightChanged: (() -> Void)?
    private var row: ChatTimelineRow?
    private let bubble = UIView()
    private let avatar = ChatAvatarView()
    private let author = UILabel()
    private let effort = ChipLabel()
    private let status = UILabel()
    private let preview = UILabel()
    private var markdown = NativeMarkdownView(frame: .zero)
    private var configuredLanguage = ""
    private var configuredBusy = false
    private var isConfiguring = false
    private var geometryCache: (CGFloat, CGFloat)?
    private var appliedGeometryWidth: CGFloat?
    private let quoteBar = UIView()
    private let references = UILabel()
    private let footer = UILabel()
    private let notice = UILabel()
    private let action = UIButton(type: .system)
    private var files: [UIButton] = []
    private var primaryAction: (() -> Void)?
    private enum Shape { case mine, theirs, agent }
    private var shape: Shape {
        guard let row else { return .agent }
        return row.isPerson ? (row.isMine ? .mine : .theirs) : .agent
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(bubble)
        [avatar, author, effort, status, preview, markdown, quoteBar, references, footer, notice, action].forEach { contentView.addSubview($0) }
        bubble.layer.cornerRadius = 20; bubble.layer.cornerCurve = .continuous
        author.adjustsFontForContentSizeCategory = true
        effort.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .medium))
        effort.textColor = .secondaryLabel; effort.backgroundColor = ChatPalette.tile
        effort.layer.cornerRadius = 10; effort.layer.cornerCurve = .continuous; effort.clipsToBounds = true; effort.textAlignment = .center
        status.textColor = .tertiaryLabel
        preview.numberOfLines = 0
        quoteBar.backgroundColor = .tertiaryLabel; quoteBar.layer.cornerRadius = 1
        references.textColor = .secondaryLabel; references.numberOfLines = 3
        footer.textColor = .tertiaryLabel; footer.numberOfLines = 2
        notice.textColor = .secondaryLabel; notice.numberOfLines = 0; notice.textAlignment = .center
        refreshFonts()
        bindMarkdown()
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule; config.buttonSize = .small
        config.baseForegroundColor = .label
        action.configuration = config
        action.addAction(UIAction { [weak self] _ in self?.primaryAction?() }, for: .touchUpInside)
        [status, preview, references, footer, notice].forEach { $0.adjustsFontForContentSizeCategory = true }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (cell: ChatTimelineCell, _: UITraitCollection) in
            cell.refreshFonts(); cell.bubble.layer.borderColor = ChatPalette.theirBorder.resolvedColor(with: cell.traitCollection).cgColor
            cell.geometryCache = nil; cell.appliedGeometryWidth = nil; cell.setNeedsLayout(); cell.heightChanged?()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func bindMarkdown() {
        markdown.onHeightChange = { [weak self] in self?.preview.isHidden = true; self?.geometryCache = nil; self?.appliedGeometryWidth = nil; self?.setNeedsLayout(); if self?.isConfiguring != true { self?.heightChanged?() } }
    }
    override func prepareForReuse() {
        super.prepareForReuse(); avatar.reset(); row = nil; primaryAction = nil
        NativeMarkdownReusePool.shared.put(markdown)
        // Do not clear the old view: its attributed document and measured lines
        // are exactly the expensive work the next viewport visit needs.
        markdown = NativeMarkdownView(frame: .zero)
    }
    func configure(_ value: ChatTimelineRow, scroll: UIScrollView, busy: Bool, download: ((JSONValue) -> Void)?, retry: ((JSONValue) -> Void)?, page: ((String) -> Void)?) {
        let sameRow = row == value && configuredLanguage == L10n.locale.identifier
        if sameRow {
            // A busy transition only affects pagination/retry controls. It must
            // not rebuild code views, avatar requests or Markdown for every row.
            action.isEnabled = !busy; configuredBusy = busy
            return
        }
        isConfiguring = true; defer { isConfiguring = false }
        if row?.id != value.id || markdown.superview == nil {
            NativeMarkdownReusePool.shared.put(markdown)
            markdown = NativeMarkdownReusePool.shared.take(text: value.value.text("text"))
            bindMarkdown(); contentView.addSubview(markdown); preview.isHidden = false
        }
        configuredLanguage = L10n.locale.identifier; configuredBusy = busy
        geometryCache = nil; appliedGeometryWidth = nil
        row = value
        files.forEach { $0.removeFromSuperview() }; files = []
        [bubble, avatar, author, effort, status, preview, markdown, quoteBar, references, footer, notice, action].forEach { $0.isHidden = true }
        primaryAction = nil
        accessibilityIdentifier = value.kind == .message ? "message.\(value.value["seq"].intValue ?? 0)" : "chat.\(value.id)"
        if value.kind != .message {
            switch value.kind {
            case .empty:
                notice.isHidden = false; notice.text = L10n.text("发送第一条消息，开始这个会话。")
            case .older, .newer:
                action.isHidden = false; action.isEnabled = !busy
                action.configuration?.title = L10n.text(value.kind == .older ? "加载更早的消息" : "加载更新的消息")
                primaryAction = { page?(value.kind == .older ? "chat.older" : "chat.newer") }
            default: break
            }
            setNeedsLayout(); return
        }
        let message = value.value
        if message.flag("system") {
            notice.isHidden = false; notice.text = message.text("text")
            setNeedsLayout(); return
        }
        let name = message["by"].text("name", fallback: message.text("authorName", fallback: message.text("author")))
        switch shape {
        case .agent:
            let label = ChatTimeline.agentLabel(L10n.projected(name))
            author.text = label.model
            effort.text = label.effort.map { L10n.text($0) }
            author.isHidden = !value.showsAuthor; avatar.isHidden = !value.showsAuthor
            effort.isHidden = !value.showsAuthor || label.effort == nil
            if value.showsAuthor { avatar.showAgent(maker: message["by"]["maker"].text("id"), runtime: message["by"].text("runtime")) }
        case .theirs:
            author.text = name
            author.isHidden = !value.showsAuthor; avatar.isHidden = !value.showsAuthor
            if value.showsAuthor {
                avatar.showPerson(name: name, id: message.text("author", fallback: name), picture: message["by"].text("picture"))
            }
        case .mine: break
        }
        if shape != .agent {
            bubble.isHidden = false
            bubble.backgroundColor = shape == .mine ? ChatPalette.myBubble : ChatPalette.theirBubble
            bubble.layer.borderWidth = shape == .theirs ? 1 / max(1, traitCollection.displayScale) : 0
            bubble.layer.borderColor = ChatPalette.theirBorder.resolvedColor(with: traitCollection).cgColor
        }
        markdown.isHidden = false; markdown.trackedScrollView = scroll; markdown.update(text: message.text("text"), streaming: value.streaming)
        preview.text = String(message.text("text").prefix(1200)); preview.isHidden = markdown.hasRenderedContent || message.text("text").isEmpty
        references.text = message["quotes"].arrayValue.map { quote in
            [quote.text("author"), quote.text("text").replacingOccurrences(of: "\n", with: " ")].filter { !$0.isEmpty }.joined(separator: "：")
        }.joined(separator: "\n")
        references.isHidden = references.text?.isEmpty != false; quoteBar.isHidden = references.isHidden
        for file in message["attachments"].arrayValue {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain(); config.title = file.text("name"); config.image = UIImage(systemName: "paperclip")
            config.imagePadding = 6; config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            config.titleLineBreakMode = .byTruncatingMiddle; config.baseForegroundColor = .label
            config.background.backgroundColor = ChatPalette.tile; config.cornerStyle = .medium
            button.configuration = config; button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { _ in download?(file) }, for: .touchUpInside)
            contentView.addSubview(button); files.append(button)
        }
        status.text = message.text("status"); status.isHidden = status.text?.isEmpty != false || !value.showsAuthor || shape != .agent
        let state = message.text("state")
        footer.text = state.isEmpty ? (value.lastInGroup ? ChatTimeline.timestamp(message) : "") : L10n.text(state == "failed" ? "未发送成功，消息已保留" : "正在发送，消息已保留")
        footer.textColor = state == "failed" ? .systemRed : .tertiaryLabel
        footer.textAlignment = shape == .mine ? .right : .left
        footer.isHidden = footer.text?.isEmpty != false
        if state == "failed" {
            action.isHidden = false; action.configuration?.title = L10n.text("重试发送"); action.isEnabled = !busy
            primaryAction = { retry?(message) }; action.accessibilityIdentifier = "outbox.retry.\(message.text("id"))"
        }
        setNeedsLayout()
    }
    private func refreshFonts() {
        let agent = shape == .agent
        author.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: agent ? 14 : 12, weight: .semibold), compatibleWith: traitCollection)
        author.textColor = agent ? .label : .secondaryLabel
        effort.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .medium), compatibleWith: traitCollection)
        status.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12), compatibleWith: traitCollection)
        preview.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        references.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
        footer.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11), compatibleWith: traitCollection)
        notice.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    }
    private func fit(_ label: UILabel, _ width: CGFloat) -> CGSize {
        let size = label.sizeThatFits(CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, ceil(size.width)), height: ceil(size.height))
    }
    /// The widest line of the body, so a bubble hugs short words instead of a fixed column.
    private func bodyWidth(maximum: CGFloat) -> CGFloat {
        let text = markdown.measuredWidth(maxWidth: maximum)
        var widest = text > 0 ? text : fit(preview, maximum).width
        if !references.isHidden { widest = max(widest, fit(references, maximum - 10).width + 10) }
        if !files.isEmpty { widest = max(widest, min(maximum, 220)) }
        return max(24, min(maximum, ceil(widest)))
    }
    private func geometry(width: CGFloat, apply: Bool) -> CGFloat {
        guard let row else { return 1 }
        if let cached = geometryCache, cached.0 == width, !apply || appliedGeometryWidth == width { return cached.1 }
        refreshFontsIfNeeded()
        let margin: CGFloat = width >= 600 ? 28 : 16
        let column = min(760, max(1, width - margin * 2)), origin = (width - column) / 2
        if row.kind != .message || row.value.flag("system") {
            if !notice.isHidden {
                let size = fit(notice, min(column, 520))
                let h = row.kind == .empty ? max(120, size.height + 40) : size.height + 20
                if apply { notice.frame = CGRect(x: origin, y: (h - size.height) / 2, width: column, height: size.height) }
                return rememberGeometry(h, width: width, applied: apply)
            }
            let size = action.sizeThatFits(CGSize(width: column, height: 40))
            if apply { action.frame = CGRect(x: (width - size.width) / 2, y: 8, width: size.width, height: size.height) }
            return rememberGeometry(size.height + 16, width: width, applied: apply)
        }
        // An agent's consecutive replies are separate documents and need air between them;
        // a person's bubbles in one run sit close together.
        var y: CGFloat = row.showsAuthor ? 16 : (shape == .agent ? 14 : 4)
        let indent: CGFloat = 38
        let padX: CGFloat = 14, padY: CGFloat = 10
        switch shape {
        case .agent:
            if !author.isHidden {
                let tile: CGFloat = 26
                let chip = effort.isHidden ? .zero : effort.sizeThatFits(CGSize(width: 120, height: 20))
                let statusSize = status.isHidden ? .zero : fit(status, 160)
                let nameWidth = max(1, column - tile - 10 - (chip.width > 0 ? chip.width + 8 : 0) - (statusSize.width > 0 ? statusSize.width + 8 : 0))
                let name = fit(author, nameWidth)
                if apply {
                    avatar.frame = CGRect(x: origin, y: y, width: tile, height: tile)
                    author.frame = CGRect(x: origin + tile + 10, y: y + (tile - name.height) / 2, width: name.width, height: name.height)
                    var x = author.frame.maxX + 8
                    if chip.width > 0 { effort.frame = CGRect(x: x, y: y + (tile - chip.height) / 2, width: chip.width, height: chip.height); x += chip.width + 8 }
                    if statusSize.width > 0 { status.frame = CGRect(x: x, y: y + (tile - statusSize.height) / 2, width: statusSize.width, height: statusSize.height) }
                }
                y += tile + 8
            }
            y = layoutBody(x: origin, y: y, width: column, apply: apply)
            y = layoutFooter(x: origin, y: y + 6, width: column, alignRight: false, apply: apply)
        case .mine, .theirs:
            let leading = shape == .theirs ? origin + indent : origin
            let available = shape == .theirs ? column - indent : column
            let maxBubble = min(available * (shape == .mine ? 0.82 : 0.88), 560)
            if shape == .theirs && !author.isHidden {
                let name = fit(author, maxBubble)
                if apply { author.frame = CGRect(x: leading + 4, y: y, width: name.width, height: name.height) }
                y += name.height + 4
            }
            let inner = bodyWidth(maximum: maxBubble - padX * 2)
            let bubbleWidth = inner + padX * 2
            let bubbleX = shape == .mine ? origin + column - bubbleWidth : leading
            let top = y
            y = layoutBody(x: bubbleX + padX, y: y + padY, width: inner, apply: apply) + padY
            if apply {
                bubble.frame = CGRect(x: bubbleX, y: top, width: bubbleWidth, height: y - top)
                if shape == .theirs && !avatar.isHidden { avatar.frame = CGRect(x: origin, y: top + max(0, min(y - top, 40) - 30) / 2, width: 30, height: 30) }
            }
            y = layoutFooter(x: shape == .mine ? origin : bubbleX + 4, y: y + 4, width: shape == .mine ? column - 4 : available - 4, alignRight: shape == .mine, apply: apply)
        }
        return rememberGeometry(ceil(y + (row.lastInGroup ? 6 : 0)), width: width, applied: apply)
    }
    private func layoutBody(x: CGFloat, y start: CGFloat, width: CGFloat, apply: Bool) -> CGFloat {
        var y = start
        if !references.isHidden {
            let size = fit(references, width - 10)
            if apply { references.frame = CGRect(x: x + 10, y: y, width: width - 10, height: size.height); quoteBar.frame = CGRect(x: x, y: y + 1, width: 2, height: size.height - 2) }
            y += size.height + 8
        }
        let rendered = markdown.measuredHeight(width: width)
        let bodyHeight = rendered > 0 ? rendered : (preview.isHidden ? 0 : fit(preview, width).height)
        if apply { markdown.frame = CGRect(x: x, y: y, width: width, height: max(1, rendered)); preview.frame = CGRect(x: x, y: y, width: width, height: bodyHeight) }
        y += bodyHeight
        for file in files {
            y += 8
            if apply { file.frame = CGRect(x: x, y: y, width: width, height: 34) }
            y += 34
        }
        return y
    }
    private func layoutFooter(x: CGFloat, y start: CGFloat, width: CGFloat, alignRight: Bool, apply: Bool) -> CGFloat {
        var y = start
        if !footer.isHidden {
            let size = fit(footer, width)
            if apply { footer.frame = CGRect(x: x, y: y, width: width, height: size.height) }
            y += size.height
        } else { y -= 4 }
        if !action.isHidden {
            let size = action.sizeThatFits(CGSize(width: width, height: 36))
            if apply { action.frame = CGRect(x: alignRight ? x + width - size.width : x, y: y + 6, width: size.width, height: size.height) }
            y += size.height + 6
        }
        return y
    }
    private var fontShape: Shape?
    private func refreshFontsIfNeeded() { if fontShape != shape { fontShape = shape; refreshFonts() } }
    private func rememberGeometry(_ height: CGFloat, width: CGFloat, applied: Bool) -> CGFloat {
        geometryCache = (width, height); if applied { appliedGeometryWidth = width }; return height
    }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = geometry(width: attributes.size.width, apply: false)
        return attributes
    }
    override func layoutSubviews() { super.layoutSubviews(); _ = geometry(width: bounds.width, apply: true) }
}
