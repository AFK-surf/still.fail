import Foundation
import WidgetKit

/// Keeps the widgets' snapshot (WidgetSnapshot) up to date from the selected
/// workspace: the chat list for decisions, recent tasks and today's counts, and the
/// archive for the days before. Both stay subscribed during synchronization, so
/// an initially disconnected station can still contribute its archive. Writes are coalesced and only
/// a changed picture reloads the widgets.
@MainActor final class WidgetFeed {
    private weak var store: AppStore?
    private var chats: CoreTopic?
    private var archive: CoreTopic?
    private var archiveReady = false
    private var archiveDays: [Date: Int] = [:]
    private var scope: (workspace: String, account: String)?
    private var pending: Task<Void, Never>?
    private var written: WidgetSnapshot?
    private let writer = DispatchQueue(label: "fail.still.iphone.widget-snapshot", qos: .utility)

    private let snapshotURL: URL?
    private let reload: @Sendable () -> Void

    init(snapshotURL: URL? = WidgetSnapshot.fileURL,
         reload: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.snapshotURL = snapshotURL
        self.reload = reload
        written = WidgetSnapshot.load(from: snapshotURL)
    }

    /// Called whenever the scope changes; scope changes cancel the old topics in the store.
    func restart(store: AppStore) {
        self.store = store
        if store.isReady {
            let account = store.selectedAccountID, workspace = store.selectedWorkspaceID
            writer.async { try? WidgetFiles.select(account: account, workspace: workspace) }
        }
        chats?.cancel(); archive?.cancel(); chats = nil; archive = nil
        archiveDays = [:]; archiveReady = false; pending?.cancel()
        guard let workspace = store.selectedWorkspaceID, let account = store.selectedAccountID else {
            // Signed out or no workspace: no other account's chats stay on the home screen.
            scope = nil
            if store.isReady && store.accounts.isEmpty { clear() }
            return
        }
        scope = (workspace, account)
        let chats = store.subscribe("chats", params: ["scope": .string(workspace), "mine": .bool(false)])
        chats.onChange = { [weak self] in self?.schedule() }
        self.chats = chats
        readArchive()
    }

    /// Restore subscriptions after a bounded background refresh released them.
    func resume() {
        guard let store else { return }
        if scope == nil { restart(store: store) }
        else if archive == nil { readArchive() }
    }

    private func readArchive() {
        guard let store, let scope else { return }
        let archive = store.subscribe("archive", params: ["scope": .string(scope.workspace)])
        archive.onChange = { [weak self, weak archive] in
            guard let self, let archive else { return }
            self.archiveReady = archive.error == nil && archive.value.map(Self.archiveIsReady) == true
            guard self.archiveReady, let value = archive.value else { return }
            self.archiveDays = Self.count(value["days"].arrayValue.flatMap { $0["items"].arrayValue }.compactMap { Self.date($0["at"]) })
            // Keep reading until the feed is stopped: stations may reconnect after
            // the first empty result, and chats may move into the archive meanwhile.
            self.schedule()
        }
        self.archive = archive
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    @discardableResult private func write() -> Bool {
        guard let scope, archiveReady, chats?.error == nil, let value = chats?.value,
              Self.chatsAreReady(value) else { return false }
        let snapshot = Self.snapshot(chats: value, archiveDays: archiveDays, workspace: scope.workspace, account: scope.account,
                                     name: store.flatMap { store in WorkspaceChoice.decode(store.workspaceGroups).first { $0.workspaceID == scope.workspace }?.name } ?? "")
        guard !snapshot.sameContent(as: written) else { return true }
        written = snapshot
        persist(snapshot)
        return true
    }

    private func clear() {
        guard written != nil else { return }
        written = nil
        writer.async {
            if let url = self.snapshotURL { try? FileManager.default.removeItem(at: url) }
            self.reload()
        }
    }

    private func persist(_ snapshot: WidgetSnapshot) {
        writer.async {
            guard let url = self.snapshotURL, let data = snapshot.encoded() else { return }
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                self.reload()
            } catch { /* Preserve the last on-disk snapshot when storage is unavailable. */ }
        }
    }

    static func snapshot(chats: JSONValue, archiveDays: [Date: Int], workspace: String, account: String, name: String,
                         now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        WidgetProjection.snapshot(chats: chats, archiveDays: archiveDays, workspace: workspace, account: account, name: name, now: now, calendar: calendar)
    }
    static func count(_ dates: [Date], calendar: Calendar = .current) -> [Date: Int] { WidgetProjection.count(dates, calendar: calendar) }
    static func date(_ value: JSONValue) -> Date? { WidgetProjection.date(value) }
    static func chatsAreReady(_ value: JSONValue) -> Bool { WidgetProjection.chatsAreReady(value) }
    static func archiveIsReady(_ value: JSONValue) -> Bool { WidgetProjection.archiveIsReady(value) }
}
