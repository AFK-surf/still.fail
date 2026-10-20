import XCTest
import Network
@testable import StillFail

private final class MemoryCoreStorage: CoreSecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    var unavailable = false
    func get(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if unavailable { throw SecureStorageError.unavailable }; return values[key]
    }
    func set(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if unavailable { throw SecureStorageError.unavailable }; values[key] = value
    }
    func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if unavailable { throw SecureStorageError.unavailable }; values.removeValue(forKey: key)
    }
}

final class NativeCoreEngineTests: XCTestCase {
    func testSignedInCoreReadsCurrentWorkspacesThroughNativeHTTP() throws {
        let server = try CloudFixture()
        defer { server.stop() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MemoryCoreStorage()
        try storage.set(key: "accounts", value: Data(#"[{"sub":"fixture","email":"fixture@example.test","name":"Fixture","picture":"","access":"test-access","refresh":"test-refresh","access_expires":4102444800}]"#.utf8))
        let loaded = expectation(description: "current cloud workspaces replace the initial view")
        let capture = LoadedWorkspaceCapture()
        let engine = try NativeCoreEngine(dataDirectory: directory, storage: storage, cloudOrigin: server.origin) { _, json in
            guard let message = try? JSONValue.parse(json) else { return }
            XCTAssertEqual(message["fatal"], .null)
            guard message["id"].intValue == 30 else { return }
            guard let group = capture.receive(message) else { return }
            XCTAssertEqual(group["workspaces"].arrayValue.first?["name"].stringValue, "Current workspace")
            loaded.fulfill()
        }
        let client = engine.connect()
        engine.receive(client: client, json: #"{"id":30,"subscribe":{"topic":"workspaces"}}"#)
        wait(for: [loaded], timeout: 15)
        engine.disconnect(client: client)
    }

    func testSharedTypeScriptCoreStartsAndDispatchesCallsInJavaScriptCore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = expectation(description: "accounts from real TS core")
        let reply = expectation(description: "prefs call through real TS core")
        let invalid = expectation(description: "unknown call is rejected")
        let engine = try NativeCoreEngine(dataDirectory: directory, storage: MemoryCoreStorage()) { _, json in
            guard let value = try? JSONValue.parse(json) else { return }
            XCTAssertEqual(value["fatal"], .null)
            switch value["id"].intValue {
            case 10: if value.objectValue["value"] != nil { XCTAssertEqual(value["value"], .array([])); accounts.fulfill() }
            case 11: if value.objectValue["ok"] != nil { reply.fulfill() }
            case 12: if value.objectValue["error"] != nil { invalid.fulfill() }
            default: break
            }
        }
        let client = engine.connect()
        XCTAssertEqual(client, 1)
        engine.receive(client: client, json: #"{"id":10,"subscribe":{"topic":"accounts"}}"#)
        engine.receive(client: client, json: #"{"id":11,"call":"prefs.set","params":{"language":"en"}}"#)
        engine.receive(client: client, json: #"{"id":12,"call":"not.a.call","params":{}}"#)
        wait(for: [accounts, reply, invalid], timeout: 10)
        engine.disconnect(client: client)
    }

    func testUnavailableSecureStorageIsFatalWithoutPlaintextFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = Data("keep-me".utf8)
        try legacy.write(to: directory.appendingPathComponent("accounts"))
        let storage = MemoryCoreStorage(); storage.unavailable = true
        let fatal = expectation(description: "secure storage stops startup")
        let engine = try NativeCoreEngine(dataDirectory: directory, storage: storage) { _, json in
            if (try? JSONValue.parse(json)["fatal"].stringValue) == "secure_storage" { fatal.fulfill() }
        }
        _ = engine.connect()
        wait(for: [fatal], timeout: 10)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("accounts")), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("device").path))
    }

    func testRestartDropsLateShellAnswers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MemoryCoreStorage()
        for _ in 0..<10 {
            var engine: NativeCoreEngine? = try NativeCoreEngine(dataDirectory: directory, storage: storage) { _, _ in }
            let client = engine!.connect()
            engine!.receive(client: client, json: #"{"id":1,"subscribe":{"topic":"prefs"}}"#)
            engine!.disconnect(client: client)
            engine = nil
        }
    }
}

private final class LoadedWorkspaceCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var state = CoreTopicState()
    private var answered = false
    func receive(_ message: JSONValue) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        state.receive(message)
        guard !answered, let group = state.value?.arrayValue.first, group["loaded"].boolValue == true else { return nil }
        answered = true; return group
    }
}

/// The real Rust HTTP bridge talks to this loopback server. No live credentials.
private final class CloudFixture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "stillfail.tests.cloud")
    private let listener: NWListener
    let origin: String
    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global())
            Self.read(connection, accumulated: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            listener.cancel(); throw CoreFailure(code: "fixture_unavailable")
        }
        origin = "http://127.0.0.1:\(port.rawValue)"
    }
    func stop() { listener.cancel() }
    private static func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { bytes, _, ended, error in
            let data = accumulated + (bytes ?? Data())
            guard let request = String(data: data, encoding: .utf8), request.contains("\r\n\r\n") else {
                if ended || error != nil { connection.cancel() }
                else { read(connection, accumulated: data) }
                return
            }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let body: String
            let status: String
            if path == "/v1/me" {
                status = "200 OK"
                body = #"{"user":{"id":"fixture"},"workspaces":[{"id":"current","name":"Current workspace","role":"owner"}],"invitations":[],"relay_urls":[]}"#
            } else if path == "/v1/workspaces/current" {
                status = "200 OK"; body = #"{"id":"current","name":"Current workspace","stations":[]}"#
            } else { status = "404 Not Found"; body = "{}" }
            let response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
