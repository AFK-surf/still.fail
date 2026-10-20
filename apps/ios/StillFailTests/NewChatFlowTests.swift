import XCTest
@testable import StillFail

@MainActor
final class NewChatFlowTests: XCTestCase {
    func testRapidSendTapOnlyCreatesOneConversation() async {
        let flow = NewChatFlow()
        var draft = ChatDraft(); draft.text = "hello"
        var creates = 0
        let call: NewChatFlow.Call = { name, _ in
            if name == "newChat.create" {
                creates += 1
                try await Task.sleep(for: .milliseconds(30))
                return .object(["key": .string("new:1-1")])
            }
            return .null
        }
        let first = Task { await flow.send(draft, station: "w/s", call: call) }
        await Task.yield()
        let repeated = await flow.send(draft, station: "w/s", call: call)
        let accepted = await first.value
        XCTAssertFalse(repeated); XCTAssertTrue(accepted); XCTAssertEqual(creates, 1)
    }

    func testFirstSendUsesPendingAliasAndPreservesAttachments() async throws {
        let flow = NewChatFlow()
        var draft = ChatDraft(); draft.text = "First message"
        draft.files = [.object(["path": .string("uploads/photo.jpg"), "name": .string("photo.jpg")])]
        var calls: [(String, [String: JSONValue])] = []
        let accepted = await flow.send(draft, station: "w/s") { name, params in
            calls.append((name, params))
            return name == "newChat.create" ? .object(["key": .string("new:1-1")]) : .null
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(calls.map(\.0), ["newChat.create", "chat.send"])
        XCTAssertEqual(calls[1].1["session"], .string("new:1-1"))
        XCTAssertNil(calls[1].1["thread"])
        XCTAssertEqual(calls[1].1["attachments"], .array(draft.files))
        XCTAssertEqual(flow.outgoing, draft)
        XCTAssertEqual(flow.openedRoute?.session, "new:1-1")
    }

    func testRejectedSendRetriesSameCreatedChat() async {
        let flow = NewChatFlow()
        var draft = ChatDraft(); draft.text = "hello"
        var creates = 0; var sends = 0
        let call: NewChatFlow.Call = { name, _ in
            if name == "newChat.create" { creates += 1; return .object(["key": .string("new:1-1")]) }
            sends += 1
            if sends == 1 { throw CoreFailure(code: "not_ready") }
            return .null
        }
        let first = await flow.send(draft, station: "w/s", call: call)
        XCTAssertFalse(first); XCTAssertNil(flow.openedRoute); XCTAssertNil(flow.outgoing)
        let second = await flow.send(draft, station: "w/s", call: call)
        XCTAssertTrue(second); XCTAssertEqual(creates, 1); XCTAssertEqual(sends, 2)
    }

    func testUncertainSendCannotCreateOrSendDuplicate() async {
        let flow = NewChatFlow()
        var draft = ChatDraft(); draft.text = "hello"
        var calls = 0
        let call: NewChatFlow.Call = { name, _ in
            calls += 1
            if name == "newChat.create" { return .object(["key": .string("new:1-1")]) }
            throw CoreFailure(code: "timeout_uncertain")
        }
        let first = await flow.send(draft, station: "w/s", call: call)
        XCTAssertFalse(first); XCTAssertTrue(flow.uncertain); XCTAssertEqual(flow.outgoing, draft)
        let second = await flow.send(draft, station: "w/s", call: call)
        XCTAssertFalse(second); XCTAssertEqual(calls, 2)
        flow.inspectCreatedChat()
        XCTAssertEqual(flow.openedRoute?.session, "new:1-1")
    }

    func testRejectedCreationCanRetryButEmptyInputDoesNotCreate() async {
        let flow = NewChatFlow()
        var calls = 0
        let call: NewChatFlow.Call = { _, _ in calls += 1; throw CoreFailure(code: "not_ready") }
        let empty = await flow.send(ChatDraft(), station: "w/s", call: call)
        XCTAssertFalse(empty); XCTAssertEqual(calls, 0)
        var draft = ChatDraft(); draft.text = "hello"
        let first = await flow.send(draft, station: "w/s", call: call)
        let second = await flow.send(draft, station: "w/s", call: call)
        XCTAssertFalse(first); XCTAssertFalse(second); XCTAssertEqual(calls, 2)
        XCTAssertNil(flow.createdRoute)
    }

    func testDraftReadKeepsTypingAndSavedAttachments() async {
        let state = NewChatDraftState()
        let file = JSONValue.object(["path": .string("uploads/saved.jpg")])
        let read = Task {
            await state.load(key: "a:new:w/s", station: "w/s") { name, _ in
                if name == "draft.get" {
                    try await Task.sleep(for: .milliseconds(20))
                    return .object(["text": .string("saved"), "files": .array([file])])
                }
                return .null
            }
        }
        await Task.yield()
        state.draft.text = "typed while loading"
        await read.value
        XCTAssertEqual(state.draft.text, "saved\n\ntyped while loading")
        XCTAssertEqual(state.draft.files, [file])
        XCTAssertTrue(state.loaded)
    }

    func testLaterDraftReadWinsEvenWhenOlderReadFinishesLast() async {
        let state = NewChatDraftState()
        var reads = 0
        let call: NewChatFlow.Call = { name, _ in
            guard name == "draft.get" else { return .null }
            reads += 1
            let read = reads
            try await Task.sleep(for: .milliseconds(read == 1 ? 40 : 5))
            return .object(["text": .string(read == 1 ? "stale" : "latest")])
        }
        let older = Task { await state.load(key: "a:new:w/s", station: "w/s", call: call) }
        while reads == 0 { await Task.yield() }
        await state.load(key: "a:new:w/s", station: "w/s", call: call)
        await older.value
        XCTAssertEqual(state.draft.text, "latest")
    }

    func testLeavingDuringDraftReadStillPreservesTypingWithoutReplacingSavedDraft() async {
        let state = NewChatDraftState()
        var savedText: JSONValue?
        let read = Task {
            await state.load(key: "a:new:w/s", station: "w/s") { name, params in
                if name == "draft.get" {
                    try await Task.sleep(for: .milliseconds(20))
                    return .object(["text": .string("saved")])
                }
                savedText = params["text"]
                return .null
            }
        }
        await Task.yield()
        state.draft.text = "typed"
        read.cancel()
        await read.value
        await Task.yield()
        XCTAssertEqual(state.draft.text, "saved\n\ntyped")
        XCTAssertEqual(savedText, .string("saved\n\ntyped"))
    }

    func testNodeSwitchKeepsAttachmentsWithTheirOriginalNode() async {
        let state = NewChatDraftState()
        let firstFile = JSONValue.object(["path": .string("uploads/first.jpg")])
        let secondFile = JSONValue.object(["path": .string("uploads/second.jpg")])
        var saved: [[String: JSONValue]] = []
        let call: NewChatFlow.Call = { name, params in
            if name == "draft.put" { saved.append(params); return .null }
            return .object(["text": .string(params["station"] == .string("w/first") ? "first" : "second"),
                            "files": .array([params["station"] == .string("w/first") ? firstFile : secondFile])])
        }
        await state.load(key: "a:new:w/first", station: "w/first", call: call)
        state.draft.text = "first edited"
        await state.load(key: "a:new:w/second", station: "w/second", call: call)
        XCTAssertEqual(state.draft.files, [secondFile])
        await state.load(key: "a:new:w/first", station: "w/first", call: call)
        XCTAssertEqual(state.draft.text, "first edited")
        XCTAssertEqual(state.draft.files, [firstFile])
        await Task.yield()
        XCTAssertTrue(saved.contains { $0["station"] == .string("w/first") && $0["files"] == .array([firstFile]) && $0["text"] == .string("first edited") })
    }

    func testRejectedFirstSendRestoresSubmittedAndNewTypingWithoutDuplicatingFiles() {
        var sent = ChatDraft(); sent.text = "submitted"
        sent.files = [.object(["path": .string("uploads/photo.jpg")])]
        var next = ChatDraft(); next.text = "next message"; next.files = sent.files
        let restored = NewChatDraftState.merge(saved: sent, typed: next)
        XCTAssertEqual(restored.text, "submitted\n\nnext message")
        XCTAssertEqual(restored.files, sent.files)
    }
}
