import Foundation

/// What the widgets show, written by the app into the shared App Group container.
/// Widgets cannot run the core, so the app leaves them its latest picture of the
/// selected workspace; every widget reads only this file.
struct WidgetSnapshot: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let summary: String
        /// alert | wait | busy | "" (as the list's state dot)
        let tone: String
        let at: Date?
        let unread: Bool
        let link: URL?
    }
    struct Day: Codable, Equatable {
        /// The local start of the day.
        let date: Date
        let count: Int
    }

    var updatedAt: Date
    var workspace: String
    var decisions: [Task]
    /// How many chats wait on a decision, which can be more than `decisions` holds.
    var decisionCount: Int
    var recent: [Task]
    /// One entry per day, oldest first, ending today.
    var days: [Day]

    static let appGroup = "group.fail.still.iphone"
    static let fileName = "widget-snapshot.json"
    static let dayCount = 26 * 7

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// Everything but the time it was written: whether the widgets need a reload.
    func sameContent(as other: WidgetSnapshot?) -> Bool {
        guard var other else { return false }
        other.updatedAt = updatedAt
        return other == self
    }

    // MARK: Derived figures shared by the widget layouts

    var today: Int { days.last?.count ?? 0 }
    func lastDays(_ count: Int) -> [Day] { Array(days.suffix(count)) }
    func total(days count: Int) -> Int { lastDays(count).reduce(0) { $0 + $1.count } }
    var peak: Day? { days.max { $0.count < $1.count } }

    /// Columns of seven days (a calendar week each, first weekday on top), the
    /// current week last; days after today are nil.
    func weeks(_ count: Int, calendar: Calendar = .current) -> [[Day?]] {
        guard let last = days.last else { return [] }
        let weekday = (calendar.component(.weekday, from: last.date) - calendar.firstWeekday + 7) % 7
        var cells: [Day?] = days.suffix(count * 7 - (6 - weekday)).map { $0 }
        cells += Array(repeating: nil, count: 6 - weekday)
        if cells.count < count * 7 { cells = Array(repeating: nil, count: count * 7 - cells.count) + cells }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }
}

/// Links from a widget into a chat: stillfail://chat?workspace=…&account=…&station=…&session=…&thread=…
enum WidgetLink {
    static func chat(workspace: String, account: String, station: String, session: String, thread: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "stillfail"; components.host = "chat"
        var items = [URLQueryItem(name: "workspace", value: workspace), URLQueryItem(name: "account", value: account),
                     URLQueryItem(name: "station", value: station), URLQueryItem(name: "session", value: session)]
        if let thread { items.append(URLQueryItem(name: "thread", value: String(thread))) }
        components.queryItems = items
        return components.url
    }
    static let home = URL(string: "stillfail://home")!
}
