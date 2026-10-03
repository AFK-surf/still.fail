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
    /// A topic's latest state; `valueChanged` when its value differs from the last one delivered.
    case topic(UInt64, CoreTopicState, valueChanged: Bool)
    case reply(UInt64, Result<JSONValue, CoreFailure>)
    case fatal(CoreFailure)
}

/// All mutable bridge state, JSON encode/decode and deltas are serial-worker
/// confined. FIFO dispatch to main applies whole states, never payload work.
/// Topic states that did not change are dropped, and a burst of states (a stream
/// of tokens) reaches main as its latest state at most `topicInterval` apart.
/// Replies and failures first deliver the topic states queued before them.
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
    private var queuedTopics: [UInt64: (state: CoreTopicState, changed: Bool)] = [:]
    private var queuedOrder: [UInt64] = []
    private var flushScheduled = false
    private var lastFlush = DispatchTime(uptimeNanoseconds: 0)
    static let topicInterval: TimeInterval = 1.0 / 24

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
            self.queuedTopics.removeAll(); self.queuedOrder.removeAll()
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
            self.queuedTopics.removeValue(forKey: id); self.queuedOrder.removeAll { $0 == id }
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
        let before = sub.state
        sub.state.receive(message)
        subscriptions[id] = sub
        let changed = before.value != sub.state.value
        guard changed || before.error != sub.state.error || before.isLoading != sub.state.isLoading else { return }
        queueTopic(id, sub.state, changed: changed)
    }
    private func fail(_ error: CoreFailure) {
        generation += 1
        engine?.disconnect(client: client); engine = nil; calls.removeAll()
        queuedTopics.removeAll(); queuedOrder.removeAll()
        for id in Array(subscriptions.keys) { subscriptions[id]?.state = CoreTopicState() }
        emit(.fatal(error))
        let delays: [Double] = [0.5, 1, 2, 5, 10, 30]
        let delay = delays[min(failures, delays.count - 1)]; failures += 1
        let epoch = generation
        worker.asyncAfter(deadline: .now() + delay) {
            guard epoch == self.generation else { return }; self.open()
        }
    }
    private func queueTopic(_ id: UInt64, _ state: CoreTopicState, changed: Bool) {
        if let queued = queuedTopics[id] { queuedTopics[id] = (state, queued.changed || changed) }
        else { queuedTopics[id] = (state, changed); queuedOrder.append(id) }
        guard !flushScheduled else { return }
        flushScheduled = true
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- lastFlush.uptimeNanoseconds) / 1e9
        worker.asyncAfter(deadline: .now() + max(0, Self.topicInterval - elapsed)) { self.flushTopics() }
    }
    private func takeQueuedTopics() -> [CoreEvent] {
        flushScheduled = false
        guard !queuedOrder.isEmpty else { return [] }
        lastFlush = .now()
        let events = queuedOrder.compactMap { id in queuedTopics[id].map { CoreEvent.topic(id, $0.state, valueChanged: $0.changed) } }
        queuedTopics.removeAll(keepingCapacity: true); queuedOrder.removeAll(keepingCapacity: true)
        return events
    }
    private func flushTopics() { deliver(takeQueuedTopics()) }
    private func emit(_ event: CoreEvent) { deliver(takeQueuedTopics() + [event]) }
    private func deliver(_ events: [CoreEvent]) {
        guard !events.isEmpty else { return }
        let callback = onEvent
        DispatchQueue.main.async { MainActor.assumeIsolated { events.forEach(callback) } }
    }
}
