import SwiftUI
import UIKit
import ImageIO

private struct ChatVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var chatVisible: Bool {
        get { self[ChatVisibilityKey.self] }
        set { self[ChatVisibilityKey.self] = newValue }
    }
}

struct ChatRoute: Hashable, Identifiable {
    let station: String
    let session: String
    var thread: Int?
    var id: String { station + ":" + session + ":" + (thread.map(String.init) ?? "") }
    var params: [String: JSONValue] {
        var result: [String: JSONValue] = ["station": .string(station)]
        if let thread { result["thread"] = .number(Double(thread)) }
        else { result["session"] = .string(session) }
        return result
    }
    init(station: String, session: String, thread: Int? = nil) {
        self.station = station; self.session = session; self.thread = thread
    }
    init(_ row: JSONValue) {
        station = row.text("station")
        session = row.text("session", fallback: row.text("id"))
        thread = row["thread"].intValue
    }
}

enum ConversationFilter: String, CaseIterable {
    case all = "全部会话", mine = "我参与的", watching = "我关注的"
    func includes(_ row: JSONValue) -> Bool {
        switch self {
        case .all: return true
        case .mine: return row.flag("mine")
        case .watching: return !row["watch"].objectValue.isEmpty
        }
    }
    static func needsDecision(_ row: JSONValue) -> Bool {
        !row["decision"].flag("dismissed") && !row["decision"].text("text").isEmpty
    }
}

