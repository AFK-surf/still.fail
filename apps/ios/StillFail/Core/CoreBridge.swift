import Foundation

protocol CoreEngine: AnyObject, Sendable {
    func connect() -> UInt64
    func receive(client: UInt64, json: String)
    func disconnect(client: UInt64)
}
typealias CoreEngineFactory = @Sendable (@escaping @Sendable (UInt64, String) -> Void) throws -> any CoreEngine

private final class NativeListener: CoreListener, @unchecked Sendable {
    let callback: @Sendable (UInt64, String) -> Void
    init(_ callback: @escaping @Sendable (UInt64, String) -> Void) { self.callback = callback }
    func onMessage(client: UInt64, json: String) { callback(client, json) }
}

/// The wrapper is confined to CoreBridge.worker. No FFI copying on the UI actor.
private final class NativeCoreEngine: CoreEngine, @unchecked Sendable {
    private let core: StillFailCoreFfi
    init(callback: @escaping @Sendable (UInt64, String) -> Void) throws {
        let storage = KeychainStorage()
        let directory = try storage.prepareDirectory()
        core = try startSecure(dataDir: directory.path, cloudOrigin: "https://app.still.fail",
                               beta: false, listener: NativeListener(callback), storage: storage)
    }
    func connect() -> UInt64 { core.connect() }
    func receive(client: UInt64, json: String) { core.receive(client: client, json: json) }
    func disconnect(client: UInt64) { core.disconnect(client: client) }
}

enum CoreEvent: Sendable {
    case started
    case topic(UInt64, CoreTopicState)
    case reply(UInt64, Result<JSONValue, CoreFailure>)
    case fatal(CoreFailure)
}

/// All mutable bridge state, JSON encode/decode and deltas are serial-worker
/// confined. FIFO dispatch to main applies whole states, never payload work.
final class CoreBridge: @unchecked Sendable {
    private let worker = DispatchQueue(label: "fail.still.iphone.core-json", qos: .userInitiated)
    private let factory: CoreEngineFactory
    private let onEvent: @MainActor @Sendable (CoreEvent) -> Void
    private var engine: (any CoreEngine)?
    private var client: UInt64 = 0
    private var generation = 0
    private var failures = 0
    private var subscriptions: [UInt64: (spec: JSONValue, state: CoreTopicState)] = [:]
    private var calls: Set<UInt64> = []
    private var stopped = false

    init(factory: @escaping CoreEngineFactory = { try NativeCoreEngine(callback: $0) },
         onEvent: @escaping @MainActor @Sendable (CoreEvent) -> Void) {
        self.factory = factory; self.onEvent = onEvent
    }
    func start() { worker.async { self.open() } }
    func stop() {
        worker.async {
            self.stopped = true; self.generation += 1
            self.engine?.disconnect(client: self.client); self.engine = nil
            self.calls.removeAll(); self.subscriptions.removeAll()
        }
    }
    func subscribe(id: UInt64, spec: JSONValue) {
        worker.async {
            self.subscriptions[id] = (spec, CoreTopicState())
            self.post(.object(["id": .number(Double(id)), "subscribe": spec]))
        }
    }
    func unsubscribe(id: UInt64) {
        worker.async {
            self.subscriptions.removeValue(forKey: id)
            self.post(.object(["id": .number(Double(id)), "unsubscribe": .bool(true)]))
        }
    }
    func call(id: UInt64, name: String, params: [String: JSONValue]) {
        worker.async {
            guard self.engine != nil else {
                self.emit(.reply(id, .failure(CoreFailure(code: "not_ready")))); return
            }
            self.calls.insert(id)
            self.post(.object(["id": .number(Double(id)), "call": .string(name), "params": .object(params)]))
        }
    }
    func cancelCall(id: UInt64) {
        worker.async {
            self.calls.remove(id)
            self.post(.object(["id": .number(Double(id)), "cancel": .bool(true)]))
        }
    }
    private func open() {
        guard !stopped, engine == nil else { return }
        generation += 1
        let epoch = generation
        do {
            let next = try factory { [weak self] client, json in
                guard let self else { return }
                self.worker.async { self.receive(client: client, json: json, generation: epoch) }
            }
            engine = next; client = next.connect()
            emit(.started)
            for (id, sub) in subscriptions {
                post(.object(["id": .number(Double(id)), "subscribe": sub.spec]))
            }
        } catch {
            fail(CoreFailure(code: "secure_storage"))
        }
    }
    private func post(_ message: JSONValue) {
        guard let engine else { return }
        do { engine.receive(client: client, json: try message.encoded()) }
        catch { fail(CoreFailure(code: "core_restarted")) }
    }
    private func receive(client: UInt64, json: String, generation: Int) {
        guard generation == self.generation, client == self.client, engine != nil else { return }
        let message: JSONValue
        do { message = try JSONValue.parse(json) }
        catch { fail(CoreFailure(code: "core_restarted")); return }
        if message.objectValue["fatal"] != nil { fail(CoreFailure(code: "core_restarted")); return }
        failures = 0
        guard let number = message["id"].intValue, number > 0 else { return }
        let id = UInt64(number)
        if calls.contains(id) {
            // Progress is not a terminal answer. Calls never retry automatically.
            if let body = message.objectValue["error"] {
                calls.remove(id); emit(.reply(id, .failure(CoreFailure(body: body))))
            } else if let ok = message.objectValue["ok"] {
                calls.remove(id); emit(.reply(id, .success(ok)))
            }
            return
        }
        guard var sub = subscriptions[id] else { return }
        sub.state.receive(message)
        subscriptions[id] = sub
        emit(.topic(id, sub.state))
    }
    private func fail(_ error: CoreFailure) {
        generation += 1
        engine?.disconnect(client: client); engine = nil; calls.removeAll()
        for id in Array(subscriptions.keys) { subscriptions[id]?.state = CoreTopicState() }
        emit(.fatal(error))
        let delays: [Double] = [0.5, 1, 2, 5, 10, 30]
        let delay = delays[min(failures, delays.count - 1)]; failures += 1
        let epoch = generation
        worker.asyncAfter(deadline: .now() + delay) {
            guard epoch == self.generation else { return }; self.open()
        }
    }
    private func emit(_ event: CoreEvent) {
        let callback = onEvent
        DispatchQueue.main.async { MainActor.assumeIsolated { callback(event) } }
    }
}
