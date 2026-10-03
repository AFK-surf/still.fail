import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatDraft: Equatable {
    var text = ""
    var quotes: [JSONValue] = []
    var files: [JSONValue] = []
    var payload: [String: JSONValue] { ["text": .string(text), "quotes": .array(quotes), "files": .array(files)] }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quotes.isEmpty && files.isEmpty }
    init() {}
    init(_ value: JSONValue) { text = value.text("text"); quotes = value["quotes"].arrayValue; files = value["files"].arrayValue }
}

/// Draft keystrokes and composer geometry updates must not decode the entire
/// conversation again. This reference cache has no observed mutations, so a
/// cache lookup during `body` does not trigger another SwiftUI render pass.
@MainActor final class ChatTimelineProjection {
    private struct Key: Equatable {
        var topics: [ObjectIdentifier: Int]
        var outgoing: ChatDraft?
        var language: String
    }
    private var key: Key?
    private var cachedRows: [ChatTimelineRow] = []
    private(set) var revision = 0
    /// Topics are compared by their change counters, never document by document:
    /// a streaming token used to compare the entire conversation on every frame.
    /// Every topic's value is read, so the calling body observes each of them.
    func rows(topic: CoreTopic?, outgoing: ChatDraft?, lives: [String: CoreTopic], histories: [String: CoreTopic], language: String) -> [ChatTimelineRow] {
        let value = topic?.value ?? .null
        let liveValues = lives.compactMapValues { $0.value }, historyValues = histories.compactMapValues { $0.value }
        var topics: [ObjectIdentifier: Int] = [:]
        for observed in [topic].compactMap({ $0 }) + Array(lives.values) + Array(histories.values) { topics[ObjectIdentifier(observed)] = observed.revision }
        let next = Key(topics: topics, outgoing: outgoing, language: language)
        if key == next { return cachedRows }
        key = next
        cachedRows = ChatTimeline.rows(value: value, initialOutgoing: outgoing, lives: liveValues, histories: historyValues)
        revision += 1
        return cachedRows
    }
}

/// Wire shapes shared by the view and protocol tests; routing stays in client/core.
enum ChatProtocol {
    static func thread(route: ChatRoute, value: JSONValue) -> Int? {
        value["thread"]["id"].intValue ?? route.thread
    }

    static func canCompose(route: ChatRoute, value: JSONValue) -> Bool {
        guard !value.flag("archived") else { return false }
        let surface = value["thread"].text("surface")
        guard surface.isEmpty || surface == "ember" else { return false }
        if !value["thread"].objectValue.isEmpty { return true }
        // A made pending chat can still be waiting for its first thread value.
        return !route.session.isEmpty && (value.flag("pending") ||
            (route.session.hasPrefix("new:") && !value.text("key").isEmpty))
    }

    private static func target(route: ChatRoute, value: JSONValue) -> [String: JSONValue] {
        var params: [String: JSONValue] = ["station": .string(route.station)]
        if let thread = thread(route: route, value: value) { params["thread"] = .number(Double(thread)) }
        else { params["session"] = .string(route.session) }
        return params
    }

    static func send(route: ChatRoute, value: JSONValue, draft: ChatDraft) -> [String: JSONValue] {
        var params = target(route: route, value: value)
        params["text"] = .string(draft.text)
        params["quotes"] = .array(draft.quotes)
        params["attachments"] = .array(draft.files)
        params["client"] = .string("ios")
        return params
    }

    static func place(route: ChatRoute, value: JSONValue, seq: Int?, offset: Double?) -> [String: JSONValue]? {
        guard let thread = thread(route: route, value: value), seq == nil || seq! >= 0 else { return nil }
        return ["station": .string(route.station), "thread": .number(Double(thread)),
                "seq": seq.map { .number(Double($0)) } ?? .null,
                "offset": seq != nil && offset?.isFinite == true ? .number(offset!) : .null]
    }
    static func retry(route: ChatRoute, value: JSONValue, id: String) -> [String: JSONValue] {
        var params = target(route: route, value: value)
        params["id"] = .string(id)
        return params
    }

    private static func chatOf(route: ChatRoute, value: JSONValue, end: Bool) -> JSONValue {
        var chat: [String: JSONValue] = ["station": .string(route.station), "session": .string(route.session), "end": .bool(end)]
        if let thread = thread(route: route, value: value) { chat["thread"] = .number(Double(thread)) }
        return .object(chat)
    }

