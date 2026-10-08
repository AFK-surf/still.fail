import XCTest
@testable import StillFail

final class ChatRenderingTests: XCTestCase {
    private func person(_ author: String, _ seq: Int, mine: Bool = false) -> JSONValue {
        .object(["seq": .number(Double(seq)), "authorKind": .string("person"), "author": .string(author), "mine": .bool(mine), "text": .string("Hello")])
    }
    func testCollaboratorGroupingStopsAtDifferentSpeakerAndAgent() {
        let messages = [person("alice", 1), person("alice", 2), person("bob", 3),
                        JSONValue.object(["seq": .number(4), "authorKind": .string("agent"), "author": .string("agent")]), person("bob", 5)]
        let rows = ChatTimeline.rows(value: .object(["messages": .array(messages)]), initialOutgoing: nil, lives: [:])
        XCTAssertEqual(rows.map(\.showsAuthor), [true, false, true, true, true])
        XCTAssertTrue(rows[0].isPerson)
        XCTAssertFalse(rows[3].isPerson)
    }
    func testMyBubblesCannotJoinAnotherPersonsGroup() {
        let rows = ChatTimeline.rows(value: .object(["messages": .array([person("alice", 1), person("me", 2, mine: true), person("alice", 3)])]), initialOutgoing: nil, lives: [:])
        XCTAssertEqual(rows.map(\.showsAuthor), [true, true, true])
        XCTAssertTrue(rows[1].isMine)
    }
    func testCoreOutgoingIdentitySurvivesDelivery() {
        let outgoing: JSONValue = .object(["id": .string("out-1"), "text": .string("Hello")])
        var delivered = person("me", 7, mine: true).objectValue
        delivered["outgoing"] = .string("out-1")
        let before = ChatTimeline.rows(value: .object(["outbox": .array([outgoing])]), initialOutgoing: nil, lives: [:])
        let after = ChatTimeline.rows(value: .object(["messages": .array([.object(delivered)])]), initialOutgoing: nil, lives: [:])
        XCTAssertEqual(before.first?.id, after.first?.id)
    }
    func testOptimisticHandoffRequiresExactAttachmentsAndQuotes() {
        var draft = ChatDraft(); draft.text = "Hello"
        draft.files = [.object(["path": .string("file"), "name": .string("file.txt")])]
        draft.quotes = [.object(["text": .string("quoted")])]
        var incoming = person("me", 1, mine: true).objectValue
        XCTAssertFalse(ChatTimeline.contains(draft, value: .object(["messages": .array([.object(incoming)])])))
        incoming["attachments"] = .array(draft.files); incoming["quotes"] = .array(draft.quotes)
        let value: JSONValue = .object(["messages": .array([.object(incoming)])])
        XCTAssertTrue(ChatTimeline.contains(draft, value: value))
        XCTAssertEqual(ChatTimeline.rows(value: value, initialOutgoing: draft, lives: [:]).count, 1)
        XCTAssertEqual(ChatTimeline.rows(value: .null, initialOutgoing: draft, lives: [:]).first?.id, "initialOutgoing")
    }
    func testLiveEndedStepsAreNotRenderedTwice() {
        let value: JSONValue = .object(["agents": .array([.object(["session": .object(["key": .string("a"), "agentText": .string("Model · high")])])])])
        let live: JSONValue = .object(["steps": .array([
            .object(["id": .string("1"), "step": .string("text"), "input": .string("Growing"), "ended": .bool(false)]),
            .object(["id": .string("2"), "step": .string("text"), "input": .string("Done"), "ended": .bool(true)])])])
        let rows = ChatTimeline.rows(value: value, initialOutgoing: nil, lives: ["a": live])
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(rows[0].streaming)
        XCTAssertEqual(rows[0].value.text("text"), "Growing")
    }
    func testOpeningPositionPreservesOffsetOnlyForExactEntry() {
        let rows = [2, 4, 6].map { ChatTimelineRow(id: "row:\($0)", kind: .message, value: person("alice", $0)) }
        XCTAssertEqual(ChatTimeline.opening(rows, seq: 4, offset: -12.5)?.id, "row:4")
        XCTAssertEqual(ChatTimeline.opening(rows, seq: 4, offset: -12.5)?.offset, -12.5)
        XCTAssertEqual(ChatTimeline.opening(rows, seq: 3, offset: -12.5)?.id, "row:4")
        XCTAssertEqual(ChatTimeline.opening(rows, seq: 3, offset: -12.5)?.offset, 0)
        XCTAssertEqual(ChatTimeline.opening(rows, seq: 4, offset: .infinity)?.offset, 0)
        XCTAssertNil(ChatTimeline.opening(rows, seq: nil, offset: 10))
    }
    func testLiveMarkdownTailRepairDoesNotChangeCodeOrEscapedDelimiters() {
        XCTAssertEqual(MarkdownStreamingRepair.repair("**Growing"), "**Growing**")
        XCTAssertEqual(MarkdownStreamingRepair.repair("`let value"), "`let value`")
        XCTAssertEqual(MarkdownStreamingRepair.repair("```swift\nlet x = a * b"), "```swift\nlet x = a * b")
        XCTAssertEqual(MarkdownStreamingRepair.repair("* First item"), "* First item")
        XCTAssertEqual(MarkdownStreamingRepair.repair("Costs $5"), "Costs $5")
        XCTAssertEqual(MarkdownStreamingRepair.repair("> ```swift\n> let x = a * b"), "> ```swift\n> let x = a * b")
        XCTAssertEqual(MarkdownStreamingRepair.repair(#"escaped \*"#), #"escaped \*"#)
    }
    func testToolJSONAndFencesRemainReadable() {
        let json = HistoryRendering.tool(#"{"hello":"world"}"#, name: "read")
        XCTAssertTrue(json.hasPrefix("```json\n")); XCTAssertTrue(json.contains("\"hello\""))
        let nested = HistoryRendering.tool("```swift\nlet a = 1\n```", name: "terminal")
        XCTAssertTrue(nested.hasPrefix("````text\n"))
        XCTAssertEqual(HistoryRendering.tool("**result**", name: "browser"), "**result**")
        XCTAssertTrue(HistoryRendering.fence("```\n~~~~\n````", language: "text").hasPrefix("`````text\n"))
    }
}
