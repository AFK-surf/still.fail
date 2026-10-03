import XCTest
@testable import StillFail

final class SlackTimelineTests: XCTestCase {
    private func message(_ seq: Int, at seconds: Double, kind: String = "person", mine: Bool = true) -> JSONValue {
        .object(["seq": .number(Double(seq)), "authorKind": .string(kind), "author": .string(kind == "person" ? "me" : "a"),
                 "mine": .bool(mine), "text": .string("m\(seq)"), "createdAt": .number(seconds * 1000)])
    }
    private let slackPlace: JSONValue = .object(["name": .string("Acme#ops"), "surface": .string("slack"), "url": .string("https://acme.slack.com/archives/C1/p1")])
    private let emberPlace: JSONValue = .object(["name": .string("修登录"), "surface": .string("ember"), "session": .string("s1")])
    private func agent(slack: Bool) -> JSONValue {
        .object(["session": .object(["key": .string("a"), "agentText": .string("Opus · high")]),
                 "threads": .array([.object(["surface": .string("ember")])] + (slack ? [.object(["surface": .string("slack:T1")])] : []))])
    }
    private func history(_ items: [JSONValue]) -> JSONValue { .object(["items": .array(items)]) }
    private func received(_ key: String, ts: String, place: JSONValue, bound: Bool = false) -> JSONValue {
        .object(["key": .string(key), "at": .number(0), "body": .object(["kind": .string("received"), "content": .object(["messages": .array([
            .object(["key": .string(ts), "from": .object(["name": .string("Ada"), "slackUser": .string("U1"), "bound": .bool(bound)]), "text": .string("from slack \(ts)"), "place": place])])])])])
    }
    private func post(_ key: String, at seconds: Double, place: JSONValue, failed: Bool = false) -> JSONValue {
        .object(["key": .string(key), "at": .number(seconds * 1000), "body": .object(["kind": .string("post"), "content": .object([
            "text": .string("reply \(key)"), "place": place, "block": .bool(false), "failed": .bool(failed)])])])
    }

    func testSlackWordsJoinTheTimelineInTimeOrderAndEmberOnesAreNotRepeated() {
        let value: JSONValue = .object(["thread": .object(["surface": .string("ember")]), "agents": .array([agent(slack: true)]),
                                        "messages": .array([message(1, at: 100), message(2, at: 300, kind: "agent", mine: false)])])
        let rows = ChatTimeline.rows(value: value, initialOutgoing: nil, lives: [:], histories: ["a": history([
            received("e1", ts: "200.5", place: slackPlace),
            received("e2", ts: "250", place: emberPlace),
            post("e3", at: 400, place: slackPlace),
            post("e4", at: 150, place: emberPlace)])])
        XCTAssertEqual(rows.map { $0.value.text("text") }, ["m1", "from slack 200.5", "m2", "reply e3"])
        XCTAssertEqual(rows[1].value["slack"].text("direction"), "from")
        XCTAssertEqual(rows[1].value["slack"].text("url"), "https://acme.slack.com/archives/C1/p1")
        XCTAssertTrue(rows[1].isPerson); XCTAssertFalse(rows[1].isMine)
        XCTAssertEqual(rows[3].value["slack"].text("direction"), "to")
        XCTAssertEqual(rows[3].value["by"].text("name"), "Opus · high")
        // The agent's Slack reply follows its own chat message as one run.
        XCTAssertFalse(rows[3].showsAuthor)
    }

    func testOnlyAgentsInASlackThreadAreReadAndEarlierWordsWaitForOlderPages() {
        let value: JSONValue = .object(["thread": .object(["surface": .string("ember")]), "agents": .array([agent(slack: true)]), "more": .bool(true),
                                        "messages": .array([message(5, at: 500)])])
        XCTAssertEqual(ChatSlack.historyKeys(value: value), ["a"])
        var plain = value.objectValue; plain["agents"] = .array([agent(slack: false)])
        XCTAssertEqual(ChatSlack.historyKeys(value: .object(plain)), [])
        let rows = ChatTimeline.rows(value: value, initialOutgoing: nil, lives: [:], histories: ["a": history([
            received("e1", ts: "100", place: slackPlace), received("e2", ts: "600", place: slackPlace, bound: true)])])
        XCTAssertEqual(rows.map(\.id).filter { $0.hasPrefix("slack:") }, ["slack:in:Acme#ops:600"])
        // Said by the viewer in Slack: their own bubble.
        XCTAssertTrue(rows.last?.isMine == true)
    }