    static func focus(route: ChatRoute, value: JSONValue, workspace: String, visible: Bool, readerAtEnd: Bool) -> [String: JSONValue] {
        ["workspace": .string(workspace), "chat": chatOf(route: route, value: value, end: readerAtEnd && !value.flag("newer")),
         "visible": .bool(visible), "focused": .bool(visible)]
    }

    static func depart(route: ChatRoute, value: JSONValue) -> [String: JSONValue] {
        // Conditional departure cannot clear a different chat that has just appeared.
        ["left": chatOf(route: route, value: value, end: false)]
    }
}

struct ExportedAttachment: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chatVisible) private var chatVisible
    let route: ChatRoute
    let workspace: String
    let composerSession: ChatComposerSession?
    private let carriedDraft: Bool
    @State private var initialOutgoing: ChatDraft?
    @State private var timelineProjection = ChatTimelineProjection()
    @State private var composerFooterHeight: CGFloat = 68
    @State private var liveTopics: [String: CoreTopic] = [:]
    @State private var historyTopics: [String: CoreTopic] = [:]
    // Subscriptions end with this page's identity, not with onDisappear, which a
    // navigation transition can deliver after the page has appeared again.
    @State private var lease = TopicLease()
    @State private var showHistory = false
    @State private var showInfo = false
    @State private var topic: CoreTopic?
    @State private var generation = 0
    @State private var draft = ChatDraft()
    @State private var draftLoaded = false
    @State private var draftEditedBeforeLoad = false
    @State private var draftReadError: String?
    @State private var operation = ViewOperation()
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var submitted: ChatDraft?
    @State private var uncertainSend = false
    @State private var rename = false
    @State private var exporting = false
    @State private var exportFile: ExportedAttachment?
    @State private var exportName = L10n.text("附件")
    @State private var readerAtEnd = true
    @State private var readerPositionReady = false
    @State private var jumpToEnd = 0
    @State private var visitEpoch: Int?
    @State private var inView = false
    @State private var subscribedGeneration = -1
    @State private var paused = false
    private var draftIdentity: String { (store.selectedAccountID ?? "") + ":" + route.session }
    private var draftParams: [String: JSONValue] { ["station": .string(route.station), "chat": .string(draftIdentity)] }
    private var value: JSONValue { topic?.value ?? .null }
    private var thread: Int? { ChatProtocol.thread(route: route, value: value) }
    private var sendable: Bool { ChatProtocol.canCompose(route: route, value: value) }

    init(route: ChatRoute, workspace: String, initialOutgoing: ChatDraft? = nil, initialDraft: ChatDraft? = nil, composerSession: ChatComposerSession? = nil) {
        self.route = route; self.workspace = workspace; self.composerSession = composerSession
        carriedDraft = initialDraft != nil
        _initialOutgoing = State(initialValue: initialOutgoing)
        _draft = State(initialValue: initialDraft ?? ChatDraft())
    }

    private var agents: [JSONValue] { value["agents"].arrayValue }
    private var liveKeys: [String] { agents.map { $0["session"].text("key", fallback: $0.text("key")) }.filter { !$0.isEmpty } }
    private var slackKeys: [String] { ChatSlack.historyKeys(value: value) }
    private var timeline: [ChatTimelineRow] {
        timelineProjection.rows(topic: topic, outgoing: initialOutgoing, lives: liveTopics, histories: historyTopics, language: locale.identifier)
    }
    /// Cheap stand-ins for the outbox and messages, so onChange never compares the conversation.
    private var outboxSignature: [String] { value["outbox"].arrayValue.map { $0.text("id") + ":" + $0.text("state") + ":" + ($0["seq"].intValue.map(String.init) ?? "") } }
    private var messagesSignature: [Int] {
        let messages = value["messages"].arrayValue
        return [messages.count, messages.first?["seq"].intValue ?? -1, messages.last?["seq"].intValue ?? -1]
    }

    var body: some View {
        let _ = locale.identifier
        VStack(spacing: 0) {
            if let error = topic?.error { FailureNotice(message: error.localizedDescription, retained: topic?.value != nil, retry: restart) }
            if let connection = value["connection"]["text"].stringValue { Text(L10n.projected(connection)).font(.footnote).foregroundStyle(.secondary).padding(.horizontal).accessibilityIdentifier("chat.connection") }
            if value.flag("pending"), value["failed"].stringValue != nil {
                PendingChatNotice(failed: true, hasOutgoing: !value["outbox"].arrayValue.isEmpty)
            }
            messages.ignoresSafeArea(.container, edges: [.top, .bottom])
            if let error = operation.error { FailureNotice(message: uncertainSend ? L10n.text("暂时无法确认发送结果。请先查看会话状态，不要重复发送。") : error) }
            if let error = draftReadError { FailureNotice(message: error, retry: { Task { await loadDraft() } }) }
            if let error = uploadError { FailureNotice(message: error) }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(value.text("title", fallback: L10n.text("会话")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background { ProgressiveHeaderBlur().frame(width: 0, height: 0).allowsHitTesting(false) }
        // safeAreaBar paints a full-width system backdrop. A plain inset keeps
        // the area around the floating native glass surfaces transparent.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Keep the bar mounted while the topic loads and when a chat is empty.
            if topic?.value == nil || sendable {
                VStack(spacing: 6) {
                    draftAccessories
                    ChatComposer(text: $draft.text, busy: operation.busy || uploading, enabled: draftLoaded && sendable && !draft.isEmpty && !uncertainSend,
                                 attachmentEnabled: draftLoaded && !route.session.isEmpty, attachFiles: { showFiles = true }, attachPhotos: { showPhotos = true }, send: send, session: composerSession)
                }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 760).frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        if abs(composerFooterHeight - height) > 0.5 { composerFooterHeight = height }
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showHistory = true } label: { Label(L10n.text("执行历史"), systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("chat.history")
                Button { showInfo = true } label: { Label(L10n.text("对话信息"), systemImage: "ellipsis") }
                    .accessibilityIdentifier("chat.menu")
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(station: route.station, agents: agents).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInfo) {
            ChatInfoSheet(route: route, workspace: workspace, value: value, rename: { rename = true }, archive: archive,
                          latest: { page("chat.latest") }, checkSend: uncertainSend ? restart : nil)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $rename) {
            RenameSheet(title: L10n.text("重命名会话"), initial: value.text("title")) { name in
                var params = route.params; params["title"] = .string(name)
                _ = try await store.call("chat.rename", params: params)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { uploadFile(url) }
            case .failure: uploadError = L10n.text("没有读取到文件，请重新选择。")
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in if let item { uploadPhoto(item) } }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .data, defaultFilename: exportName) { result in
            if case .failure = result { uploadError = L10n.text("附件未能保存，请重试。") }
        }
        .task(id: generation) {
            if visitEpoch == nil { visitEpoch = store.scopeEpoch }
            guard visitEpoch == store.scopeEpoch else { return }
            inView = true
            if topic == nil || generation != subscribedGeneration {
                let next = store.subscribe("chat", params: route.params)
                lease.replace(next); topic = next; subscribedGeneration = generation
            }
            if !draftLoaded { await loadDraft() }
            reconcileInitialOutgoing()
            await focus()
        }
        .onChange(of: draft) { _, _ in
            if draftLoaded { persistDraft() } else { draftEditedBeforeLoad = true }
        }
        .onChange(of: outboxSignature) { _, _ in reconcileSubmission(); reconcileInitialOutgoing() }
        .onChange(of: messagesSignature) { _, _ in reconcileInitialOutgoing() }
        .onChange(of: chatVisible) { _, visible in
            Task {
                if visible { await focus() }
                else if visitEpoch == store.scopeEpoch { _ = try? await store.call("client.focus", params: ChatProtocol.depart(route: route, value: value)) }
            }
        }
        .onChange(of: scenePhase) { _, _ in Task { await focus() } }
        .onChange(of: thread) { _, _ in Task { await focus() } }
        .onChange(of: value.flag("newer")) { _, _ in Task { await focus() } }
        .onDisappear(perform: depart)
        .accessibilityIdentifier("chat.page")
    }
    private func depart() {
        inView = false
        let epoch: Int? = visitEpoch
        let params: [String: JSONValue] = ChatProtocol.depart(route: route, value: value)
        let store = store
        Task { @MainActor in
            guard epoch == store.scopeEpoch else { return }
            _ = try? await store.call("client.focus", params: params)
        }
    }

    private var messages: some View {
        ChatMessageList(rows: timeline, store: store, route: route, thread: thread, busy: operation.busy, jumpToEnd: jumpToEnd,
                        atEnd: $readerAtEnd, quote: quote, download: download, retry: retry, page: page,
                        initialSeq: value["at"].intValue, initialOffset: value["atOffset"].numberValue, newer: value.flag("newer"),
                        topicLoaded: topic?.value != nil, rememberPlace: rememberPlace, positionReady: { readerPositionReady = true },
                        footerHeight: topic?.value == nil || sendable ? composerFooterHeight : 0,
                        visibilityChanged: setVisible)
            .onChange(of: readerAtEnd) { _, _ in Task { await focus() } }
            .onChange(of: readerPositionReady) { _, _ in Task { await focus() } }
            .task(id: liveKeys) {
                let wanted = Set(liveKeys)
                for key in liveTopics.keys where !wanted.contains(key) { lease.drop(key: "live:" + key); liveTopics.removeValue(forKey: key) }
                for key in liveKeys where liveTopics[key] == nil {
                    let next = store.subscribe("live", params: ["station": .string(route.station), "key": .string(key)])
                    lease.replace(next, key: "live:" + key); liveTopics[key] = next
                }
            }
            // Agents that also talk in Slack: their histories carry those words into this timeline.
            .task(id: slackKeys) {
                let wanted = Set(slackKeys)
                for key in historyTopics.keys where !wanted.contains(key) { lease.drop(key: "history:" + key); historyTopics.removeValue(forKey: key) }
                for key in slackKeys where historyTopics[key] == nil {
                    let next = store.subscribe("history", params: ["station": .string(route.station), "key": .string(key)])
                    lease.replace(next, key: "history:" + key); historyTopics[key] = next
                }
            }
    }
    private func reconcileInitialOutgoing() {
        if let outgoing = initialOutgoing, ChatTimeline.contains(outgoing, value: value) { initialOutgoing = nil }
    }
    private var draftAccessories: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(draft.quotes.enumerated()), id: \.offset) { index, quote in
                HStack {
                    Text(L10n.format("引用：%@", quote.text("text"))).font(.footnote).lineLimit(2).accessibilityIdentifier("composer.quote.\(index)")
                    Spacer()
                    Button(L10n.text("移除引用"), systemImage: "xmark") { draft.quotes.remove(at: index) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("composer.removeQuote.\(index)")
                }
            }
            ForEach(Array(draft.files.enumerated()), id: \.offset) { index, file in
                HStack {
                    Label(file.text("name"), systemImage: "paperclip").font(.footnote).accessibilityIdentifier("composer.file.\(index)")
                    Spacer()
                    Button(L10n.text("移除附件"), systemImage: "xmark") { draft.files.remove(at: index) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("composer.removeFile.\(index)")
                }
            }
            if uploading { ProgressView(L10n.text("正在上传附件…")).accessibilityIdentifier("composer.uploading") }
        }.disabled(operation.busy || uploading)
    }
    private func restart() { generation += 1 }
    /// A covered page (back on the list on iPhone, where its identity is kept) stops
    /// its chat, live and history subscriptions, and takes them up again when shown.
    private func setVisible(_ visible: Bool) {
        if visible {
            guard paused else { return }
            paused = false; generation += 1
        } else {
            guard !paused, topic != nil else { return }
            paused = true
            lease.cancelAll(); topic = nil; liveTopics = [:]; historyTopics = [:]
        }
    }
    private func loadDraft() async {
        guard visitEpoch == store.scopeEpoch else { return }
        let epoch = store.scopeEpoch
        do {
            let saved = try await store.call("draft.get", params: draftParams)
            guard epoch == store.scopeEpoch else { return }
            if !draftLoaded && !carriedDraft { draft = NewChatDraftState.merge(saved: ChatDraft(saved), typed: draft) }
            draftLoaded = true; draftReadError = nil
            // Save a handoff or typing during the async read even if the reader
            // navigates back before another keystroke.
            if carriedDraft || draftEditedBeforeLoad { persistDraft() }
        } catch {
            guard epoch == store.scopeEpoch else { return }
            draftReadError = L10n.text("草稿暂时无法读取。请重试后继续，避免覆盖已保存的草稿。")
        }
    }
    private func persistDraft() {
        guard visitEpoch == store.scopeEpoch else { return }
        let epoch = store.scopeEpoch
        var params = draftParams; params.merge(draft.payload) { _, new in new }
        Task {
            guard epoch == store.scopeEpoch else { return }
            do { _ = try await store.call("draft.put", params: params) }
            catch {
                guard epoch == store.scopeEpoch else { return }
                draftReadError = L10n.text("草稿未能保存。内容仍保留在当前页面，请检查连接后重试。")
            }
        }
    }
    private func quote(_ message: JSONValue) {
        guard visitEpoch == store.scopeEpoch, draftLoaded else { return }
        var fields: [String: JSONValue] = ["author": .string(message["by"].text("name", fallback: message.text("author"))), "text": message["text"], "comment": .string(""), "role": message["authorKind"]]
        if let ts = message["ts"].stringValue { fields["ts"] = .string(ts) }
        draft.quotes.append(.object(fields))
    }
    private func focus() async {
        guard inView, chatVisible, visitEpoch == store.scopeEpoch else { return }
        let params = ChatProtocol.focus(route: route, value: value, workspace: workspace, visible: scenePhase == .active, readerAtEnd: readerAtEnd && readerPositionReady)
        _ = try? await store.call("client.focus", params: params)
    }
    private func rememberPlace(_ seq: Int?, _ offset: Double?) {
        guard visitEpoch == store.scopeEpoch,
              let params = ChatProtocol.place(route: route, value: value, seq: seq, offset: offset) else { return }
        let epoch = store.scopeEpoch
        Task { guard epoch == store.scopeEpoch else { return }; _ = try? await store.call("chat.place", params: params) }
    }
    private func page(_ name: String) {
        guard let thread else { return }
        if name == "chat.latest" { readerAtEnd = true; jumpToEnd += 1 }
        Task { await operation.run { _ = try await store.call(name, params: ["station": .string(route.station), "thread": .number(Double(thread))]) } }
    }
    private func archive() {
        Task { await operation.run {
            var params = route.params; params["session"] = .string(route.session); params["archived"] = .bool(!value.flag("archived"))
            _ = try await store.call("chat.archive", params: params)
        } }
    }
    private func send() {
        guard visitEpoch == store.scopeEpoch, draftLoaded, sendable, !draft.isEmpty, !operation.busy, !uploading, !uncertainSend else { return }
        let epoch = store.scopeEpoch
        readerAtEnd = true; jumpToEnd += 1
        let sending = draft
        let params = ChatProtocol.send(route: route, value: value, draft: sending)
        submitted = sending
        Task {
            guard epoch == store.scopeEpoch else { return }
            await operation.run {
                _ = try await store.call("chat.send", params: params)
                guard epoch == store.scopeEpoch else { return }
                if draft == sending { draft = ChatDraft() }
                submitted = nil; uncertainSend = false
            }
            guard epoch == store.scopeEpoch else { return }
            if operation.error != nil {
                uncertainSend = ["timeout_uncertain", "core_restarted", "cancelled_uncertain"].contains(operation.code ?? "")
                reconcileSubmission()
            }
        }
    }
    private func reconcileSubmission() {
        guard visitEpoch == store.scopeEpoch, let sent = submitted else { return }
        let owned = value["outbox"].arrayValue.contains { $0.text("text") == sent.text && $0["quotes"].arrayValue == sent.quotes && $0["attachments"].arrayValue == sent.files }
        if owned { if draft == sent { draft = ChatDraft() }; submitted = nil; uncertainSend = false }
    }
    private func retry(_ outgoing: JSONValue) {
        guard visitEpoch == store.scopeEpoch, !operation.busy, let id = outgoing["id"].stringValue else { return }
        let epoch = store.scopeEpoch
        let params = ChatProtocol.retry(route: route, value: value, id: id)
        Task {
            guard epoch == store.scopeEpoch else { return }
            await operation.run { _ = try await store.call("chat.retry", params: params) }
        }
    }
    private func uploadFile(_ url: URL) {
        guard visitEpoch == store.scopeEpoch, draftLoaded, !uploading, !operation.busy else { return }
        uploading = true; uploadError = nil
        let epoch = store.scopeEpoch
        Task {
            defer { uploading = false }
            do {
                let encoded = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try Data(contentsOf: url).base64EncodedString()
                }.value
                try await upload(name: url.lastPathComponent, encoded: encoded, epoch: epoch)
            } catch {
                guard epoch == store.scopeEpoch else { return }
                uploadError = (error as? CoreFailure)?.localizedDescription ?? L10n.text("文件未能上传。草稿仍保留，请重新选择文件后重试。")
            }
        }
    }
    private func uploadPhoto(_ item: PhotosPickerItem) {
        guard visitEpoch == store.scopeEpoch, draftLoaded, !uploading, !operation.busy else { return }
        uploading = true; uploadError = nil
        let epoch = store.scopeEpoch
        Task {
            defer { uploading = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CoreFailure(code: "file_unavailable") }
                let encoded = await Task.detached { data.base64EncodedString() }.value
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                try await upload(name: L10n.text("照片") + ".\(ext)", encoded: encoded, epoch: epoch)
            } catch {
                guard epoch == store.scopeEpoch else { return }
                uploadError = (error as? CoreFailure)?.localizedDescription ?? L10n.text("照片未能上传，请重新选择后重试。")
            }
        }
    }
    private func upload(name: String, encoded: String, epoch: Int) async throws {
        guard epoch == store.scopeEpoch else { return }
        let saved = try await store.call("station.upload", params: ["station": .string(route.station), "name": .string(name), "bytes": .string(encoded)])
        guard epoch == store.scopeEpoch else { return }
        guard !saved.text("path").isEmpty else { throw CoreFailure(code: "invalid_response") }
        draft.files.append(saved)
    }
    private func download(_ attachment: JSONValue) {
        guard visitEpoch == store.scopeEpoch else { return }
        let epoch = store.scopeEpoch
        Task { await operation.run {
            guard epoch == store.scopeEpoch else { return }
            let name = attachment.text("path").split(separator: "/").last.map(String.init) ?? attachment.text("name")
            let saved = try await store.call("station.file", params: ["station": .string(route.station), "key": .string(route.session), "name": .string(name)])
            let bytes = saved.text("bytes")
            let decoded = await Task.detached { Data(base64Encoded: bytes) }.value
            guard epoch == store.scopeEpoch else { return }
            guard let decoded else { throw CoreFailure(code: "invalid_response") }
            exportFile = ExportedAttachment(bytes: decoded); exportName = attachment.text("name"); exporting = true
        } }
    }
}

