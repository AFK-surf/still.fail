import Foundation
import Observation

/// The first send uses the same local pending-session alias and core-owned outbox as the web client.
/// Keep the alias after a rejected send: retrying must never create a second conversation.
@MainActor @Observable
final class NewChatFlow {
    private(set) var createdRoute: ChatRoute?
    private(set) var openedRoute: ChatRoute?
    private(set) var outgoing: ChatDraft?
    private(set) var busy = false
    private(set) var uncertain = false
    private(set) var error: String?

    typealias Call = (String, [String: JSONValue]) async throws -> JSONValue

    @discardableResult
    func send(_ draft: ChatDraft, station: String, call: Call) async -> Bool {
        guard !busy, !uncertain, openedRoute == nil, !draft.isEmpty, !station.isEmpty else { return false }
        busy = true; error = nil; outgoing = draft
        defer { busy = false }
        do {
            if createdRoute == nil {
                let made = try await call("newChat.create", ["station": .string(station)])
                guard !made.text("key").isEmpty else { throw CoreFailure(code: "invalid_response") }
                createdRoute = ChatRoute(station: station, session: made.text("key"))
            }
            guard let route = createdRoute else { return false }
            let params = ChatProtocol.send(route: route, value: .object(["pending": .bool(true)]), draft: draft)
            _ = try await call("chat.send", params)
            openedRoute = route
            return true
        } catch {
            uncertain = (error as? CoreFailure)?.outcomeUncertain == true
            self.error = (error as? LocalizedError)?.errorDescription ?? L10n.text("操作暂时未能完成，请检查连接后重试。")
            if !uncertain { outgoing = nil }
            return false
        }
    }

    func inspectCreatedChat() { openedRoute = createdRoute }
}

/// Draft reads can overlap node changes and edits. Keep each node's buffer until its write is acknowledged.
@MainActor @Observable
final class NewChatDraftState {
    var draft = ChatDraft()
    private(set) var loaded = false
    private(set) var key = ""
    private(set) var station = ""
    private(set) var readError: String?
    private(set) var saveError: String?
    @ObservationIgnored private var readID = UUID()
    @ObservationIgnored private var cache: [String: Entry] = [:]
    private struct Entry { let draft: ChatDraft; let loaded: Bool }

    var params: [String: JSONValue] { ["station": .string(station), "chat": .string(key)] }

    func load(key nextKey: String, station nextStation: String, call: @escaping NewChatFlow.Call) async {
        guard !nextKey.isEmpty, !nextStation.isEmpty, key != nextKey || !loaded else { return }
        let ticket = UUID(); readID = ticket; readError = nil
        if key != nextKey {
            if !key.isEmpty {
                cache[key] = Entry(draft: draft, loaded: loaded)
                if loaded { save(draft, params: params, call: call) }
            }
            if let saved = cache[nextKey] {
                draft = saved.draft; loaded = saved.loaded
            } else if !key.isEmpty {
                draft = ChatDraft(); loaded = false
            }
            key = nextKey; station = nextStation
        }
        if loaded {
            save(draft, params: params, call: call)
            return
        }
        let target = params
        do {
            // Finishing a local draft read after navigation lets pending typing be saved without overwriting the unread draft.
            let read = Task { try await call("draft.get", target) }
            let saved = try await read.value
            guard readID == ticket, key == nextKey else { return }
            // Until a read completes the visible buffer contains typing, including typing before node discovery.
            draft = Self.merge(saved: ChatDraft(saved), typed: draft)
            loaded = true; cache[nextKey] = Entry(draft: draft, loaded: true)
            if draft != ChatDraft(saved) { save(draft, params: target, call: call) }
        } catch {
            guard readID == ticket, key == nextKey else { return }
            readError = L10n.text("草稿暂时无法读取。请重试后继续，避免覆盖已保存的草稿。")
        }
    }

    private func save(_ draft: ChatDraft, params: [String: JSONValue], call: @escaping NewChatFlow.Call) {
        var payload = params; payload.merge(draft.payload) { _, new in new }
        Task {
            do { _ = try await call("draft.put", payload); saveError = nil }
            catch { saveError = L10n.text("草稿未能保存。内容仍保留在当前页面，请检查连接后重试。") }
        }
    }

    /// Preserve both a saved/submitted draft and text typed while the asynchronous operation was pending.
    static func merge(saved: ChatDraft, typed: ChatDraft) -> ChatDraft {
        if saved == typed || typed.isEmpty { return saved }
        if saved.isEmpty { return typed }
        var combined = saved
        if !typed.text.isEmpty {
            combined.text = saved.text.isEmpty ? typed.text : saved.text + "\n\n" + typed.text
        }
        for quote in typed.quotes where !combined.quotes.contains(quote) { combined.quotes.append(quote) }
        for file in typed.files {
            let path = file.text("path")
            if !combined.files.contains(where: { path.isEmpty ? $0 == file : $0.text("path") == path }) { combined.files.append(file) }
        }
        return combined
    }
}
