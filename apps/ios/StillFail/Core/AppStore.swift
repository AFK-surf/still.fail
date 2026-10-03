import Foundation
import Observation
import AuthenticationServices
import UIKit

@MainActor @Observable
final class CoreTopic {
    private(set) var value: JSONValue?
    private(set) var error: CoreFailure?
    private(set) var isLoading = true
    @ObservationIgnored private var cancellation: (() -> Void)?
    init(cancel: @escaping () -> Void) { cancellation = cancel }
    func cancel() {
        cancellation?(); cancellation = nil
        value = nil; error = nil; isLoading = false
    }
    fileprivate func apply(_ state: CoreTopicState) {
        value = state.value; error = state.error; isLoading = state.isLoading
    }
}

@MainActor @Observable
final class AppStore {
    private(set) var accounts: [JSONValue] = []
    private(set) var workspaceGroups: [JSONValue] = []
    var selectedWorkspaceID: String? {
        didSet {
            if oldValue != selectedWorkspaceID {
                selectedWorkspaceRole = selectedMembership()?["role"]
                scopeChanged(); sendFocus()
                rememberScope()
            }
        }
    }
    var selectedAccountID: String? {
        didSet {
            if oldValue != selectedAccountID {
                if selectedWorkspaceID != nil { selectedWorkspaceID = nil }
                scopeChanged()
            }
        }
    }
    private(set) var scopeEpoch = 0
    private(set) var fatalMessage: String?
    private(set) var isReady = false
    private(set) var authError: String?
    private(set) var isAuthenticating = false

    @ObservationIgnored private var bridge: CoreBridge!
    @ObservationIgnored private var nextID: UInt64 = 1
    @ObservationIgnored private var topics: [UInt64: CoreTopic] = [:]
    @ObservationIgnored private var globalTopics: Set<UInt64> = []
    @ObservationIgnored private var accountsID: UInt64 = 0
    @ObservationIgnored private var workspacesID: UInt64 = 0
    @ObservationIgnored private var pending: [UInt64: PendingCall] = [:]
    @ObservationIgnored private var authSession: GoogleAuthentication?
    @ObservationIgnored private var timeout: Duration = .seconds(60)
    // Keep the last verified permission across per-account refresh failures.
    @ObservationIgnored private var selectedWorkspaceRole: JSONValue?
    // The last workspace is reopened on launch, before its membership refresh
    // arrives. Unconfirmed membership keeps the scope, exactly like a refresh failure.
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private var restoredScope = false
    @ObservationIgnored private var restoringScope = false
    @ObservationIgnored private var choseOnlyWorkspace = false
    static let rememberedScopeKey = "lastWorkspaceScope"

    private struct PendingCall {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let timer: Task<Void, Never>
        let epoch: Int?
    }

    /// Production always starts the REAL core. No fixtures or auth bypass.
    init() {
        preferences = .standard
        bridge = CoreBridge { [weak self] event in self?.receive(event) }
        openBaseTopics()
        bridge.start()
    }
    /// Internal injection point for unit tests; production init never uses it.
    init(engineFactory: @escaping CoreEngineFactory, callTimeout: Duration, preferences: UserDefaults? = nil) {
        timeout = callTimeout
        self.preferences = preferences
        bridge = CoreBridge(factory: engineFactory) { [weak self] event in self?.receive(event) }
        openBaseTopics()
        bridge.start()
    }
    deinit { bridge?.stop() }