private struct PendingChatNotice: View {
    @Environment(\.locale) private var locale
    let failed: Bool
    let hasOutgoing: Bool
    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 6) {
            if failed {
                Text(L10n.text("会话暂时未能创建。草稿和待发消息仍保留。"))
                if hasOutgoing { Text(L10n.text("请在待发消息中选择“重试发送”，继续创建会话。")) }
                else { Text(L10n.text("发送消息时会重试创建会话。")) }
            } else {
                Text(L10n.text("正在创建会话。你可以先写下并发送消息，消息会在会话创建后继续发送。"))
            }
        }.font(.footnote).foregroundStyle(.secondary).padding()
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("chat.pending")
    }
}

struct DecisionReplyView: View {
    @Environment(\.locale) private var locale
    @Environment(AppStore.self) private var store
    let message: JSONValue
    let station: String
    let thread: Int?
    @State private var reply = ""
    @State private var operation = ViewOperation()
    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 8) {
            if message["card"].text("type") == "text" {
                TextField(message["card"].text("placeholder", fallback: L10n.text("写下你的决定")), text: $reply, axis: .vertical).accessibilityIdentifier("decision.text")
                Button(L10n.text("回复")) { answer(nil) }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operation.busy).accessibilityIdentifier("decision.reply")
            } else {
                // Suggested answers: glass capsules in one row that scrolls sideways,
                // running to the screen edges so a long row reads as scrollable.
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(ViewRecord.decode(message["options"].arrayValue, key: "label")) { option in
                                Button { answer(option.value.text("label")) } label: {
                                    Text(option.value.text("label")).font(.subheadline.weight(.medium)).lineLimit(1)
                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                }
                                .buttonStyle(.glass).buttonBorderShape(.capsule)
                                .disabled(operation.busy).accessibilityIdentifier("decision.option.\(option.id)")
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 6)
                    }
                }
                .scrollIndicators(.hidden).scrollClipDisabled()
                .padding(.horizontal, -18)
            }
            OperationSection(operation: operation)
        }
    }
    private func answer(_ option: String?) {
        guard let thread else { return }
        Task { await operation.run {
            var params: [String: JSONValue] = ["station": .string(station), "thread": .number(Double(thread)), "seq": message["seq"]]
            params[option == nil ? "text" : "option"] = .string(option ?? reply)
            _ = try await store.call(option == nil ? "decision.reply" : "decision.answer", params: params)
            reply = ""
        } }
    }
}
