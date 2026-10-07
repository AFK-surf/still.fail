import XCTest
@testable import StillFail

final class CoreJSONTests: XCTestCase {
    func testCodableConversionAndMissingKeys() throws {
        let value = try JSONValue.parse(#"{"null":null,"bool":true,"n":4,"a":["x"]}"#)
        XCTAssertEqual(value["missing"], .null)
        XCTAssertEqual(value["bool"].boolValue, true)
        XCTAssertEqual(value["n"].intValue, 4)
        XCTAssertNil(JSONValue.number(.infinity).intValue)
        XCTAssertNil(JSONValue.number(1.5).intValue)
        XCTAssertEqual(try JSONValue.parse(value.encoded()), value)
        XCTAssertEqual(try JSONValue.from(["a": [1, 2]]), .object(["a": .array([.number(1), .number(2)])]))
    }
    func testOrderedSetAppendRemoveAndNull() throws {
        let value = try JSONValue.parse(#"{"items":[{"title":"old"}],"link":{"message":"gone"}}"#)
        let ops = try JSONValue.parse(#"[{"path":["items",0,"title"],"set":"new"},{"path":["items"],"append":[{"title":"last"}]},{"path":["link","message"],"remove":true},{"path":["added"],"set":null}]"#)
        let expected = try JSONValue.parse(#"{"items":[{"title":"new"},{"title":"last"}],"link":{},"added":null}"#)
        XCTAssertEqual(applyDelta(value, ops.arrayValue), expected)
        XCTAssertEqual(applyDelta(value, [.object(["path": .array([]), "set": .null])]), .null)
        // Object keys and array indices are not interchangeable.
        XCTAssertEqual(applyDelta(value, try JSONValue.parse(#"[{"path":["items","0","title"],"set":"wrong"}]"#).arrayValue), value)
    }
    func testErrorRetainsDisplayButInvalidatesDeltaBase() throws {
        var state = CoreTopicState()
        state.receive(try JSONValue.parse(#"{"value":[1]}"#))
        state.receive(try JSONValue.parse(#"{"error":{"code":"offline","message":"secret payload"}}"#))
        XCTAssertEqual(state.value, .array([.number(1)]))
        XCTAssertNotNil(state.error); XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.error!.message.contains("secret"))
        state.receive(try JSONValue.parse(#"{"delta":[{"path":[],"append":[2]}]}"#))
        XCTAssertEqual(state.value, .array([.number(1)]))
        state.receive(try JSONValue.parse(#"{"value":null}"#))
        XCTAssertEqual(state.value, .null); XCTAssertNil(state.error)
        state.receive(try JSONValue.parse(#"{"value":[]}"#))
        XCTAssertEqual(state.value, .array([])); XCTAssertNil(state.error)
    }
}

/// The fixture exists ONLY in the test target. Its mutable state is lock-owned.
private final class TestCoreEngine: CoreEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (UInt64, String) -> Void)?
    private var messages: [JSONValue] = []
    private var connections = 0
    func attach(_ callback: @escaping @Sendable (UInt64, String) -> Void) { lock.lock(); self.callback = callback; lock.unlock() }
    func connect() -> UInt64 { lock.lock(); connections += 1; lock.unlock(); return 1 }
    func disconnect(client: UInt64) {}
    func receive(client: UInt64, json: String) {
        guard let message = try? JSONValue.parse(json) else { return }
        lock.lock(); messages.append(message); lock.unlock()
        if ["client.focus", "client.wake"].contains(message["call"].stringValue ?? "") { emit(.object(["id": message["id"], "ok": .null])) }
        if ["accounts", "workspaces"].contains(message["subscribe"]["topic"].stringValue ?? "") {
            emit(.object(["id": message["id"], "value": .array([])]))
        }
    }
    func emit(_ message: JSONValue) {
        lock.lock(); let callback = callback; lock.unlock()
        if let text = try? message.encoded() { callback?(1, text) }
    }
    func sent() -> [JSONValue] { lock.lock(); defer { lock.unlock() }; return messages }
    func connectionCount() -> Int { lock.lock(); defer { lock.unlock() }; return connections }
}

@MainActor
final class CoreStoreTests: XCTestCase {
    func testReturnFromBackgroundTellsCoreHowLongItWasAway() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await waitUntil { app.isReady }
        app.pause()
        try await Task.sleep(for: .milliseconds(25))
        app.resume()
        try await waitUntil { engine.sent().contains { $0["call"].stringValue == "client.wake" } }
        let wake = try XCTUnwrap(engine.sent().last { $0["call"].stringValue == "client.wake" })
        guard case .number(let away) = wake["params"]["away"] else { return XCTFail("wake needs elapsed milliseconds") }
        XCTAssertGreaterThanOrEqual(away, 20)
        XCTAssertEqual(wake["params"]["network"].boolValue, false)
        let count = engine.sent().filter { $0["call"].stringValue == "client.wake" }.count
        app.resume()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(engine.sent().filter { $0["call"].stringValue == "client.wake" }.count, count)
    }

    func testNetworkChangeWakesCoreWithoutLosingWorkspaceScope() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a"], groups: [group("a", [workspace()])])
        let epoch = app.scopeEpoch
        app.networkDidChange()
        try await waitUntil { engine.sent().contains { $0["call"].stringValue == "client.wake" } }
        let wake = try XCTUnwrap(engine.sent().last { $0["call"].stringValue == "client.wake" })
        XCTAssertEqual(wake["params"]["network"].boolValue, true)
        XCTAssertEqual(wake["params"]["away"], .number(0))
        XCTAssertEqual(app.scopeEpoch, epoch)
    }

    private func store(_ engine: TestCoreEngine, timeout: Duration = .seconds(5)) -> AppStore {
        AppStore(engineFactory: { engine.attach($0); return engine }, callTimeout: timeout)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Core condition did not arrive")
    }
    private func id(_ engine: TestCoreEngine, topic: String) -> JSONValue {
        engine.sent().last(where: { $0["subscribe"]["topic"].stringValue == topic })?["id"] ?? .null
    }
    private func account(_ sub: String) -> JSONValue { .object(["sub": .string(sub)]) }
    private func workspace(_ id: String = "w", role: String = "owner", name: String = "Workspace") -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "role": .string(role)])
    }
    private func group(_ sub: String, _ workspaces: [JSONValue], loaded: Bool = true, error: JSONValue = .null) -> JSONValue {
        .object(["account": account(sub), "workspaces": .array(workspaces), "loaded": .bool(loaded), "error": error])
    }
    private func loadScope(_ app: AppStore, _ engine: TestCoreEngine, accounts: [String], groups: [JSONValue]) async throws {
        try await waitUntil { app.isReady && self.id(engine, topic: "workspaces") != .null }
        let values = accounts.map { account($0) }
        engine.emit(.object(["id": id(engine, topic: "accounts"), "value": .array(values)]))
        try await waitUntil { app.accounts == values }
        try await updateGroups(app, engine, groups)
    }
    private func updateGroups(_ app: AppStore, _ engine: TestCoreEngine, _ groups: [JSONValue]) async throws {
        engine.emit(.object(["id": id(engine, topic: "workspaces"), "value": .array(groups)]))
        try await waitUntil { app.workspaceGroups == groups }
    }
    private func privateTopic(_ app: AppStore, _ engine: TestCoreEngine) async throws -> CoreTopic {
        let topic = app.subscribe("workspace", params: ["workspace": .string("w")])
        try await waitUntil { self.id(engine, topic: "workspace") != .null }
        engine.emit(.object(["id": id(engine, topic: "workspace"), "value": .string("private")]))
        try await waitUntil { topic.value != nil }
        return topic
    }
    func testUnchangedTopicStatesAreDroppedAndBurstsCoalesce() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a"], groups: [group("a", [workspace()])])
        let topic = try await privateTopic(app, engine)
        let first = topic.revision
        let request = id(engine, topic: "workspace")
        engine.emit(.object(["id": request, "value": .string("private")]))
        for n in 0..<20 { engine.emit(.object(["id": request, "value": .string("tick \(n)")])) }
        try await waitUntil { topic.value == .string("tick 19") }
        // The same value never re-renders; twenty in a burst arrive as a handful of states.
        XCTAssertLessThan(topic.revision - first, 6)
        // A reply still comes after the states sent before it.
        engine.emit(.object(["id": request, "value": .string("before focus")]))
        _ = try await app.call("client.focus")
        XCTAssertEqual(topic.value, .string("before focus"))
    }
    func testLaunchReopensTheLastWorkspaceUntilMembershipDisprovesIt() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "fail.still.tests.\(UUID().uuidString)"))
        let first = TestCoreEngine()
        let app = AppStore(engineFactory: { first.attach($0); return first }, callTimeout: .seconds(5), preferences: defaults)
        try await loadScope(app, first, accounts: ["a"], groups: [group("a", [workspace(), workspace("w2")])])
        try app.switchWorkspace(workspace: "w2", account: "a")
        let second = TestCoreEngine()
        let relaunched = AppStore(engineFactory: { second.attach($0); return second }, callTimeout: .seconds(5), preferences: defaults)
        try await waitUntil { relaunched.isReady && self.id(second, topic: "accounts") != .null }
        // The empty first answer must not spend the restore; memberships have not arrived yet.
        XCTAssertNil(relaunched.selectedWorkspaceID)
        second.emit(.object(["id": id(second, topic: "accounts"), "value": .array([account("a")])]))
        try await waitUntil { relaunched.selectedWorkspaceID == "w2" }
        XCTAssertEqual(relaunched.selectedAccountID, "a")
        // Confirmed removal forgets it; with several left, the chooser decides.
        try await updateGroups(relaunched, second, [group("a", [workspace(), workspace("w3")])])
        XCTAssertNil(relaunched.selectedWorkspaceID)
        XCTAssertNil(defaults.dictionary(forKey: AppStore.rememberedScopeKey))
    }
    func testFirstLaunchWithOneWorkspaceSkipsTheChooser() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "fail.still.tests.\(UUID().uuidString)"))
        let engine = TestCoreEngine()
        let app = AppStore(engineFactory: { engine.attach($0); return engine }, callTimeout: .seconds(5), preferences: defaults)
        try await loadScope(app, engine, accounts: ["a"], groups: [group("a", [workspace()])])
        try await waitUntil { app.selectedWorkspaceID == "w" }
        XCTAssertEqual(app.selectedAccountID, "a")
    }
    func testSharedWorkspaceRejectsAccountIdentityMismatchWithoutSwitching() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        // Group order deliberately differs from sign-in order.
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("b", [workspace()]), group("a", [workspace()])])
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        XCTAssertThrowsError(try app.switchWorkspace(workspace: "w", account: "b")) { error in
            XCTAssertEqual((error as? CoreFailure)?.code, "scope_identity_mismatch")
            XCTAssertTrue((error as? CoreFailure)?.message.contains("最先登录") == true)
        }
        XCTAssertEqual(app.selectedAccountID, "a"); XCTAssertEqual(app.selectedWorkspaceID, "w")
        XCTAssertEqual(app.scopeEpoch, epoch); XCTAssertEqual(topic.value, .string("private"))
        XCTAssertFalse(engine.sent().contains { $0["call"].stringValue == "workspace.switch" || $0["call"].stringValue == "account.switch" })
    }
    func testSwitchAccountLeavesSharedWorkspaceUnselectedAndAllowsExplicitValidWorkspace() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("a", [workspace()]), group("b", [workspace(), workspace("b-only")])])
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine)
        try app.switchAccount(account: "b")
        XCTAssertEqual(app.selectedAccountID, "b"); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertNil(topic.value)
        try app.switchWorkspace(workspace: "b-only", account: "b")
        XCTAssertEqual(app.selectedAccountID, "b"); XCTAssertEqual(app.selectedWorkspaceID, "b-only")
    }
    func testSelectedBMembershipRemovalClearsScopeEvenWhenARetainsWorkspace() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("a", []), group("b", [workspace()])])
        try app.switchWorkspace(workspace: "w", account: "b")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        let request = id(engine, topic: "workspace")
        try await updateGroups(app, engine, [group("a", [workspace()]), group("b", [])])
        XCTAssertEqual(app.selectedAccountID, "b"); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertGreaterThan(app.scopeEpoch, epoch); XCTAssertNil(topic.value)
        try await waitUntil { engine.sent().contains { $0["id"] == request && $0["unsubscribe"].boolValue == true } }
    }
    func testKeptMembershipTransientFailureRetainsScopeAndBlocksWrongIdentity() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("a", [workspace()]), group("b", [workspace()])])
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        let offline = JSONValue.object(["code": .string("offline")])
        engine.emit(.object(["id": id(engine, topic: "workspaces"), "error": offline]))
        // FIFO bridge processing: the focus reply is a barrier after the topic error.
        _ = try await app.call("client.focus")
        XCTAssertEqual(app.selectedWorkspaceID, "w"); XCTAssertEqual(app.scopeEpoch, epoch)
        XCTAssertEqual(topic.value, .string("private"))
        try await updateGroups(app, engine, [group("a", [workspace()], loaded: false, error: offline), group("b", [workspace()])])
        XCTAssertEqual(app.selectedWorkspaceID, "w"); XCTAssertEqual(app.scopeEpoch, epoch)
        XCTAssertEqual(topic.value, .string("private"))
        // The failed A refresh still supplies the kept owner; B cannot impersonate it.
        XCTAssertThrowsError(try app.switchWorkspace(workspace: "w", account: "b")) { error in
            XCTAssertEqual((error as? CoreFailure)?.code, "scope_identity_mismatch")
        }
        XCTAssertThrowsError(try app.switchAccount(account: "a")) { error in
            XCTAssertEqual((error as? CoreFailure)?.code, "scope_unverified")
        }
        // Even an unconfirmed empty list is not evidence of membership removal.
        try await updateGroups(app, engine, [group("a", [], loaded: false, error: offline), group("b", [])])
        XCTAssertEqual(app.selectedAccountID, "a"); XCTAssertEqual(app.selectedWorkspaceID, "w")
        XCTAssertEqual(app.scopeEpoch, epoch); XCTAssertEqual(topic.value, .string("private"))
        try await updateGroups(app, engine, [group("a", [workspace()]), group("b", [workspace()])])
        XCTAssertEqual(app.scopeEpoch, epoch)
    }
    func testEffectiveIdentityChangeClearsScopeWithoutRelabelingSelectedAccount() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("a", []), group("b", [workspace()])])
        try app.switchWorkspace(workspace: "w", account: "b")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        // Both retain membership, but A now wins the core's first-owner resolution.
        try await updateGroups(app, engine, [group("a", [workspace()], loaded: false), group("b", [workspace()])])
        XCTAssertEqual(app.selectedAccountID, "b"); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertGreaterThan(app.scopeEpoch, epoch); XCTAssertNil(topic.value)
    }
    func testAccountsSignInOrderChangeClearsEffectiveIdentityScope() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        let groups = [group("b", [workspace()]), group("a", [workspace()])]
        try await loadScope(app, engine, accounts: ["a", "b"], groups: groups)
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine)
        try await loadScope(app, engine, accounts: ["b", "a"], groups: groups)
        XCTAssertEqual(app.selectedAccountID, "a"); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertNil(topic.value)
    }
    func testConfirmedPermissionChangeClearsScopeAndCancelsInflightCall() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a"], groups: [group("a", [workspace()])])
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        try await updateGroups(app, engine, [group("a", [workspace(name: "Renamed")])])
        XCTAssertEqual(app.scopeEpoch, epoch); XCTAssertEqual(topic.value, .string("private"))
        // Unconfirmed permission changes do not replace the verified role baseline.
        try await updateGroups(app, engine, [group("a", [workspace(role: "member")], loaded: false, error: .object(["code": .string("offline")]))])
        XCTAssertEqual(app.scopeEpoch, epoch)
        let writing = Task { try await app.call("station.send", params: ["station": .string("w/s")]) }
        try await waitUntil { engine.sent().contains { $0["call"].stringValue == "station.send" } }
        try await updateGroups(app, engine, [group("a", [workspace(role: "member")])])
        XCTAssertEqual(app.selectedAccountID, "a"); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertGreaterThan(app.scopeEpoch, epoch); XCTAssertNil(topic.value)
        do { _ = try await writing.value; XCTFail("Expected permission scope invalidation") }
        catch let failure as CoreFailure { XCTAssertEqual(failure.code, "scope_changed") }
    }
    func testFailedMembershipValidationPreservesPreviousScope() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await loadScope(app, engine, accounts: ["a", "b"], groups: [group("a", [workspace()]), group("b", [], loaded: false)])
        try app.switchWorkspace(workspace: "w", account: "a")
        let topic = try await privateTopic(app, engine); let epoch = app.scopeEpoch
        XCTAssertThrowsError(try app.switchAccount(account: "b"))
        XCTAssertThrowsError(try app.switchWorkspace(workspace: "w", account: "b"))
        XCTAssertEqual(app.selectedAccountID, "a"); XCTAssertEqual(app.selectedWorkspaceID, "w")
        XCTAssertEqual(app.scopeEpoch, epoch); XCTAssertEqual(topic.value, .string("private"))
    }
    func testOrderedLiveDeltasAndCancellationCleanup() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await waitUntil { app.isReady }
        let topic = app.subscribe("live", params: ["station": .string("w/s"), "key": .string("k")])
        try await waitUntil { self.id(engine, topic: "live") != .null }
        let request = id(engine, topic: "live")
        engine.emit(.object(["id": request, "value": .array([.number(1)])]))
        for i in 2...30 {
            engine.emit(.object(["id": request, "delta": .array([.object(["path": .array([]), "append": .array([.number(Double(i))])])])]))
        }
        try await waitUntil { topic.value?.arrayValue.count == 30 }
        XCTAssertEqual(topic.value?.arrayValue.last, .number(30))
        topic.cancel()
        XCTAssertNil(topic.value); XCTAssertFalse(topic.isLoading)
        engine.emit(.object(["id": request, "value": .string("late")]))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(topic.value)
    }
    func testScopeChangesClearOldValuesAndPreventLateResults() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await waitUntil { app.isReady }
        app.selectedAccountID = "a"; app.selectedWorkspaceID = "w"
        let epoch = app.scopeEpoch
        let topic = app.subscribe("workspace", params: ["workspace": .string("w")])
        try await waitUntil { self.id(engine, topic: "workspace") != .null }
        engine.emit(.object(["id": id(engine, topic: "workspace"), "value": .string("private")]))
        try await waitUntil { topic.value != nil }
        let writing = Task { try await app.call("station.send", params: ["station": .string("w/s")]) }
        try await waitUntil { engine.sent().contains(where: { $0["call"].stringValue == "station.send" }) }
        app.selectedAccountID = "b"
        XCTAssertGreaterThan(app.scopeEpoch, epoch); XCTAssertNil(app.selectedWorkspaceID)
        XCTAssertNil(topic.value)
        do { _ = try await writing.value; XCTFail("Expected scope uncertainty") }
        catch let failure as CoreFailure { XCTAssertEqual(failure.code, "scope_changed"); XCTAssertTrue(failure.outcomeUncertain) }
        app.selectedWorkspaceID = "new"
        XCTAssertGreaterThan(app.scopeEpoch, epoch + 1)
    }
    func testNormalNullReplyAndTimeoutDoesNotRerunWrite() async throws {
        let engine = TestCoreEngine(); let app = store(engine, timeout: .milliseconds(80))
        try await waitUntil { app.isReady }
        let normal = Task { try await app.call("auth.signOut", params: ["account": .string("a")]) }
        try await waitUntil { engine.sent().contains(where: { $0["call"].stringValue == "auth.signOut" }) }
        let request = engine.sent().last(where: { $0["call"].stringValue == "auth.signOut" })!["id"]
        engine.emit(.object(["id": request, "ok": .null]))
        let answer = try await normal.value
        XCTAssertEqual(answer, .null)
        do { _ = try await app.call("station.send"); XCTFail("Expected timeout") }
        catch let failure as CoreFailure { XCTAssertEqual(failure.code, "timeout_uncertain"); XCTAssertTrue(failure.outcomeUncertain) }
        XCTAssertEqual(engine.sent().filter { $0["call"].stringValue == "station.send" }.count, 1)
    }
    func testFatalRejectsInflightAndReplaysOnlySubscriptions() async throws {
        let engine = TestCoreEngine(); let app = store(engine)
        try await waitUntil { app.isReady }
        let writing = Task { try await app.call("station.send") }
        try await waitUntil { engine.sent().contains(where: { $0["call"].stringValue == "station.send" }) }
        engine.emit(.object(["fatal": .string("must never surface raw token")]))
        do { _ = try await writing.value; XCTFail("Expected uncertainty") }
        catch let failure as CoreFailure { XCTAssertEqual(failure.code, "core_restarted") }
        XCTAssertFalse(app.fatalMessage?.contains("token") ?? false)
        try await waitUntil { engine.connectionCount() == 2 && app.isReady }
        XCTAssertEqual(engine.sent().filter { $0["call"].stringValue == "station.send" }.count, 1)
        XCTAssertEqual(engine.sent().filter { $0["subscribe"]["topic"].stringValue == "accounts" }.count, 2)
    }
}
