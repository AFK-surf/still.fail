import XCTest
@testable import StillFail

private final class WidgetReplyEngine: CoreEngine, @unchecked Sendable {
    private let callback: @Sendable (UInt64, String) -> Void
    let fail: Bool
    init(fail: Bool, callback: @escaping @Sendable (UInt64, String) -> Void) { self.fail = fail; self.callback = callback }
    func connect() -> UInt64 { 1 }
    func disconnect(client: UInt64) {}
    func receive(client: UInt64, json: String) {
        let now = Date().timeIntervalSince1970 * 1000
        let reply: JSONValue = fail ? .object(["id": .number(1), "error": .object(["code": .string("offline")])]) :
            .object(["id": .number(1), "ok": .object(["name": .string("Independent"), "archivedAt": .array([]),
                "chats": .object(["days": .array([.object(["items": .array([.object([
                    "station": .string("w/s"), "session": .string("one"), "title": .string("Fresh from widget"),
                    "time": .object(["createdAt": .object(["at": .number(now)])])])])])])])])])
        callback(1, try! reply.encoded())
    }
}
final class WidgetSyncTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testReaderUpdatesSnapshotWithoutAppStoreOrForegroundLifecycle() async throws {
        let directory = try directory()
        try WidgetFiles.select(account: "a", workspace: "w", in: directory)
        let sync = WidgetSync(directory: directory, factory: { WidgetReplyEngine(fail: false, callback: $0) })
        let result = await sync.update()
        XCTAssertEqual(result?.today, 1)
        XCTAssertEqual(result?.recent.first?.title, "Fresh from widget")
        XCTAssertTrue(result?.sameContent(as: WidgetSnapshot.load(from: directory.appendingPathComponent(WidgetSnapshot.fileName))) == true)
    }
    func testFailedReadPreservesPreviousGoodSnapshot() async throws {
        let directory = try directory()
        try WidgetFiles.select(account: "a", workspace: "w", in: directory)
        let saved = WidgetSnapshot(updatedAt: Date(timeIntervalSince1970: 1000), workspace: "old", decisions: [], decisionCount: 0, recent: [], days: [])
        let selection = try XCTUnwrap(WidgetFiles.selection(in: directory))
        try WidgetFiles.commit(saved, for: selection, in: directory)
        let sync = WidgetSync(directory: directory, factory: { WidgetReplyEngine(fail: true, callback: $0) })
        let result = await sync.update()
        XCTAssertEqual(result, saved)
        XCTAssertEqual(WidgetSnapshot.load(from: directory.appendingPathComponent(WidgetSnapshot.fileName)), saved)
    }
    func testChangedAccountRejectsInFlightOldSnapshot() throws {
        let directory = try directory()
        try WidgetFiles.select(account: "a", workspace: "w", in: directory)
        let selection = try XCTUnwrap(WidgetFiles.selection(in: directory))
        try WidgetFiles.select(account: "b", workspace: "w", in: directory)
        let old = WidgetSnapshot(updatedAt: Date(timeIntervalSince1970: 1000), workspace: "old", decisions: [], decisionCount: 0, recent: [], days: [])
        XCTAssertFalse(try WidgetFiles.commit(old, for: selection, in: directory))
        XCTAssertNil(WidgetSnapshot.load(from: directory.appendingPathComponent(WidgetSnapshot.fileName)))
    }
    func testWidgetCannotResurrectSignedOutAccountsOrDiscardAnotherAccount() throws {
        let incoming = Data(#"[{"sub":"a","access_expires":200},{"sub":"removed","access_expires":999}]"#.utf8)
        let current = Data(#"[{"sub":"a","access_expires":300},{"sub":"b","access_expires":100}]"#.utf8)
        let merged = try JSONValue.parse(String(decoding: WidgetCredentials.merge(incoming: incoming, current: current, widget: true), as: UTF8.self)).arrayValue
        XCTAssertEqual(merged.map { $0.text("sub") }, ["a", "b"])
        XCTAssertEqual(merged.first?["access_expires"].intValue, 300)
        let signedOut = try WidgetCredentials.merge(incoming: incoming, current: Data("[]".utf8), widget: true)
        XCTAssertEqual(try JSONValue.parse(String(decoding: signedOut, as: UTF8.self)), .array([]))
    }
}
