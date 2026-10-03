import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A page, rather than a creation form. Its destination stays mounted as the first send becomes a chat.
struct NewChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let workspace: String
    let onCreated: (ChatRoute) -> Void
    @State private var topic: CoreTopic?
    @State private var draftState = NewChatDraftState()
    @State private var flow = NewChatFlow()
    @State private var composerSession = ChatComposerSession()
    @State private var picking = ViewOperation()
    @State private var sendingFirst = false
    @State private var persistenceError: String?
    @State private var uploadError: String?
    @State private var uploading = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var generation = 0
    @State private var persistence: Task<Void, Never>?
    @State private var visitEpoch: Int?
    private var value: JSONValue { topic?.value ?? .null }
    private var station: String { flow.createdRoute?.station ?? value["station"].text("station") }
    private var draftKey: String { (store.selectedAccountID ?? "") + ":new:" + station }
    private var draft: ChatDraft {
        get { draftState.draft }
        nonmutating set { draftState.draft = newValue }
    }
    private var draftLoaded: Bool { draftState.loaded && draftState.key == draftKey }
    private var draftError: String? { draftState.readError ?? persistenceError ?? draftState.saveError }
    private var locked: Bool { sendingFirst || flow.busy || flow.uncertain || uploading || picking.busy }
    private var ready: Bool {
        draftLoaded && !station.isEmpty && !value["model"].text("model").isEmpty &&
        !value.text("runtime").isEmpty && value.text("blocked").isEmpty && topic?.error == nil
    }

    var body: some View {
        let _ = locale.identifier
        Group {
            if let route = flow.openedRoute {
                ChatView(route: route, workspace: workspace, initialOutgoing: flow.outgoing,
                         initialDraft: draft, composerSession: composerSession)
            } else {
                placeholder
            }
        }
        .task(id: generation) {
            visitEpoch = store.scopeEpoch
            guard flow.openedRoute == nil else { return }
            topic?.cancel(); topic = store.subscribe("newChat", params: ["scope": .string(workspace)])
        }
        .task(id: draftKey) { await loadDraft() }
        .onChange(of: draft) { _, _ in persistDraft() }
        .onChange(of: flow.openedRoute) { _, route in
            if let route { onCreated(route); topic?.cancel(); topic = nil }
        }
        .onDisappear {
            topic?.cancel(); topic = nil
            persistence?.cancel()
            if draftLoaded && flow.openedRoute == nil { persistDraft(immediately: true) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { uploadFile(url) }
            case .failure: uploadError = L10n.text("没有读取到文件，请重新选择。")
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in if let item { uploadPhoto(item) } }
        .accessibilityIdentifier("newChat.page")
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    if let outgoing = flow.outgoing {
                        HStack {
                            Spacer(minLength: 56)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(outgoing.text).textSelection(.enabled)
                                ForEach(ViewRecord.decode(outgoing.files, key: "path")) { file in
                                    Label(file.value.text("name"), systemImage: "paperclip").font(.footnote)
                                }
                            }.padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(uiColor: ChatPalette.myBubble), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(uiColor: ChatPalette.myBorder), lineWidth: 1 / max(1, displayScale)))
                        }.accessibilityIdentifier("newChat.optimisticMessage")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        hero
                    }
                    if let error = topic?.error {
                        FailureNotice(message: error.localizedDescription, retry: { generation += 1 })
                    } else if topic?.value == nil {
                        ProgressView("正在读取节点…")
                    } else if station.isEmpty {
                        Text(value.flag("any") ? L10n.text("没有在线节点。请检查目标电脑及节点连接。") : L10n.text("还没有节点。请先在目标电脑上添加节点。"))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        NavigationLink("查看节点连接") { NodesView(workspace: workspace) }
                    }
                    if let problem = value["problem"].stringValue { Text(L10n.projected(problem)).font(.footnote).foregroundStyle(.secondary) }
                    if let spent = value["spent"].stringValue { Text(L10n.projected(spent)).font(.footnote).foregroundStyle(.secondary) }
                    if let error = flow.error {
                        FailureNotice(message: error)
                        if flow.uncertain, flow.createdRoute != nil {
                            Button("查看发送状态") { flow.inspectCreatedChat() }.accessibilityIdentifier("newChat.checkSend")
                        }
                    }
                    if let error = draftError { FailureNotice(message: error, retry: { Task { await loadDraft() } }) }
                    if let error = uploadError { FailureNotice(message: error) }
                    OperationSection(operation: picking)
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: flow.outgoing)
            }.defaultScrollAnchor(.bottom).scrollDismissesKeyboard(.interactively)
                .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("新建会话").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background { ProgressiveHeaderBlur().frame(width: 0, height: 0).allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                choices
                attachments
                ChatComposer(text: Binding(get: { draft.text }, set: { draft.text = $0 }), busy: locked || !draftLoaded, enabled: ready && !draft.isEmpty,
                             attachmentEnabled: draftLoaded && !station.isEmpty,
                             attachFiles: { showFiles = true }, attachPhotos: { showPhotos = true }, send: send, session: composerSession)
            }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
    }

    /// Greets with the agent the first message will reach.
    private var hero: some View {
        VStack(spacing: 14) {
            Group {
                if let logo = ModelLogo.image(maker: value["model"]["maker"].text("id"), runtime: value.text("runtime")) {
                    Image(uiImage: logo).renderingMode(logo.renderingMode == .alwaysOriginal ? .original : .template).resizable().scaledToFit()
                } else {
                    Image(systemName: "sparkle").resizable().scaledToFit()
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30).padding(15)
            .background(Color(uiColor: ChatPalette.tile), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 72).accessibilityHidden(true)
            Text("想让 agent 做什么？").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("发送第一条消息，开始一个新会话。").font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// The new chat's setup sits in one glass container directly above the input,
    /// so the page reads as the chat it is about to become.
    private var choices: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                nodeMenu
                Rectangle().fill(.separator).frame(width: 0.5, height: 30)
                modelMenu
            }
            Rectangle().fill(.separator).frame(height: 0.5).gridCellColumns(3).padding(.horizontal, 12)
            GridRow {
                effortMenu
                Rectangle().fill(.separator).frame(width: 0.5, height: 30)
                accountMenu
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Menus tint their labels; the chosen values read as content, not as links.
        .tint(.primary)
        .disabled(locked || flow.createdRoute != nil).accessibilityIdentifier("newChat.configuration")
    }

    private var nodeMenu: some View {
        Menu {
            ForEach(ViewRecord.decode(value["stations"].arrayValue)) { row in
                Button { pick("station", .string(row.value.text("id"))) } label: {
                    Label(row.value.text("name"), systemImage: row.value.text("station") == station ? "checkmark" : "desktopcomputer")
                }
            }
        } label: { choiceRow("节点", value: value["station"].text("name", fallback: L10n.text("选择节点")), symbol: "desktopcomputer") }
            .disabled(value["stations"].arrayValue.isEmpty || !draft.files.isEmpty)
            .accessibilityIdentifier("newChat.node")
    }

    private var modelMenu: some View {
        Menu {
            ForEach(ViewRecord.decode(value["station"]["models"].arrayValue, key: "model")) { row in
                Button { pick("model", .string(row.value.text("model"))) } label: {
                    Label(row.value.text("name", fallback: row.id), systemImage: row.id == value["model"].text("model") ? "checkmark" : "sparkles")
                }
            }
            if value["model"]["runtimes"].arrayValue.count > 1 {
                Section("运行方式") {
                    ForEach(value["model"]["runtimes"].arrayValue.compactMap(\.stringValue), id: \.self) { runtime in
                        Button { pick("runtime", .string(runtime)) } label: {
                            Label(runtime, systemImage: runtime == value.text("runtime") ? "checkmark" : "terminal")
                        }
                    }
                }
            }
        } label: { choiceRow("模型", value: value["model"].text("name", fallback: L10n.text("选择模型")), symbol: "sparkles") }
            .disabled(value["station"]["models"].arrayValue.isEmpty).accessibilityIdentifier("newChat.model")
    }

    private var effortMenu: some View {
        Menu {
            Button("默认") { pick("effort", .null) }
            ForEach(value["efforts"].arrayValue.compactMap(\.stringValue), id: \.self) { effort in
                Button { pick("effort", .string(effort)) } label: {
                    Label(L10n.text(effort), systemImage: effort == value.text("effort") ? "checkmark" : "brain")
                }
            }
            if value["pick"].flag("fastAvailable") {
                Section("速度") {
                    Button("跟随订阅") { pick("fast", .null) }
                    Button("标准速度") { pick("fast", .bool(false)) }
                    Button("快速模式") { pick("fast", .bool(true)) }
                }
            }
        } label: { choiceRow("思考强度", value: value["effort"].stringValue.map { L10n.text($0) } ?? L10n.text("默认深度"), symbol: "brain") }
            .accessibilityIdentifier("newChat.effort")
    }

    private var accountMenu: some View {
        Menu {
            Button("自动选择账号池") { pick("profile", .null) }
            ForEach(ViewRecord.decode(value["accounts"].arrayValue)) { row in
                Button { pick("profile", .string(row.id)) } label: {
                    Label(row.value.text("name", fallback: row.value.text("label", fallback: row.id)),
                          systemImage: row.id == value.text("profile") ? "checkmark" : "person.crop.circle")
                }
            }
        } label: {
            let account = value["accounts"].arrayValue.first { $0.text("id") == value.text("profile") }
            let selected = account?.text("name", fallback: account?.text("label") ?? "") ?? ""
            choiceRow("账号池", value: selected.isEmpty ? L10n.text("自动选择") : selected, symbol: "person.crop.circle")
        }.accessibilityIdentifier("newChat.account")
    }

    private func choiceRow(_ label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(label)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(draft.files.enumerated()), id: \.offset) { index, file in
                HStack {
                    Label(file.text("name"), systemImage: "paperclip").font(.footnote).lineLimit(1)
                    Spacer()
                    Button("移除附件", systemImage: "xmark") { draft.files.remove(at: index) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
            }
            if uploading { ProgressView("正在上传附件…") }
        }.disabled(locked)
    }

    private func pick(_ field: String, _ choice: JSONValue) {
        guard !locked, flow.createdRoute == nil else { return }
        Task { await picking.run {
            _ = try await store.call("newChat.pick", params: ["scope": .string(workspace), field: choice])
        } }
    }

    private func send() {
        guard ready, !locked, !draft.isEmpty, visitEpoch == store.scopeEpoch else { return }
        let sending = draft
        let epoch = store.scopeEpoch
        let address = station
        let source = draftParams
        persistence?.cancel()
        sendingFirst = true
        draft = ChatDraft()
        Task {
            defer { sendingFirst = false }
            let accepted = await flow.send(sending, station: address) { name, params in
                guard epoch == store.scopeEpoch else { throw CoreFailure(code: "scope_changed") }
                return try await store.call(name, params: params)
            }
            guard epoch == store.scopeEpoch else { return }
            guard accepted else {
                if !flow.uncertain {
                    draft = NewChatDraftState.merge(saved: sending, typed: draft)
                    sendingFirst = false
                    persistDraft(immediately: true)
                }
                return
            }
            var clear = source; clear.merge(ChatDraft().payload) { _, new in new }
            _ = try? await store.call("draft.put", params: clear)
        }
    }

    private var draftParams: [String: JSONValue] { draftState.params }
    private func loadDraft() async {
        guard !station.isEmpty, visitEpoch == store.scopeEpoch, !sendingFirst, !flow.busy, flow.openedRoute == nil else { return }
        let epoch = store.scopeEpoch
        persistence?.cancel()
        await draftState.load(key: draftKey, station: station) { name, params in
            guard epoch == store.scopeEpoch else { throw CoreFailure(code: "scope_changed") }
            return try await store.call(name, params: params)
        }
    }

    private func persistDraft(immediately: Bool = false) {
        guard draftLoaded, visitEpoch == store.scopeEpoch, flow.openedRoute == nil, !sendingFirst, !flow.busy, !flow.uncertain else { return }
        persistence?.cancel()
        var params = draftParams; params.merge(draft.payload) { _, new in new }
        let epoch = store.scopeEpoch
        persistence = Task {
            if !immediately { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
            guard epoch == store.scopeEpoch else { return }
            do { _ = try await store.call("draft.put", params: params) }
            catch {
                guard epoch == store.scopeEpoch else { return }
                persistenceError = L10n.text("草稿未能保存。内容仍保留在当前页面，请检查连接后重试。")
            }
        }
    }

    private func uploadFile(_ url: URL) {
        guard draftLoaded, !locked else { return }
        let address = station; let epoch = store.scopeEpoch
        uploading = true; uploadError = nil
        Task {
            defer { uploading = false }
            do {
                let encoded = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try Data(contentsOf: url).base64EncodedString()
                }.value
                try await upload(name: url.lastPathComponent, encoded: encoded, station: address, epoch: epoch)
            } catch { if epoch == store.scopeEpoch { uploadError = error.localizedDescription } }
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem) {
        guard draftLoaded, !locked else { return }
        let address = station; let epoch = store.scopeEpoch
        uploading = true; uploadError = nil
        Task {
            defer { uploading = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CoreFailure(code: "file_unavailable") }
                let encoded = await Task.detached { data.base64EncodedString() }.value
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                try await upload(name: "photo.\(ext)", encoded: encoded, station: address, epoch: epoch)
            } catch { if epoch == store.scopeEpoch { uploadError = error.localizedDescription } }
        }
    }

    private func upload(name: String, encoded: String, station address: String, epoch: Int) async throws {
        guard epoch == store.scopeEpoch else { throw CoreFailure(code: "scope_changed") }
        let file = try await store.call("station.upload", params: ["station": .string(address), "name": .string(name), "bytes": .string(encoded)])
        guard epoch == store.scopeEpoch, address == station else { return }
        guard !file.text("path").isEmpty else { throw CoreFailure(code: "invalid_response") }
        draft.files.append(file)
    }
}
