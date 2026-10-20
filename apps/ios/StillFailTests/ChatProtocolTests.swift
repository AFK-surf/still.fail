import XCTest
@testable import StillFail

/// Pure protocol tests only: no engine, login, station, or runtime is started.
final class ChatProtocolTests: XCTestCase {
    private let pendingRoute = ChatRoute(station: "w/s", session: "new:1-1")
    private let existingRoute = ChatRoute(station: "w/s", session: "ember:c-1", thread: 7)

    private func pending(failed: Bool = false) throws -> JSONValue {
        try JSONValue.parse(failed
            ? #"{"thread":null,"pending":true,"key":null,"failed":"creation failed","messages":[],"outbox":[]}"#
            : #"{"thread":null,"pending":true,"key":null,"failed":null,"messages":[],"outbox":[]}"#)
    }

    private func draft() throws -> ChatDraft {
        ChatDraft(try JSONValue.parse(#"{"text":"hello","quotes":[{"author":"A","text":"quoted","role":"person","comment":"","ts":"now"}],"files":[{"name":"note.txt","path":"uploads/note.txt","size":12}]}"#))
    }

    func testPendingAndFailedCreationKeepComposerAvailable() throws {
        XCTAssertTrue(ChatProtocol.canCompose(route: pendingRoute, value: try pending()))
        XCTAssertTrue(ChatProtocol.canCompose(route: pendingRoute, value: try pending(failed: true)))
        XCTAssertNil(ChatProtocol.thread(route: pendingRoute, value: try pending()))
    }

    func testComposerStaysAvailableWhileMadeChatWaitsForThreadValue() throws {
        let value = try JSONValue.parse(#"{"thread":null,"pending":false,"key":"ember:c-1"}"#)
        XCTAssertTrue(ChatProtocol.canCompose(route: pendingRoute, value: value))
        // Core still recognizes the original pending alias; never invent a thread.
        XCTAssertEqual(ChatProtocol.retry(route: pendingRoute, value: value, id: "out-1"),
                       ["station": .string("w/s"), "session": .string("new:1-1"), "id": .string("out-1")])
    }

    func testComposerStillHonorsArchiveAndSurfaceRestrictions() throws {
        let archived = try JSONValue.parse(#"{"thread":null,"pending":true,"archived":true}"#)
        let readOnly = try JSONValue.parse(#"{"thread":{"id":7,"surface":"other"}}"#)
        let ember = try JSONValue.parse(#"{"thread":{"id":7,"surface":"ember"}}"#)
        let legacy = try JSONValue.parse(#"{"thread":{"id":7}}"#)
        XCTAssertFalse(ChatProtocol.canCompose(route: pendingRoute, value: archived))
        XCTAssertFalse(ChatProtocol.canCompose(route: existingRoute, value: readOnly))
        XCTAssertTrue(ChatProtocol.canCompose(route: existingRoute, value: ember))
        XCTAssertTrue(ChatProtocol.canCompose(route: existingRoute, value: legacy))
        XCTAssertFalse(ChatProtocol.canCompose(route: pendingRoute, value: .null))
        XCTAssertFalse(ChatProtocol.canCompose(route: ChatRoute(station: "w/s", session: ""), value: try pending()))
        XCTAssertFalse(ChatProtocol.canCompose(route: existingRoute, value: try JSONValue.parse(#"{"thread":null}"#)))
    }

    func testReadingPlaceRequiresKnownThreadAndClearsAtEnd() throws {
        XCTAssertNil(ChatProtocol.place(route: pendingRoute, value: try pending(), seq: 4, offset: -12.5))
        XCTAssertEqual(ChatProtocol.place(route: existingRoute, value: .null, seq: 4, offset: -12.5),
                       ["station": .string("w/s"), "thread": .number(7), "seq": .number(4), "offset": .number(-12.5)])
        XCTAssertEqual(ChatProtocol.place(route: existingRoute, value: .null, seq: nil, offset: 30),
                       ["station": .string("w/s"), "thread": .number(7), "seq": .null, "offset": .null])
        XCTAssertEqual(ChatProtocol.place(route: existingRoute, value: .null, seq: 4, offset: .infinity)?["offset"], .null)
    }

    func testPendingSendUsesSessionAndPreservesQuotesAndAttachments() throws {
        let original = try draft()
        let params = ChatProtocol.send(route: pendingRoute, value: try pending(), draft: original)
        let expected = try JSONValue.parse(#"{"station":"w/s","session":"new:1-1","text":"hello","quotes":[{"author":"A","text":"quoted","role":"person","comment":"","ts":"now"}],"attachments":[{"name":"note.txt","path":"uploads/note.txt","size":12}],"client":"ios"}"#)
        XCTAssertEqual(.object(params), expected)
        XCTAssertEqual(original, try draft(), "Building wire params must not clear the retained draft")
        XCTAssertNil(params["thread"])
        XCTAssertNil(params["files"])
        XCTAssertNil(params["key"])
    }

    func testAttachmentAndQuoteOnlyDraftsAreNotLostForPendingSend() throws {
        var attachmentsOnly = ChatDraft()
        attachmentsOnly.files = [.object(["name": .string("note.txt"), "path": .string("uploads/note.txt")])]
        XCTAssertFalse(attachmentsOnly.isEmpty)
        let attachmentParams = ChatProtocol.send(route: pendingRoute, value: try pending(), draft: attachmentsOnly)
        XCTAssertEqual(attachmentParams["attachments"], .array(attachmentsOnly.files))
        XCTAssertEqual(attachmentParams["text"], .string(""))
        var quotesOnly = ChatDraft()
        quotesOnly.quotes = [.object(["text": .string("quoted")])]
        XCTAssertFalse(quotesOnly.isEmpty)
        XCTAssertEqual(ChatProtocol.send(route: pendingRoute, value: try pending(), draft: quotesOnly)["quotes"], .array(quotesOnly.quotes))
    }

    func testExistingSendUsesNumericThreadRatherThanSession() throws {
        let params = ChatProtocol.send(route: existingRoute, value: .null, draft: ChatDraft())
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"station":"w/s","thread":7,"text":"","quotes":[],"attachments":[],"client":"ios"}"#))
        XCTAssertNil(params["session"])
    }

    func testSendSwitchesToThreadAsSoonAsTopicProvidesIt() throws {
        let value = try JSONValue.parse(#"{"thread":{"id":19,"surface":"ember"},"key":"ember:actual","pending":false}"#)
        let params = ChatProtocol.send(route: pendingRoute, value: value, draft: ChatDraft())
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"station":"w/s","thread":19,"text":"","quotes":[],"attachments":[],"client":"ios"}"#))
        XCTAssertEqual(ChatProtocol.thread(route: existingRoute, value: value), 19, "Live thread takes precedence over route fallback")
    }

    func testPendingRetryTargetsRetainedOutboxEntryBySession() throws {
        let params = ChatProtocol.retry(route: pendingRoute, value: try pending(failed: true), id: "out-1")
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"station":"w/s","session":"new:1-1","id":"out-1"}"#))
        XCTAssertNil(params["thread"])
        XCTAssertNil(params["text"], "Retry must reuse the core-owned entry, not submit another message")
    }

    func testExistingRetryUsesNumericThreadAndOriginalID() throws {
        XCTAssertEqual(.object(ChatProtocol.retry(route: existingRoute, value: .null, id: "out-1")),
                       try JSONValue.parse(#"{"station":"w/s","thread":7,"id":"out-1"}"#))
        let made = try JSONValue.parse(#"{"thread":{"id":19},"pending":false}"#)
        XCTAssertEqual(.object(ChatProtocol.retry(route: pendingRoute, value: made, id: "out-1")),
                       try JSONValue.parse(#"{"station":"w/s","thread":19,"id":"out-1"}"#))
    }

    func testPendingFocusNamesSessionAndEndWithoutInvalidKeyOrLeft() throws {
        let params = ChatProtocol.focus(route: pendingRoute, value: try pending(), workspace: "w", visible: true, readerAtEnd: true)
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"workspace":"w","chat":{"station":"w/s","session":"new:1-1","end":true},"visible":true,"focused":true}"#))
        XCTAssertNil(params["left"])
        XCTAssertNil(params["end"], "Read position belongs inside ChatOf")
        XCTAssertNil(params["chat"]?.objectValue["key"])
    }

    func testExistingFocusIncludesBothSessionAndNumericThread() throws {
        let value = try JSONValue.parse(#"{"thread":{"id":19}}"#)
        let params = ChatProtocol.focus(route: existingRoute, value: value, workspace: "w", visible: true, readerAtEnd: true)
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"workspace":"w","chat":{"station":"w/s","session":"ember:c-1","thread":19,"end":true},"visible":true,"focused":true}"#))
    }

    func testFocusKeepsPendingRouteSessionWhenThreadBecomesKnown() throws {
        let value = try JSONValue.parse(#"{"thread":{"id":19},"key":"ember:actual","pending":false}"#)
        let params = ChatProtocol.focus(route: pendingRoute, value: value, workspace: "w", visible: true, readerAtEnd: true)
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"workspace":"w","chat":{"station":"w/s","session":"new:1-1","thread":19,"end":true},"visible":true,"focused":true}"#))
    }

    func testFocusEndRequiresBothReaderAtEndAndNoNewerPage() throws {
        for readerAtEnd in [false, true] {
            for newer in [false, true] {
                let value: JSONValue = .object(["newer": .bool(newer)])
                let params = ChatProtocol.focus(route: existingRoute, value: value, workspace: "w", visible: true, readerAtEnd: readerAtEnd)
                XCTAssertEqual(params["chat"]?["end"], .bool(readerAtEnd && !newer))
                XCTAssertNil(params["left"], "Scrolling is not departure")
            }
        }
    }

    func testBackgroundFocusPreservesChatAndReportsVisibilitySeparately() throws {
        let params = ChatProtocol.focus(route: existingRoute, value: .null, workspace: "w", visible: false, readerAtEnd: true)
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"workspace":"w","chat":{"station":"w/s","session":"ember:c-1","thread":7,"end":true},"visible":false,"focused":false}"#))
    }

    func testPendingDepartureUsesConditionalLeftChatOf() throws {
        let params = ChatProtocol.depart(route: pendingRoute, value: try pending())
        XCTAssertEqual(.object(params), try JSONValue.parse(#"{"left":{"station":"w/s","session":"new:1-1","end":false}}"#))
        XCTAssertNil(params["chat"], "Late departure must not unconditionally clear the next chat")
        XCTAssertNil(params["workspace"], "Departure must not restore the old workspace")
        XCTAssertNil(params["left"]?.boolValue)
    }

    func testExistingDepartureUsesKnownThreadAndSession() throws {
        let value = try JSONValue.parse(#"{"thread":{"id":19}}"#)
        XCTAssertEqual(.object(ChatProtocol.depart(route: existingRoute, value: value)),
                       try JSONValue.parse(#"{"left":{"station":"w/s","session":"ember:c-1","thread":19,"end":false}}"#))
    }
}