/// SwiftUI owns navigation and sheets; UIKit owns the frequently changing, reusable rows.
struct ConversationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let workspace: String
    @State private var filter = ConversationFilter.all
    @State private var choosingWorkspace = false
    @State private var workspaceDetent = PresentationDetent.medium
    @State private var showingSettings = false
    @State private var route: ChatRoute?
    @State private var draftID: UUID?
    @State private var renameRow: ConversationListRow?
    @State private var archiveRow: ConversationListRow?
    @State private var operation = ViewOperation()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    // iPhone: the new chat is a page layer that follows the finger in from the right edge
    // and back out from the left. It is the real page from the first frame of the drag.
    @State private var drawerID: UUID?
    @State private var drawerOffset: CGFloat = 0
    @State private var drawerWidth: CGFloat = 400
    @State private var drawerDragging = false
    @State private var edgeTriggered = false
    private var compact: Bool { horizontalSizeClass == .compact }
    private var modalOpen: Bool { showingSettings || choosingWorkspace || renameRow != nil || archiveRow != nil }
    private var current: WorkspaceChoice? {
        WorkspaceChoice.decode(store.workspaceGroups).first {
            $0.workspaceID == workspace && $0.accountID == store.selectedAccountID
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            TopicContent(name: "chats", params: ["scope": .string(workspace), "mine": .bool(false)]) { value in
                // The list runs under the transparent header and to the screen's bottom edge;
                // UIKit insets its rows from the real safe area, like the chat timeline.
                ConversationTable(
                    sections: ConversationListSection.decode(value, filter: filter, locale: locale),
                    selected: route,
                    empty: emptyState(value),
                    locale: locale.identifier,
                    busy: operation.busy,
                    onSelect: open,
                    onRename: { renameRow = $0 },
                    onArchive: askToArchive,
                    onPin: pin,
                    onRetry: retryConnections
                )
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let trouble = value["trouble"]["text"].stringValue {
                        Text(L10n.projected(trouble)).font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 8)
                            .accessibilityIdentifier("conversations.trouble")
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 8) {
                        if operation.busy { ProgressView().padding(10).glassEffect(.regular, in: Circle()) }
                        if let error = operation.error { FailureNotice(message: error) }
                    }.padding(.bottom, 84)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbarBackground(.hidden, for: .navigationBar)
            .background { ProgressiveHeaderBlur().frame(width: 0, height: 0).allowsHitTesting(false) }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { workspaceDetent = .medium; choosingWorkspace = true } label: {
                        HStack(spacing: 5) {
                            Text(current?.name ?? L10n.text("工作区")).font(.headline).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                    }.accessibilityIdentifier("conversations.workspace")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("会话筛选", selection: $filter) {
                            ForEach(ConversationFilter.allCases, id: \.self) { value in
                                Text(L10n.text(value.rawValue)).tag(value)
                                    .accessibilityIdentifier("conversations.filter.\(value)")
                            }
                        }
                    } label: {
                        Label("会话筛选", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }.accessibilityIdentifier("conversations.filter")
                    Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }
                        .accessibilityIdentifier("conversations.settings")
                }
            }
            // Floats over the list like the composer's glass: the list keeps the full height
            // and its last rows scroll above the button through the table's bottom inset.
            .overlay(alignment: .bottomTrailing) {
                Button(action: newChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .padding(.trailing, 20).padding(.bottom, 12)
                .accessibilityLabel(Text("新建会话"))
                .accessibilityIdentifier("conversations.new")
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
            .accessibilityIdentifier("conversations.page")
        } detail: {
            Group {
                if let draftID {
                    // Creation remains mounted through the optimistic transition into its first chat.
                    NewChatView(workspace: workspace) { created in route = created }
                        .id(draftID)
                } else if let route {
                    ChatView(route: route, workspace: workspace).id(route.id)
                } else {
                    ContentUnavailableView("选择会话", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("从左侧选择会话，或开始一个新会话。"))
                }
            }
            .environment(\.chatVisible, (horizontalSizeClass != .compact || compactColumn == .detail) &&
                         !showingSettings && !choosingWorkspace && renameRow == nil && archiveRow == nil)
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            EdgePanGesture(edge: .right, name: "conversations.newChat.edge",
                           enabled: !modalOpen && (!compact || (compactColumn == .sidebar && (drawerID == nil || drawerDragging))),
                           onPan: edgePan)
                .frame(width: 0, height: 0).allowsHitTesting(false)
        }
        // The list recedes a little under the incoming page, as a navigation push does.
        .offset(x: compact && drawerID != nil ? -(drawerWidth - drawerOffset) * 0.28 : 0)
        .overlay {
            if compact && drawerID != nil {
                Color.black.opacity(0.1 * Double(1 - drawerOffset / max(1, drawerWidth)))
                    .ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .overlay {
            if compact, let drawerID { drawer(drawerID) }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            drawerWidth = max(1, width)
            if drawerID != nil && !drawerDragging && drawerOffset > 0 { drawerOffset = drawerWidth }
        }
        .onChange(of: horizontalSizeClass) { _, size in
            // Rotating into a regular width hands an open drawer to the split detail.
            if size != .compact, drawerID != nil { drawerID = nil; draftID = UUID(); route = nil }
        }
        .sheet(isPresented: $choosingWorkspace) {
            NavigationStack { WorkspaceChooserView() }
                .presentationDetents([.medium, .large], selection: $workspaceDetent)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView().toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { showingSettings = false }
                            .accessibilityIdentifier("settings.close")
                    }
                }
            }.presentationDragIndicator(.visible)
        }
        .sheet(item: $renameRow) { row in
            RenameSheet(title: L10n.text("重命名会话"), initial: row.title) { name in
                var params = row.route.params
                params["title"] = .string(name)
                _ = try await store.call("chat.rename", params: params)
            }.presentationDetents([.medium])
        }
        .confirmationDialog("归档会话", isPresented: Binding(get: { archiveRow != nil }, set: { if !$0 { archiveRow = nil } }),
                            titleVisibility: .visible) {
            if let row = archiveRow {
                Button("归档") { archive(row); archiveRow = nil }
            }
            Button("取消", role: .cancel) { archiveRow = nil }
        } message: { Text(archiveRow?.value["watch"].text("ask") ?? "") }
        .onChange(of: compactColumn) { _, column in
            if column == .sidebar && horizontalSizeClass == .compact { Task { await focusList() } }
        }
        .task { if route == nil && draftID == nil { await focusList() } }
    }

    private func open(_ row: ConversationListRow) {
        draftID = nil
        route = row.route
        compactColumn = .detail
    }
    private func newChat() {
        guard compact else {
            draftID = UUID(); route = nil
            return
        }
        guard drawerID == nil else { return }
        var mount = Transaction(); mount.disablesAnimations = true
        withTransaction(mount) { drawerOffset = drawerWidth; drawerID = UUID() }
        Task { @MainActor in
            await Task.yield()
            settleDrawer(open: true)
        }
    }
    private func drawer(_ id: UUID) -> some View {
        NavigationStack {
            NewChatView(workspace: workspace) { _ in }
                .id(id)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { settleDrawer(open: false) } label: { Label("返回", systemImage: "chevron.backward") }
                            .accessibilityIdentifier("newChat.back")
                    }
                }
        }
        .environment(\.chatVisible, drawerOffset == 0 && !modalOpen)
        .background(Color(uiColor: .systemBackground))
        .shadow(color: .black.opacity(drawerOffset > 0 ? 0.14 : 0), radius: 18, x: -6)
        .offset(x: drawerOffset)
        .background {
            EdgePanGesture(edge: .left, name: "newChat.back.edge", enabled: !modalOpen && (drawerOffset == 0 || drawerDragging),
                           preferSplit: false, onPan: backPan)
                .frame(width: 0, height: 0).allowsHitTesting(false)
        }
        .accessibilityIdentifier("newChat.drawer")
    }
    /// Right edge: on iPhone the page follows the finger; on iPad a short pull opens the detail.
    private func edgePan(_ pan: EdgePan) {
        guard compact else {
            if pan.state == .began { edgeTriggered = false }
            if !edgeTriggered && (pan.state == .changed || pan.state == .ended) && pan.translation < -48 {
                edgeTriggered = true; newChat()
            }
            return
        }
        switch pan.state {
        case .began:
            drawerDragging = true
            var mount = Transaction(); mount.disablesAnimations = true
            withTransaction(mount) { drawerOffset = drawerWidth; drawerID = UUID() }
        case .changed:
            var follow = Transaction(); follow.disablesAnimations = true
            withTransaction(follow) { drawerOffset = min(drawerWidth, max(0, drawerWidth + pan.translation)) }
        default:
            drawerDragging = false
            let open = pan.state == .ended && (pan.velocity < -450 || (drawerOffset < drawerWidth * 0.6 && pan.velocity < 450))
            settleDrawer(open: open, velocity: pan.velocity)
        }
    }
    /// Left edge of the open page: drag it back out, like an interactive pop.
    private func backPan(_ pan: EdgePan) {
        switch pan.state {
        case .began: drawerDragging = true
        case .changed:
            var follow = Transaction(); follow.disablesAnimations = true
            withTransaction(follow) { drawerOffset = min(drawerWidth, max(0, pan.translation)) }
        default:
            drawerDragging = false
            let close = pan.state == .ended && (pan.velocity > 450 || (drawerOffset > drawerWidth * 0.4 && pan.velocity > -450))
            settleDrawer(open: !close, velocity: pan.velocity)
        }
    }
    private func settleDrawer(open: Bool, velocity: CGFloat = 0) {
        let target: CGFloat = open ? 0 : drawerWidth
        let distance = abs(drawerOffset - target)
        // Carry the finger's speed into the spring, so a flick does not stall at release.
        let animation: Animation? = reduceMotion ? nil :
            .interpolatingSpring(mass: 1, stiffness: 340, damping: 36, initialVelocity: distance > 1 ? Double(abs(velocity) / distance) : 0)
        withAnimation(animation) { drawerOffset = target } completion: {
            guard !open, drawerOffset >= drawerWidth else { return }
            drawerID = nil
            Task { await focusList() }
        }
    }
    private func askToArchive(_ row: ConversationListRow) {
        if row.value["watch"].objectValue.isEmpty { archive(row) }
        else { archiveRow = row }
    }
    private func archive(_ row: ConversationListRow) {
        Task { await operation.run {
            var params = row.route.params
            params["session"] = .string(row.route.session)
            params["archived"] = .bool(true)
            _ = try await store.call("chat.archive", params: params)
            if row.matches(route) {
                route = nil; draftID = nil; compactColumn = .sidebar
                await focusList()
            }
        } }
    }
    private func pin(_ row: ConversationListRow) {
        Task { await operation.run {
            _ = try await store.call("chat.pin", params: ["station": .string(row.route.station),
                "session": .string(row.route.session), "pinned": .bool(!row.value.flag("pinned"))])
        } }
    }
    private func focusList() async {
        _ = try? await store.call("client.focus", params: ["workspace": .string(workspace),
            "visible": .bool(true), "focused": .bool(true), "chat": .null])
    }
    private func retryConnections() {
        Task { await operation.run {
            _ = try await store.call("client.wake", params: ["away": .number(0), "network": .bool(true), "retry": .bool(true)])
        } }
    }
    private func emptyState(_ value: JSONValue) -> ConversationEmptyState {
        if value.flag("loading") || value["note"].flag("reading") { return .loading }
        let failures = value["note"]["failing"].arrayValue.map { L10n.projected($0.text("text")) }.filter { !$0.isEmpty }
        if !failures.isEmpty { return .failure(failures.joined(separator: "\n")) }
        return .empty(filtered: filter != .all)
    }
}

