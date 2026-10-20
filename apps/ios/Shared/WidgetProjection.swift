import Foundation

enum WidgetProjection {
    /// Partial station reads must never replace a complete snapshot with zeros.
    static func chatsAreReady(_ value: JSONValue) -> Bool {
        value["loading"].boolValue == false && !value["note"].flag("reading") &&
            value["stations"].arrayValue.allSatisfy { $0.text("state") == "online" }
    }

    static func archiveIsReady(_ value: JSONValue) -> Bool {
        value["wait"]["reading"].boolValue == false && value["wait"]["failing"].arrayValue.isEmpty &&
            value["errors"].arrayValue.isEmpty
    }

    private static func needsDecision(_ row: JSONValue) -> Bool {
        !row["decision"].flag("dismissed") && !row["decision"].text("text").isEmpty
    }

    static func snapshot(chats: JSONValue, archiveDays: [Date: Int], workspace: String, account: String, name: String,
                         now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let rows = chats["days"].arrayValue.flatMap { $0["items"].arrayValue }.filter { !$0.flag("pending") }
        func task(_ row: JSONValue) -> WidgetSnapshot.Task {
            let station = row.text("station"), session = row.text("session", fallback: row.text("id")), thread = row["thread"].intValue
            let id = station + ":" + session + ":" + (thread.map(String.init) ?? "")
            let summary = needsDecision(row) ? row["decision"].text("text") : (row["stateText"].stringValue.map { L10n.projected($0) } ?? row["decision"].text("text", fallback: row["last"].text("preview", fallback: row["last"].text("text")))).components(separatedBy: .newlines).joined(separator: " ")
            return WidgetSnapshot.Task(id: id, title: row.text("title", fallback: L10n.text("会话")), summary: summary,
                                       tone: row.text("tone"), at: lastActive(row), unread: row.flag("unread"),
                                       link: WidgetLink.chat(workspace: workspace, account: account, station: station, session: session, thread: thread))
        }
        let decisions = rows.filter(needsDecision).sorted { (lastActive($0) ?? .distantPast) > (lastActive($1) ?? .distantPast) }
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