    func call(_ name: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        try Task.checkCancellation()
        let id = allocateID()
        let epoch: Int? = name.hasPrefix("auth.") || name == "client.focus" ? nil : scopeEpoch
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.failCall(id, error: CoreFailure(code: "timeout_uncertain"))
                }
                pending[id] = PendingCall(continuation: continuation, timer: timer, epoch: epoch)
                bridge.call(id: id, name: name, params: params)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failCall(id, error: CoreFailure(code: "cancelled_uncertain")) }
        }
    }
    func subscribe(_ topic: String, params: [String: JSONValue] = [:]) -> CoreTopic {
        subscribeTopic(topic, params: params, global: false).topic
    }
    func signOut(account: String) async throws {
        _ = try await call("auth.signOut", params: ["account": .string(account)])
        // The accounts topic drives identity invalidation, even when it arrives
        // before this terminal reply. Other accounts remain fully intact.
    }
    /// Workspace selection is local UI scope, not a made-up cloud/core call.
    func switchWorkspace(workspace: String, account: String) throws {
        guard accounts.contains(where: { $0["sub"].stringValue == account }),
              let group = workspaceGroups.first(where: { $0["account"]["sub"].stringValue == account }),
              group["loaded"].boolValue == true, group["error"] == .null,
              group["workspaces"].arrayValue.contains(where: { $0["id"].stringValue == workspace }) else {
            throw CoreFailure(code: "scope_unverified", message: "尚未确认这个账号的工作区权限，请连接后重试。")
        }
        guard effectiveAccount(workspace: workspace) == account else {
            throw CoreFailure(code: "scope_identity_mismatch", message: "这个工作区由最先登录且仍有权限的账号连接，暂不支持切换为当前账号。请选择该账号或另一个工作区。")
        }
        // Validate before replacing the visible identity. A failed selection
        // preserves the previous account, workspace and subscriptions.
        selectedAccountID = account
        selectedWorkspaceID = workspace
    }
    func switchAccount(account: String) throws {
        guard accounts.contains(where: { $0["sub"].stringValue == account }),
              let group = workspaceGroups.first(where: { $0["account"]["sub"].stringValue == account }),
              group["loaded"].boolValue == true, group["error"] == .null else {
            throw CoreFailure(code: "scope_unverified", message: "尚未读取这个账号的权限，请连接后重试。")
        }
        let firstWorkspace = group["workspaces"].arrayValue.first?["id"].stringValue
        selectedAccountID = account
        // Never label a station connection as B when the core will use A.
        // Leave B selected in the chooser; a B-only workspace can be selected explicitly.
        selectedWorkspaceID = firstWorkspace.flatMap { effectiveAccount(workspace: $0) == account ? $0 : nil }
    }
    private func group(account: String) -> JSONValue? {
        workspaceGroups.first { $0["account"]["sub"].stringValue == account }
    }
    private func selectedMembership() -> JSONValue? {
        guard let account = selectedAccountID, let workspace = selectedWorkspaceID else { return nil }
        return group(account: account)?["workspaces"].arrayValue.first { $0["id"].stringValue == workspace }
    }
    /// Mirrors account_state.rs::recompute_owners: sign-in order, KEPT membership,
    /// including unloaded/error groups. A failed refresh does not discard a core owner.
    private func effectiveAccount(workspace: String) -> String? {
        for account in accounts {
            guard let sub = account["sub"].stringValue, let group = group(account: sub) else { return nil }
            if group["workspaces"].arrayValue.contains(where: { $0["id"].stringValue == workspace }) { return sub }
        }
        return nil
    }
    private func reconcileSelectedScope() {
        guard let account = selectedAccountID, let workspace = selectedWorkspaceID else { return }
        // Check the selected ACCOUNT's membership, not any group's same workspace ID.
        if let group = group(account: account), group["loaded"].boolValue == true, group["error"] == .null {
            guard let membership = selectedMembership() else {
                forgetScope(); selectedWorkspaceID = nil
                return
            }
            if let role = selectedWorkspaceRole, role != membership["role"] {
                selectedWorkspaceID = nil
                return
            }
            selectedWorkspaceRole = membership["role"]
        }
        if let effective = effectiveAccount(workspace: workspace), effective != account {
            forgetScope(); selectedWorkspaceID = nil
        }
        // Missing/unloaded/failed membership is not confirmed removal. Keep the
        // visible scope and its subscriptions until a successful answer confirms it.
    }
    /// The remembered scope is only a starting point: the first accounts value
    /// must still list its account, and a confirmed membership answer can clear it.
    private func restoreScope() {
        // A signed-out (or not yet read) account list does not spend the one restore.
        guard !restoredScope, selectedWorkspaceID == nil, !accounts.isEmpty else { return }
        restoredScope = true
        guard let saved = preferences?.dictionary(forKey: Self.rememberedScopeKey) as? [String: String],
              let account = saved["account"], let workspace = saved["workspace"],
              accounts.contains(where: { $0["sub"].stringValue == account }) else { return }
        restoringScope = true; defer { restoringScope = false }
        selectedAccountID = account
        selectedWorkspaceID = workspace
    }
    /// A single visible workspace needs no chooser on the first launch either.
    private func chooseOnlyWorkspace() {
        guard !choseOnlyWorkspace, let preferences, selectedWorkspaceID == nil, !workspaceGroups.isEmpty,
              preferences.dictionary(forKey: Self.rememberedScopeKey) == nil,
              workspaceGroups.allSatisfy({ $0["loaded"].boolValue == true && $0["error"] == .null }) else { return }
        let choices = WorkspaceChoice.decode(workspaceGroups)
        choseOnlyWorkspace = true
        guard choices.count == 1, let only = choices.first else { return }
        try? switchWorkspace(workspace: only.workspaceID, account: only.accountID)
    }
    private func forgetScope() { preferences?.removeObject(forKey: Self.rememberedScopeKey) }
    private func rememberScope() {
        guard !restoringScope, let preferences else { return }
        if let account = selectedAccountID, let workspace = selectedWorkspaceID {
            preferences.set(["account": account, "workspace": workspace], forKey: Self.rememberedScopeKey)
        } else if selectedAccountID == nil || !accounts.contains(where: { $0["sub"].stringValue == selectedAccountID }) {
            preferences.removeObject(forKey: Self.rememberedScopeKey)
        }
    }
    func resume() { sendFocus() }
    func pause() {
        Task { [weak self] in _ = try? await self?.call("client.focus", params: ["visible": .bool(false), "focused": .bool(false)]) }
    }
    func signInWithGoogle() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true; authError = nil
        defer { isAuthenticating = false; authSession = nil }
        do {
            let begun = try await call("auth.begin", params: [
                "redirect_uri": .string("stillfail://auth/callback"),
                "return_to": .string("/"), "device_name": .string(UIDevice.current.userInterfaceIdiom == .pad ? "still.fail iPad" : "still.fail iPhone")])
            guard let raw = begun["url"].stringValue, let url = URL(string: raw),
                  url.scheme == "https", url.host == "app.still.fail" else {
                throw CoreFailure(code: "auth_invalid_url")
            }
            let browser = try GoogleAuthentication(application: .shared)
            authSession = browser
            let callback = try await browser.open(url)
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            guard components?.scheme == "stillfail", components?.host == "auth",
                  components?.path == "/callback", let query = components?.percentEncodedQuery else {
                throw CoreFailure(code: "auth_invalid_callback")
            }
            _ = try await call("auth.complete", params: ["query": .string(query)])
        } catch {
            authError = LoginCopy.completion(provider: "google", error: error)
        }
    }

    private func allocateID() -> UInt64 { defer { nextID += 1 }; return nextID }
    private func openBaseTopics() {
        accountsID = subscribeTopic("accounts", params: [:], global: true).id
        workspacesID = subscribeTopic("workspaces", params: [:], global: true).id
    }
    private func subscribeTopic(_ name: String, params: [String: JSONValue], global: Bool) -> (id: UInt64, topic: CoreTopic) {
        let id = allocateID()
        let topic = CoreTopic { [weak self] in
            self?.topics.removeValue(forKey: id); self?.globalTopics.remove(id)
            self?.bridge.unsubscribe(id: id)
        }
        topics[id] = topic
        if global { globalTopics.insert(id) }
        var spec = params; spec["topic"] = .string(name)
        bridge.subscribe(id: id, spec: .object(spec))
        return (id, topic)
    }
    private func receive(_ event: CoreEvent) {
        switch event {
        case .started: sendFocus()
        case .fatal(let error):
            fatalMessage = error.message; isReady = false
            accounts = []; workspaceGroups = []
            for id in Array(pending.keys) { failCall(id, error: CoreFailure(code: "core_restarted")) }
            scopeChanged()
            for topic in topics.values { topic.apply(CoreTopicState()) }
        case .reply(let id, let result):
            guard let call = pending.removeValue(forKey: id) else { return }
            call.timer.cancel()
            if let epoch = call.epoch, epoch != scopeEpoch {
                call.continuation.resume(throwing: CoreFailure(code: "scope_changed"))
            } else { call.continuation.resume(with: result.mapError { $0 as any Error }) }
        case .topic(let id, let state):
            guard let topic = topics[id] else { return }
            topic.apply(state)
            if id == accountsID, let value = state.value, state.error == nil {
                if accounts != value.arrayValue {
                    accounts = value.arrayValue
                    let signedIn = Set(accounts.compactMap { $0["sub"].stringValue })
                    workspaceGroups.removeAll { group in
                        guard let account = group["account"]["sub"].stringValue else { return true }
                        return !signedIn.contains(account)
                    }
                    scopeChanged()
                    if let selectedAccountID, !accounts.contains(where: { $0["sub"].stringValue == selectedAccountID }) {
                        self.selectedAccountID = nil
                    }
                    reconcileSelectedScope()
                }
                restoreScope()
                fatalMessage = nil; isReady = true
            } else if id == workspacesID, let value = state.value, state.error == nil {
                workspaceGroups = value.arrayValue
                reconcileSelectedScope()
                chooseOnlyWorkspace()
            }
        }
    }
    private func scopeChanged() {
        scopeEpoch += 1
        // No subscription or replay cache from a previous identity may leak into
        // another scope. Views resubscribe using their scopeEpoch task key.
        for id in Array(topics.keys) where !globalTopics.contains(id) { topics[id]?.cancel() }
        for id in Array(pending.keys) where pending[id]?.epoch != nil {
            failCall(id, error: CoreFailure(code: "scope_changed"))
        }
    }
    private func failCall(_ id: UInt64, error: CoreFailure) {
        guard let call = pending.removeValue(forKey: id) else { return }
        call.timer.cancel(); bridge.cancelCall(id: id)
        call.continuation.resume(throwing: error)
    }
    private func sendFocus() {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await call("client.focus", params: ["visible": .bool(true), "focused": .bool(true),
                                                       "workspace": selectedWorkspaceID.map(JSONValue.string) ?? .null])
        }
    }
}

/// System browser only; no embedded web view or direct station networking.
@MainActor
private final class GoogleAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: UIWindow
    private var session: ASWebAuthenticationSession?
    private var answer: CheckedContinuation<URL, any Error>?
    init(application: UIApplication) throws {
        guard let window = application.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw CoreFailure(code: "auth_no_window")
        }
        anchor = window
        super.init()
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    func open(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                answer = continuation
                let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "stillfail") { [weak self] callback, error in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, let answer = self.answer else { return }
                            self.answer = nil; self.session = nil
                            if let callback { answer.resume(returning: callback) }
                            else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                                answer.resume(throwing: CoreFailure(code: "auth_cancelled"))
                            } else { answer.resume(throwing: CoreFailure(code: "auth_failed")) }
                        }
                    }
                }
                session = browser; browser.presentationContextProvider = self
                browser.prefersEphemeralWebBrowserSession = true
                if !browser.start() { cancel() }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    private func cancel() {
        session?.cancel(); session = nil
        let pending = answer; answer = nil
        pending?.resume(throwing: CoreFailure(code: "auth_cancelled"))
    }
}
