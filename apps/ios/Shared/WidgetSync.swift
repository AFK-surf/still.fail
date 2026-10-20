import Foundation

/// Runs in the widget extension, independently of the main app's lifecycle.
/// Multiple widget kinds share one in-flight read in the extension process.
actor WidgetSync {
    static let shared = WidgetSync()
    private var pending: (WidgetSelection, Task<WidgetSnapshot?, Never>)?
    private let directory: URL?
    private let factory: CoreEngineFactory
    init(directory: URL? = WidgetFiles.directory, factory: @escaping CoreEngineFactory = { callback in
        #if WIDGET_E2E
        return try WidgetE2EFactory.make(callback: callback)
        #else
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("widget-io", isDirectory: true)
        return try NativeCoreEngine(dataDirectory: data, scriptName: "stillfail-widget", storage: WidgetCredentials(), callback: callback)
        #endif
    }) {
        self.directory = directory; self.factory = factory
    }
    func update() async -> WidgetSnapshot? {
        guard let selected = WidgetFiles.selection(in: directory) else { return nil }
        if let pending, pending.0 == selected { return await pending.1.value }
        pending?.1.cancel()
        let directory = directory, factory = factory
        let task = Task<WidgetSnapshot?, Never> {
            do {
                let reading = try await WidgetReadOperation.read(selected, factory: factory)
                try Task.checkCancellation()
                let archive = WidgetProjection.count(reading["archivedAt"].arrayValue.compactMap(WidgetProjection.date))
                let snapshot = WidgetProjection.snapshot(chats: reading["chats"], archiveDays: archive,
                    workspace: selected.workspace, account: selected.account, name: reading.text("name"))
                guard try WidgetFiles.commit(snapshot, for: selected, in: directory) else { return nil }
                return snapshot
            } catch {
                // An unavailable station/Keychain never overwrites good statistics.
                guard WidgetFiles.selection(in: directory) == selected else { return nil }
                return WidgetSnapshot.load(from: directory?.appendingPathComponent(WidgetSnapshot.fileName))
            }
        }
        pending = (selected, task)
        let result = await task.value
        if pending?.0 == selected { pending = nil }
        return result
    }
}

/// One request owns a lightweight reader and its native connections. Completing,
/// cancelling or timing out releases them; no background app task is involved.
private final class WidgetReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<JSONValue, any Error>?
    private var engine: (any CoreEngine)?
    private var client: UInt64 = 0
    private var timer: Task<Void, Never>?

    static func read(_ selection: WidgetSelection, factory: @escaping CoreEngineFactory) async throws -> JSONValue {
        let operation = WidgetReadOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { operation.start(selection, factory: factory, continuation: $0) }
        } onCancel: { operation.finish(.failure(CancellationError())) }
    }
    private func start(_ selection: WidgetSelection, factory: CoreEngineFactory, continuation: CheckedContinuation<JSONValue, any Error>) {
        lock.lock()
        if finished { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        lock.unlock()
        do {
            let engine = try factory { [weak self] _, json in
                guard let self, let message = try? JSONValue.parse(json) else { return }
                if message["fatal"] != .null { self.finish(.failure(CoreFailure(code: "widget_core_failed"))) }
                else if message["id"].intValue == 1 {
                    if message.objectValue["ok"] != nil { self.finish(.success(message["ok"])) }
                    else if message.objectValue["error"] != nil { self.finish(.failure(CoreFailure(body: message["error"]))) }
                }
            }
            let client = engine.connect()
            lock.lock()
            if finished { lock.unlock(); engine.disconnect(client: client); return }
            self.engine = engine; self.client = client
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(22)) } catch { return }
                self?.finish(.failure(CoreFailure(code: "widget_timeout")))
            }
            lock.unlock()
            engine.receive(client: client, json: try JSONValue.object(["id": .number(1), "call": .string("widget.read"),
                "params": .object(["account": .string(selection.account), "workspace": .string(selection.workspace)])]).encoded())
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<JSONValue, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation, engine = engine, client = client, timer = timer
        self.continuation = nil; self.engine = nil; self.timer = nil
        lock.unlock()
        timer?.cancel(); engine?.disconnect(client: client)
        continuation?.resume(with: result)
    }
}