struct ConversationListRow: Identifiable, Equatable {
    let value: JSONValue
    var peopleFirst = false
    var id: String { value.text("station") + "/" + value.text("clientKey", fallback: value.text("id", fallback: value.text("session"))) }
    var route: ChatRoute { ChatRoute(value) }
    var title: String { value.text("title", fallback: L10n.text("会话")) }
    var summary: String {
        (value["stateText"].stringValue.map { L10n.projected($0) } ?? value["decision"].text("text", fallback: value["last"].text("preview", fallback: value["last"].text("text"))))
            .components(separatedBy: .newlines).joined(separator: " ")
    }
    var metadata: String {
        let participants = ConversationParticipants(self)
        let models = participants.models.map(\.label).joined(separator: ", ")
        let people = participants.people.map(\.label).joined(separator: ", ")
        return (peopleFirst ? [people, models] : [models, people]).filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func matches(_ route: ChatRoute?) -> Bool {
        guard let route, route.station == self.route.station else { return false }
        guard [self.route.session, value.text("clientKey"), value.text("id")].contains(route.session) else { return false }
        return route.thread == nil || route.thread == self.route.thread
    }
    var editable: Bool { !value.flag("pending") && value.text("offline").isEmpty }
}

struct ConversationListSection: Equatable {
    let id: String
    let title: String
    let rows: [ConversationListRow]
    static func decode(_ value: JSONValue, filter: ConversationFilter, locale: Locale) -> [Self] {
        let days = value["days"].arrayValue
        let peopleFirst = value.text("leading") == "people"
        let decisions = days.flatMap { $0["items"].arrayValue }.filter(filter.includes).filter(ConversationFilter.needsDecision)
        var sections: [Self] = decisions.isEmpty ? [] : [Self(id: "decisions", title: L10n.text("需要决定"), rows: decisions.map { ConversationListRow(value: $0, peopleFirst: peopleFirst) })]
        for (index, day) in days.enumerated() {
            let rows = day["items"].arrayValue.filter(filter.includes).filter { !ConversationFilter.needsDecision($0) }
            guard !rows.isEmpty else { continue }
            let title: String
            if day.flag("pinned") || day["daysAgo"].intValue == -1 { title = L10n.text("已固定") }
            else if let ago = day["daysAgo"].intValue {
                if ago == 0 { title = L10n.text("今天") }
                else if ago == 1 { title = L10n.text("昨天") }
                else {
                    let formatter = DateFormatter(); formatter.locale = locale
                    if ago < 7 { formatter.dateFormat = "EEEE" } else { formatter.dateStyle = .medium }
                    title = formatter.string(from: Calendar.current.date(byAdding: .day, value: -ago, to: Date()) ?? Date())
                }
            } else { title = day.text("label") }
            sections.append(Self(id: "day:\(day["daysAgo"].intValue ?? index)", title: title, rows: rows.map { ConversationListRow(value: $0, peopleFirst: peopleFirst) }))
        }
        return sections
    }
}

enum ConversationEmptyState: Equatable { case loading, empty(filtered: Bool), failure(String) }

/// One continuous screen-edge pan, reported as it moves so a page can follow the finger.
struct EdgePan: Equatable {
    var state: UIGestureRecognizer.State
    var translation: CGFloat
    var velocity: CGFloat
}

/// The gesture belongs to a controller view (the split screen's, when there is one), never to
/// UIWindow, so presented sheets keep their own untouched gesture hierarchy.
struct EdgePanGesture: UIViewRepresentable {
    let edge: UIRectEdge
    let name: String
    let enabled: Bool
    var preferSplit = true
    let onPan: (EdgePan) -> Void
    func makeUIView(context: Context) -> EdgePanAnchor { EdgePanAnchor(edge: edge, name: name, preferSplit: preferSplit) }
    func updateUIView(_ anchor: EdgePanAnchor, context: Context) {
        anchor.onPan = onPan
        anchor.enabled = enabled
        anchor.attach()
    }
    static func dismantleUIView(_ anchor: EdgePanAnchor, coordinator: ()) { anchor.detach() }
}

final class EdgePanAnchor: UIView, UIGestureRecognizerDelegate {
    var onPan: ((EdgePan) -> Void)?
    var enabled = true { didSet { pan.isEnabled = enabled } }
    var gestureName: String { pan.name ?? "" }
    private weak var installedScope: UIView?
    private let pan = UIScreenEdgePanGestureRecognizer()
    private let preferSplit: Bool
    private let edge: UIRectEdge
    init(edge: UIRectEdge, name: String, preferSplit: Bool) {
        self.edge = edge; self.preferSplit = preferSplit
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "conversations.edgeAnchor"
        pan.edges = edge
        pan.delegate = self
        pan.name = name
        pan.addTarget(self, action: #selector(panned(_:)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() }
        else { DispatchQueue.main.async { [weak self] in self?.attach() } }
    }
    override func layoutSubviews() { super.layoutSubviews(); attach() }
    func attach() {
        guard window != nil else { return }
        var responder: UIResponder? = self
        var owner: UIViewController?
        while let current = responder {
            if let controller = current as? UIViewController { owner = controller; break }
            responder = current.next
        }
        guard let owner else { return }
        var split: UISplitViewController?
        if preferSplit {
            var ancestor: UIViewController? = owner
            while let controller = ancestor {
                if let controller = controller as? UISplitViewController { split = controller; break }
                ancestor = controller.parent
            }
        }
        guard let scope = split?.view ?? owner.view else { return }
        guard installedScope !== scope else { return }
        detach()
        scope.addGestureRecognizer(pan)
        pan.isEnabled = enabled
        installedScope = scope
    }
    func detach() {
        installedScope?.removeGestureRecognizer(pan)
        installedScope = nil
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = pan.velocity(in: installedScope)
        let inward = edge == .right ? velocity.x < 0 : velocity.x > 0
        return enabled && inward && abs(velocity.x) > abs(velocity.y)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // At the screen edge, the page drag wins over row swipes and scrolling; elsewhere it fails immediately.
        otherGestureRecognizer is UIPanGestureRecognizer
    }
    @objc private func panned(_ gesture: UIScreenEdgePanGestureRecognizer) {
        onPan?(EdgePan(state: gesture.state, translation: gesture.translation(in: installedScope).x,
                       velocity: gesture.velocity(in: installedScope).x))
    }
}

private struct ConversationTable: UIViewControllerRepresentable {
    let sections: [ConversationListSection]
    let selected: ChatRoute?
    let empty: ConversationEmptyState
    let locale: String
    let busy: Bool
    let onSelect: (ConversationListRow) -> Void
    let onRename: (ConversationListRow) -> Void
    let onArchive: (ConversationListRow) -> Void
    let onPin: (ConversationListRow) -> Void
    let onRetry: () -> Void
    func makeUIViewController(context: Context) -> ConversationTableController { ConversationTableController() }
    func updateUIViewController(_ controller: ConversationTableController, context: Context) {
        controller.onSelect = onSelect; controller.onRename = onRename; controller.onArchive = onArchive
        controller.onPin = onPin; controller.onRetry = onRetry
        controller.busy = busy
        controller.update(sections: sections, selected: selected, empty: empty, locale: locale)
    }
}

private final class ConversationTableController: UITableViewController {
    var onSelect: ((ConversationListRow) -> Void)?
    var onRename: ((ConversationListRow) -> Void)?
    var onArchive: ((ConversationListRow) -> Void)?
    var onPin: ((ConversationListRow) -> Void)?
    var onRetry: (() -> Void)?
    var busy = false
    private var sections: [ConversationListSection] = []
    private var rows: [String: ConversationListRow] = [:]
    private var dataSource: UITableViewDiffableDataSource<String, String>!
    private var language = ""
    private var emptyState: ConversationEmptyState?
    private var selectedRoute: ChatRoute?