    func testASlackThreadMarksItsOwnMessagesWithItsLink() {
        let value: JSONValue = .object(["thread": .object(["surface": .string("slack:T1")]), "slackUrl": .string("https://acme.slack.com/x"), "place": .string("#ops"),
                                        "messages": .array([message(1, at: 1, mine: false), message(2, at: 2, kind: "agent", mine: false)])])
        let rows = ChatTimeline.rows(value: value, initialOutgoing: nil, lives: [:], histories: ["a": history([received("e1", ts: "1.5", place: slackPlace)])])
        XCTAssertEqual(rows.count, 2, "a Slack thread's messages are its Slack words already")
        XCTAssertEqual(rows.map { $0.value["slack"].text("direction") }, ["from", "to"])
        XCTAssertEqual(rows[0].value["slack"].text("url"), "https://acme.slack.com/x")
    }
}

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; calendar.firstWeekday = 2
        return calendar
    }
    func testSnapshotPicksDecisionsRecentTasksAndCountsTasksByDay() {
        let now = Date(timeIntervalSince1970: 1_790_467_200) // 2026-09-27 00:00 UTC
        func row(_ id: String, minutesAgo: Double, decision: String? = nil, createdDaysAgo: Double = 0) -> JSONValue {
            var fields: [String: JSONValue] = ["id": .string(id), "station": .string("st"), "session": .string(id), "title": .string("T\(id)"),
                "lastActiveAt": .number((now.timeIntervalSince1970 - minutesAgo * 60) * 1000),
                "time": .object(["createdAt": .object(["at": .number((now.timeIntervalSince1970 - createdDaysAgo * 86400 + 60) * 1000)])])]
            if let decision { fields["decision"] = .object(["text": .string(decision)]) }
            return .object(fields)
        }
        let chats: JSONValue = .object(["days": .array([.object(["items": .array([
            row("1", minutesAgo: 30), row("2", minutesAgo: 5, decision: "Ship?"), row("3", minutesAgo: 60 * 30, createdDaysAgo: 2)])])])])
        let archived = WidgetFeed.count([now.addingTimeInterval(-86400 * 2 + 10)], calendar: calendar)
        let snapshot = WidgetFeed.snapshot(chats: chats, archiveDays: archived, workspace: "w", account: "a", name: "Team", now: now, calendar: calendar)
        XCTAssertEqual(snapshot.decisions.map(\.id), ["st:2:"])
        XCTAssertEqual(snapshot.decisions.first?.summary, "Ship?")
        XCTAssertEqual(snapshot.decisionCount, 1)
        XCTAssertEqual(snapshot.recent.map(\.title), ["T2", "T1", "T3"])
        XCTAssertEqual(snapshot.days.count, WidgetSnapshot.dayCount)
        XCTAssertEqual(snapshot.days.last?.date, now)
        XCTAssertEqual(snapshot.today, 2)
        XCTAssertEqual(snapshot.days[snapshot.days.count - 3].count, 2, "a chat begun then plus one archived that day")
        XCTAssertEqual(snapshot.recent.first?.link?.host, "chat")
    }

    func testWeeksEndOnTheCurrentWeekWithFutureDaysEmpty() {
        let start = Date(timeIntervalSince1970: 1_790_467_200) // a Sunday
        let days = (0..<20).map { WidgetSnapshot.Day(date: calendar.date(byAdding: .day, value: $0 - 19, to: start)!, count: $0) }
        let snapshot = WidgetSnapshot(updatedAt: start, workspace: "", decisions: [], decisionCount: 0, recent: [], days: days)
        let weeks = snapshot.weeks(2, calendar: calendar)
        XCTAssertEqual(weeks.count, 2)
        // Weeks begin on Monday here; Sunday ends the current week, so nothing is in the future.
        XCTAssertEqual(weeks[1].compactMap { $0?.count }, [13, 14, 15, 16, 17, 18, 19])
        let saturday = WidgetSnapshot(updatedAt: start, workspace: "", decisions: [], decisionCount: 0, recent: [], days: Array(days.dropLast()))
        XCTAssertEqual(saturday.weeks(1, calendar: calendar)[0].map { $0?.count }, [13, 14, 15, 16, 17, 18, nil])
    }
}
