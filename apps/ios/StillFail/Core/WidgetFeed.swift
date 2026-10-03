import Foundation
import WidgetKit

/// Keeps the widgets' snapshot (WidgetSnapshot) up to date from the selected
/// workspace: the chat list for decisions, recent tasks and today's counts, and the
/// archive, read once per visit, for the days before. Writes are coalesced and only
/// a changed picture reloads the widgets.
@MainActor final class WidgetFeed {
    private weak var store: AppStore?
    private var chats: CoreTopic?
    private var archive: CoreTopic?
    private var archiveDays: [Date: Int] = [:]
    private var scope: (workspace: String, account: String)?
    private var pending: Task<Void, Never>?
    private var written: WidgetSnapshot?
    private let writer = DispatchQueue(label: "fail.still.iphone.widget-snapshot", qos: .utility)

    init() { written = WidgetSnapshot.load() }

    /// Called whenever the scope changes; scope changes cancel the old topics in the store.
    func restart(store: AppStore) {
        self.store = store
        chats?.cancel(); archive?.cancel(); chats = nil; archive = nil
        archiveDays = [:]; pending?.cancel()
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

    /// Back in the foreground: the archive is read again (chats stay live meanwhile).
    func resume() { if scope != nil, archive == nil { readArchive() } }

    private func readArchive() {
        guard let store, let scope else { return }
        let archive = store.subscribe("archive", params: ["scope": .string(scope.workspace)])
        archive.onChange = { [weak self, weak archive] in
            guard let self, let archive, let value = archive.value, !value.flag("loading") else { return }
            self.archiveDays = Self.count(value["days"].arrayValue.flatMap { $0["items"].arrayValue }.compactMap { Self.date($0["at"]) })
            // One reading is enough for the days before today; it is not kept open.
            archive.cancel(); if self.archive === archive { self.archive = nil }
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

    private func write() {
        guard let scope, let value = chats?.value, !value.flag("loading") else { return }
        let snapshot = Self.snapshot(chats: value, archiveDays: archiveDays, workspace: scope.workspace, account: scope.account,
                                     name: store.flatMap { store in WorkspaceChoice.decode(store.workspaceGroups).first { $0.workspaceID == scope.workspace }?.name } ?? "")
        guard !snapshot.sameContent(as: written) else { return }
        written = snapshot
        persist(snapshot)
    }

    private func clear() {
        guard written != nil else { return }
        written = nil
        writer.async {
            if let url = WidgetSnapshot.fileURL { try? FileManager.default.removeItem(at: url) }
            DispatchQueue.main.async { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    private func persist(_ snapshot: WidgetSnapshot) {
        writer.async {
            guard let url = WidgetSnapshot.fileURL, let data = snapshot.encoded() else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            DispatchQueue.main.async { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    // MARK: Projection (pure, tested)

    static func snapshot(chats: JSONValue, archiveDays: [Date: Int], workspace: String, account: String, name: String,
                         now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let rows = chats["days"].arrayValue.flatMap { $0["items"].arrayValue }.filter { !$0.flag("pending") }
        func task(_ row: JSONValue) -> WidgetSnapshot.Task {
            let route = ChatRoute(row)
            let summary = ConversationFilter.needsDecision(row) ? row["decision"].text("text") : ConversationListRow(value: row).summary
            return WidgetSnapshot.Task(id: route.id, title: row.text("title", fallback: L10n.text("会话")), summary: summary,
                                       tone: row.text("tone"), at: lastActive(row), unread: row.flag("unread"),
                                       link: WidgetLink.chat(workspace: workspace, account: account, station: route.station, session: route.session, thread: route.thread))
        }
        let decisions = rows.filter(ConversationFilter.needsDecision).sorted { (lastActive($0) ?? .distantPast) > (lastActive($1) ?? .distantPast) }
        let recent = rows.sorted { (lastActive($0) ?? .distantPast) > (lastActive($1) ?? .distantPast) }
        // A task counts on the day it began (its last activity when the station does not say).
        var counts = archiveDays
        for (day, n) in count(rows.compactMap { date($0["time"]["createdAt"]["at"]) ?? lastActive($0) }, calendar: calendar) { counts[day, default: 0] += n }
        let today = calendar.startOfDay(for: now)
        let days = (0..<WidgetSnapshot.dayCount).reversed().compactMap { offset -> WidgetSnapshot.Day? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return WidgetSnapshot.Day(date: day, count: counts[day] ?? 0)
        }
        return WidgetSnapshot(updatedAt: now, workspace: name, decisions: decisions.prefix(8).map(task), decisionCount: decisions.count,
                              recent: recent.prefix(8).map(task), days: days)
    }

    private static func lastActive(_ row: JSONValue) -> Date? { date(row["time"]["lastActiveAt"]["at"]) ?? date(row["lastActiveAt"]) }

    /// Core times are epoch milliseconds; a seconds value is taken as such.
    static func date(_ value: JSONValue) -> Date? {
        guard let number = value.numberValue, number.isFinite, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
    }

    static func count(_ dates: [Date], calendar: Calendar = .current) -> [Date: Int] {
        dates.reduce(into: [:]) { counts, date in counts[calendar.startOfDay(for: date), default: 0] += 1 }
    }
}