    // Grouped: section headers scroll with their rows, so no opaque pinned band
    // cuts through the progressive blur under the header.
    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 74
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionFooterHeight = 0; tableView.estimatedSectionFooterHeight = 0
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
        tableView.contentInsetAdjustmentBehavior = .always
        tableView.estimatedSectionHeaderHeight = 30
        tableView.keyboardDismissMode = .interactive
        // Room for the floating new-chat button below the final row.
        tableView.contentInset.bottom = 84
        tableView.verticalScrollIndicatorInsets.bottom = 72
        tableView.register(ConversationCell.self, forCellReuseIdentifier: "conversation")
        dataSource = UITableViewDiffableDataSource<String, String>(tableView: tableView) { [weak self] table, path, id in
            guard let self, let row = self.rows[id], let cell = table.dequeueReusableCell(withIdentifier: "conversation", for: path) as? ConversationCell else { return nil }
            cell.configure(row)
            return cell
        }
    }
    func update(sections next: [ConversationListSection], selected: ChatRoute?, empty: ConversationEmptyState, locale: String) {
        loadViewIfNeeded()
        let languageChanged = language != locale
        let changedSections = sections != next
        let previous = rows
        let previousSections = sections
        selectedRoute = selected
        language = locale
        sections = next
        rows = Dictionary(next.flatMap(\.rows).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectCurrent: () -> Void = { [weak self] in
            guard let self else { return }
            if let row = self.rows.values.first(where: { $0.matches(self.selectedRoute) }), let path = self.dataSource.indexPath(for: row.id) {
                self.tableView.selectRow(at: path, animated: false, scrollPosition: .none)
            } else if let path = self.tableView.indexPathForSelectedRow {
                self.tableView.deselectRow(at: path, animated: false)
            }
        }
        if changedSections || languageChanged {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            var seen = Set<String>()
            var seenSections = Set<String>()
            for section in next {
                guard seenSections.insert(section.id).inserted else { continue }
                let ids = section.rows.map(\.id).filter { seen.insert($0).inserted }
                guard !ids.isEmpty else { continue }
                snapshot.appendSections([section.id]); snapshot.appendItems(ids, toSection: section.id)
            }
            let currentSnapshot = dataSource.snapshot()
            let currentItems = Set(currentSnapshot.itemIdentifiers)
            let currentSections = Set(currentSnapshot.sectionIdentifiers)
            let desiredSections = Set(snapshot.sectionIdentifiers)
            let reloadSections = Array(Set(next.filter { section in
                currentSections.contains(section.id) && desiredSections.contains(section.id) &&
                    (languageChanged || previousSections.first(where: { $0.id == section.id })?.title != section.title)
            }.map(\.id)))
            snapshot.reloadSections(reloadSections)
            let reloadedItems = Set(reloadSections.flatMap { snapshot.itemIdentifiers(inSection: $0) })
            let changed = snapshot.itemIdentifiers.filter {
                currentItems.contains($0) && !reloadedItems.contains($0) && (languageChanged || previous[$0] != rows[$0])
            }
            snapshot.reconfigureItems(changed)
            dataSource.apply(snapshot, animatingDifferences: !previous.isEmpty, completion: selectCurrent)
        } else { selectCurrent() }
        if rows.isEmpty {
            if emptyState != empty || languageChanged || tableView.backgroundView == nil { tableView.backgroundView = makeEmpty(empty) }
        } else { tableView.backgroundView = nil }
        emptyState = empty
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] { onSelect?(row) }
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let id = dataSource.snapshot().sectionIdentifiers[safe: section], let item = sections.first(where: { $0.id == id }) else { return nil }
        let label = UILabel()
        label.text = item.title
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        label.textColor = .secondaryLabel; label.adjustsFontForContentSizeCategory = true
        let container = UIView(); container.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: section == 0 ? 6 : 18), label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)])
        return container
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNormalMagnitude }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !busy, let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.editable else { return nil }
        let archive = UIContextualAction(style: .normal, title: L10n.text("归档")) { [weak self] _, _, done in self?.onArchive?(row); done(true) }
        archive.image = UIImage(systemName: "archivebox"); archive.backgroundColor = .systemOrange
        let rename = UIContextualAction(style: .normal, title: L10n.text("重命名")) { [weak self] _, _, done in self?.onRename?(row); done(true) }
        rename.image = UIImage(systemName: "pencil"); rename.backgroundColor = .systemGray
        var actions = [archive, rename]
        // Legacy stations omit pinned, so their rows cannot offer an unsupported operation.
        if row.value["pinned"].boolValue != nil {
            let pin = UIContextualAction(style: .normal, title: L10n.text(row.value.flag("pinned") ? "取消固定" : "固定")) { [weak self] _, _, done in self?.onPin?(row); done(true) }
            pin.image = UIImage(systemName: row.value.flag("pinned") ? "pin.slash" : "pin")
            pin.backgroundColor = .systemIndigo; actions.append(pin)
        }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    private func makeEmpty(_ state: ConversationEmptyState) -> UIView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        let title = UILabel(); title.font = .preferredFont(forTextStyle: .headline); title.textAlignment = .center
        let body = UILabel(); body.font = .preferredFont(forTextStyle: .subheadline); body.textColor = .secondaryLabel
        body.numberOfLines = 0; body.textAlignment = .center
        switch state {
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating(); stack.addArrangedSubview(spinner)
            title.text = L10n.text("正在读取会话…"); stack.accessibilityIdentifier = "conversations.loading"
        case .empty(let filtered):
            let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right")); icon.tintColor = .tertiaryLabel
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 36); stack.addArrangedSubview(icon)
            title.text = L10n.text("暂无会话")
            body.text = L10n.text(filtered ? "没有符合此筛选条件的会话。" : "选择节点，新建一个会话。")
            stack.accessibilityIdentifier = "conversations.empty"
        case .failure(let message):
            title.text = L10n.text("暂时无法读取会话"); body.text = message
            let retry = UIButton(type: .system); retry.setTitle(L10n.text("重试"), for: .normal)
            retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
            retry.accessibilityIdentifier = "conversations.connectionRetry"; stack.addArrangedSubview(retry)
        }
        stack.addArrangedSubview(title); stack.addArrangedSubview(body)
        let container = UIView(); stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor), stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -30)])
        return container
    }
}

private final class ConversationCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let participants = ConversationAsideView(frame: .zero)
    private let mark = UIView()
    private let accessory = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let highlight = UIView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        // A rounded, inset selection reads as the current row in the iPad split
        // without the full-bleed grey band of a plain table.
        highlight.backgroundColor = .tertiarySystemFill
        highlight.layer.cornerRadius = 14; highlight.layer.cornerCurve = .continuous
        let selected = UIView(); selected.addSubview(highlight)
        selectedBackgroundView = selected
        let top = UIStackView(arrangedSubviews: [titleLabel, spinner, accessory]); top.alignment = .center; top.spacing = 6
        let bottom = UIStackView(arrangedSubviews: [summaryLabel, participants]); bottom.alignment = .center; bottom.spacing = 10
        let stack = UIStackView(arrangedSubviews: [top, bottom]); stack.axis = .vertical; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(stack)
        mark.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(mark)
        let accessoryWidth = accessory.widthAnchor.constraint(equalToConstant: 13)
        accessoryWidth.priority = .init(999)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            // The state dot lives in the leading gutter, so titles never shift sideways.
            mark.widthAnchor.constraint(equalToConstant: 7), mark.heightAnchor.constraint(equalToConstant: 7),
            mark.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            mark.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            accessoryWidth, accessory.heightAnchor.constraint(equalToConstant: 13)])
        mark.layer.cornerRadius = 3.5
        for label in [titleLabel, summaryLabel] {
            label.numberOfLines = 1; label.lineBreakMode = .byTruncatingTail; label.adjustsFontForContentSizeCategory = true
        }
        summaryLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14))
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        participants.setContentCompressionResistancePriority(.required, for: .horizontal)
        participants.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        [accessory, spinner].forEach { $0.setContentHuggingPriority(.required, for: .horizontal); $0.setContentCompressionResistancePriority(.required, for: .horizontal) }
        accessory.tintColor = .tertiaryLabel; accessory.contentMode = .scaleAspectFit
        accessory.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        spinner.hidesWhenStopped = true; spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds.insetBy(dx: 8, dy: 1)
    }
    override func prepareForReuse() { super.prepareForReuse(); participants.clear() }
    func configure(_ row: ConversationListRow) {
        let unread = row.value.flag("unread")
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: unread ? .bold : .semibold))
        titleLabel.text = row.title; summaryLabel.text = row.summary
        participants.configure(ConversationParticipants(row))
        participants.accessibilityIdentifier = "conversation.participants.\(row.value.text("id"))"
        titleLabel.accessibilityIdentifier = "conversation.title.\(row.value.text("id"))"
        summaryLabel.accessibilityIdentifier = "conversation.summary.\(row.value.text("id"))"
        let subdued = !row.value.text("offline").isEmpty || row.value.flag("settled")
        titleLabel.textColor = subdued ? .secondaryLabel : .label
        summaryLabel.textColor = subdued ? .tertiaryLabel : .secondaryLabel
        participants.alpha = subdued ? 0.55 : 1
        let tone = row.value.text("tone")
        mark.isHidden = tone.isEmpty && !unread
        mark.backgroundColor = tone == "alert" ? .systemRed : tone == "wait" ? .systemOrange : tone == "busy" ? .systemGreen : tintColor
        let offline = !row.value.text("offline").isEmpty || !row.value.text("reconnecting").isEmpty
        accessory.image = UIImage(systemName: offline ? "network.slash" : "pin.fill")
        accessory.isHidden = !offline && !row.value.flag("pinned")
        if row.value.flag("pending") { spinner.startAnimating() } else { spinner.stopAnimating() }
        accessibilityIdentifier = "conversation.open.\(row.value.text("id"))"
        accessibilityLabel = [row.title, row.summary, row.metadata, L10n.projected(row.value.text("offline")), L10n.projected(row.value.text("reconnecting"))].filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = [.button]
    }
}

/// Matches web/src/RowPicture.tsx: one icon per maker/runtime and a small overlapping people group.
private struct ConversationParticipants: Equatable {
    struct Model: Equatable { let maker: String; let runtime: String; let label: String }
    struct Person: Equatable {
        let id: String
        let name: String
        let label: String
        let picture: String
        let starter: Bool
    }
    let models: [Model]
    let people: [Person]
    let peopleFirst: Bool
    init(_ row: ConversationListRow) {
        peopleFirst = row.peopleFirst
        var agents = row.value["agents"].arrayValue
        if agents.isEmpty {
            let last = row.value["last"]["by"]
            if !last["maker"].objectValue.isEmpty || last.text("kind") == "agent" { agents = [last] }
        }
        var seenMakers = Set<String>()
        models = agents.compactMap { agent in
            let session = agent["session"]
            let maker = agent["maker"].objectValue.isEmpty ? session["maker"] : agent["maker"]
            let runtime = agent.text("runtime", fallback: session.text("runtime", fallback: "codex"))
            guard seenMakers.insert(maker.text("id", fallback: runtime)).inserted else { return nil }
            return Model(maker: maker.text("id"), runtime: runtime,
                         label: L10n.projected(agent.text("agentText", fallback: session.text("agentText", fallback: maker.text("name", fallback: agent.text("model", fallback: runtime))))))
        }
        var records = row.value["people"].arrayValue
        // Older stations expose only the creator. Keep that person's real portrait where available.
        if records.isEmpty && !row.value["creator"].objectValue.isEmpty { records = [row.value["creator"]] }
        let showPeople = peopleFirst || records.contains { !$0["shown"].flag("mine") }
        var seenPeople = Set<String>()
        people = showPeople ? records.compactMap { person in
            let shown = person["shown"]
            let name = shown.text("name", fallback: person.text("name", fallback: shown.text("display")))
            let id = person.text("id", fallback: person.text("email", fallback: name))
            guard seenPeople.insert(id).inserted else { return nil }
            return Person(id: person.text("email", fallback: id), name: name,
                          label: shown.flag("mine") ? L10n.text("你") : shown.text("display", fallback: name),
                          picture: shown.text("picture"),
                          starter: records.count > 1 && !id.isEmpty && id == row.value["creator"].text("id"))
        } : []
    }
}

private final class ConversationAsideView: UIStackView {
    private let models = UIStackView()
    private let people = UIStackView()
    private let modelIcons = (0..<3).map { _ in UIImageView() }
    private let personIcons = (0..<3).map { _ in ConversationPersonAvatar(frame: .zero) }
    private let moreModels = UILabel()
    private let morePeople = UILabel()
    private var previous: ConversationParticipants?
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal; alignment = .center; spacing = 7
        models.axis = .horizontal; models.alignment = .center; models.spacing = 4
        people.axis = .horizontal; people.alignment = .center; people.spacing = -3
        for icon in modelIcons {
            icon.contentMode = .scaleAspectFit; icon.tintColor = .secondaryLabel
            let width = icon.widthAnchor.constraint(equalToConstant: 16)
            width.priority = .init(999); width.isActive = true
            icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            models.addArrangedSubview(icon)
        }
        for icon in personIcons {
            let width = icon.widthAnchor.constraint(equalToConstant: 20)
            width.priority = .init(999); width.isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
            people.addArrangedSubview(icon)
        }
        for label in [moreModels, morePeople] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabel
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        models.addArrangedSubview(moreModels); people.addArrangedSubview(morePeople)
        people.setCustomSpacing(4, after: personIcons[2])
        addArrangedSubview(models); addArrangedSubview(people)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ value: ConversationParticipants) {
        guard previous != value else { return }
        previous = value
        if (arrangedSubviews.first === people) != value.peopleFirst {
            removeArrangedSubview(models); removeArrangedSubview(people)
            insertArrangedSubview(value.peopleFirst ? people : models, at: 0)
            addArrangedSubview(value.peopleFirst ? models : people)
        }
        for (index, icon) in modelIcons.enumerated() {
            icon.isHidden = index >= value.models.count
            guard index < value.models.count else { icon.image = nil; continue }
            let model = value.models[index]
            icon.image = ModelLogo.image(maker: model.maker, runtime: model.runtime) ?? UIImage(systemName: "sparkles")
            icon.accessibilityLabel = model.label
        }
        for (index, icon) in personIcons.enumerated() {
            icon.isHidden = index >= value.people.count
            if index < value.people.count { icon.configure(value.people[index]) }
            else { icon.clear() }
        }
        moreModels.text = "+\(max(0, value.models.count - 3))"
        moreModels.isHidden = value.models.count <= 3
        morePeople.text = "+\(max(0, value.people.count - 3))"
        morePeople.isHidden = value.people.count <= 3
        models.isHidden = value.models.isEmpty; people.isHidden = value.people.isEmpty
        isHidden = value.models.isEmpty && value.people.isEmpty
    }
    func clear() {
        previous = nil
        personIcons.forEach { $0.clear() }
    }
}

private final class ConversationPersonAvatar: UIView {
    private let image = UIImageView()
    private let initial = UILabel()
    private var identity: ConversationParticipants.Person?
    private var request: UUID?
    private var url: URL?
    private static let tones: [UIColor] = [
        UIColor(red: 0.79, green: 0.58, blue: 0.30, alpha: 1), UIColor(red: 0.44, green: 0.56, blue: 0.75, alpha: 1),
        UIColor(red: 0.49, green: 0.60, blue: 0.44, alpha: 1), UIColor(red: 0.69, green: 0.48, blue: 0.61, alpha: 1),
        UIColor(red: 0.55, green: 0.51, blue: 0.78, alpha: 1), UIColor(red: 0.78, green: 0.49, blue: 0.42, alpha: 1)]
    override init(frame: CGRect) {
        super.init(frame: frame)
        image.contentMode = .scaleAspectFill; image.clipsToBounds = true
        initial.textAlignment = .center; initial.font = .systemFont(ofSize: 10, weight: .medium); initial.textColor = .white
        addSubview(image); addSubview(initial)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ConversationPersonAvatar, _: UITraitCollection) in
            view.layer.borderColor = UIColor.label.cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = identity?.starter == true ? 2 : 0
        image.frame = bounds.insetBy(dx: inset, dy: inset); initial.frame = image.frame
        image.layer.cornerRadius = image.bounds.width / 2
        initial.layer.cornerRadius = image.layer.cornerRadius; initial.clipsToBounds = true
        layer.cornerRadius = bounds.width / 2
    }
    func configure(_ value: ConversationParticipants.Person) {
        guard identity != value else { return }
        clear(); identity = value
        let hash = value.id.utf16.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
        initial.backgroundColor = Self.tones[Int(hash % UInt32(Self.tones.count))]
        let words = value.name.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_./"))).filter { !$0.isEmpty }
        initial.text = String((words.last ?? value.name).prefix(1)).uppercased()
        if initial.text?.isEmpty != false { initial.text = "?" }
        layer.borderWidth = value.starter ? 1 : 0; layer.borderColor = UIColor.label.cgColor
        accessibilityLabel = value.label
        setNeedsLayout()
        guard let address = URL(string: value.picture), ["https", "http"].contains(address.scheme?.lowercased() ?? "") else { return }
        url = address
        request = ConversationAvatarImages.shared.image(at: address) { [weak self] loaded in
            guard let self, self.identity == value, self.url == address, let loaded else { return }
            self.image.image = loaded; self.initial.isHidden = true
        }
    }
    func clear() {
        if let url, let request { ConversationAvatarImages.shared.cancel(request, at: url) }
        request = nil; url = nil; identity = nil
        image.image = nil; initial.isHidden = false
    }
}

/// URL observers share one request, and decoded portraits never exceed 64 px for these 20 pt views.
@MainActor private final class ConversationAvatarImages {
    static let shared = ConversationAvatarImages()
    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>(); cache.countLimit = 200; cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()
    private struct Flight {
        let id: UUID
        let task: URLSessionDataTask
        var observers: [UUID: (UIImage?) -> Void]
    }
    private var flights: [URL: Flight] = [:]
    private var failedUntil: [URL: Date] = [:]
    func image(at url: URL, completion: @escaping (UIImage?) -> Void) -> UUID? {
        if let image = cache.object(forKey: url as NSURL) { completion(image); return nil }
        if let until = failedUntil[url], until > Date() { return nil }
        let observer = UUID()
        if flights[url] != nil { flights[url]?.observers[observer] = completion; return observer }
        let identity = UUID()
        let task = session.dataTask(with: url) { [weak self] data, response, _ in
            var image: UIImage?
            if let data, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
               let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                image = UIImage(cgImage: thumbnail, scale: 3, orientation: .up)
            }
            let decoded = image
            Task { @MainActor in self?.finish(url: url, identity: identity, image: decoded) }
        }
        flights[url] = Flight(id: identity, task: task, observers: [observer: completion])
        task.resume()
        return observer
    }
    func cancel(_ observer: UUID, at url: URL) {
        guard var flight = flights[url] else { return }
        flight.observers.removeValue(forKey: observer)
        if flight.observers.isEmpty { flight.task.cancel(); flights.removeValue(forKey: url) }
        else { flights[url] = flight }
    }
    private func finish(url: URL, identity: UUID, image: UIImage?) {
        guard let flight = flights[url], flight.id == identity else { return }
        flights.removeValue(forKey: url)
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
            failedUntil.removeValue(forKey: url)
        } else { failedUntil[url] = Date().addingTimeInterval(60) }
        flight.observers.values.forEach { $0(image) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
