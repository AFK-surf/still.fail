import Foundation
import JavaScriptCore
import Security
import Darwin

protocol CoreSecureStorage: Sendable {
    func get(key: String) throws -> Data?
    func set(key: String, value: Data) throws
    func delete(key: String) throws
}
extension KeychainStorage: CoreSecureStorage {}

/// Shell work may finish after stop. Opaque, never reused IDs avoid dereferencing
/// freed Swift objects; removing an engine also drops all late answers.
private enum ShellCallbacks {
    private final class WeakEngine {
        weak var value: NativeCoreEngine?
        init(_ value: NativeCoreEngine) { self.value = value }
    }
    static let lock = NSLock()
    private static var next: UInt = 1
    private static var engines: [UInt: WeakEngine] = [:]
    static func add(_ engine: NativeCoreEngine) -> UInt {
        lock.lock(); defer { lock.unlock() }
        let id = next; next += 1; engines[id] = WeakEngine(engine); return id
    }
    static func get(_ id: UInt) -> NativeCoreEngine? {
        lock.lock(); defer { lock.unlock() }; return engines[id]?.value
    }
    static func remove(_ id: UInt) {
        lock.lock(); defer { lock.unlock() }; engines.removeValue(forKey: id)
    }
}

private let shellCompleted: sf_complete = { opaque, id, json, jsonLength, error, errorLength, bytes, bytesLength, hasBytes in
    guard let opaque, let engine = ShellCallbacks.get(UInt(bitPattern: opaque)) else { return }
    let text: (UnsafePointer<UInt8>?, Int) -> String = { p, n in
        guard let p, n > 0 else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
    }
    let data = hasBytes == 0 ? nil : bytes.map { Data(bytes: $0, count: bytesLength) } ?? Data()
    engine.complete(id: id, json: text(json, jsonLength), error: errorLength == 0 ? nil : text(error, errorLength), bytes: data)
}

/// JS, JSON, storage and timers all run on one serial queue, away from the UI.
final class NativeCoreEngine: CoreEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "fail.still.iphone.javascript", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let callback: @Sendable (UInt64, String) -> Void
    private let storage: any CoreSecureStorage
    private var context: JSContext?
    private var shell: UnsafeMutableRawPointer?
    private var callbackID: UInt = 0
    private var timers: [UInt64: DispatchSourceTimer] = [:]
    private var clients: Set<UInt64> = []
    private var failed = false

    init(dataDirectory: URL? = nil, storage: any CoreSecureStorage = KeychainStorage(), cloudOrigin: String = "https://app.still.fail",
         callback: @escaping @Sendable (UInt64, String) -> Void) throws {
        self.callback = callback; self.storage = storage
        let directory = try dataDirectory ?? (storage as? KeychainStorage)?.prepareDirectory()
        guard let directory, let scriptURL = Bundle.main.url(forResource: "stillfail-core", withExtension: "js") else {
            throw CoreFailure(code: "core_unavailable")
        }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        queue.setSpecific(key: queueKey, value: true)
        callbackID = ShellCallbacks.add(self)
        do {
            try queue.sync {
                shell = directory.path.withCString { sf_shell_start($0, shellCompleted, UnsafeMutableRawPointer(bitPattern: callbackID)) }
                guard shell != nil, let ctx = JSContext() else { throw CoreFailure(code: "core_unavailable") }
                context = ctx
                ctx.name = "still.fail TypeScript core"
                ctx.exceptionHandler = { [weak self] _, _ in self?.fatal("javascript_exception") }
                installNative(in: ctx)
                ctx.evaluateScript(script, withSourceURL: scriptURL)
                guard !failed else { throw CoreFailure(code: "core_unavailable") }
                ctx.objectForKeyedSubscript("__stillfail")?.invokeMethod("start", withArguments: [cloudOrigin, false])
            }
        } catch {
            ShellCallbacks.remove(callbackID)
            queue.sync {
                timers.values.forEach { $0.cancel() }; timers.removeAll()
                context = nil
                if let shell { sf_shell_stop(shell); self.shell = nil }
            }
            throw error
        }
    }

    deinit {
        ShellCallbacks.remove(callbackID)
        let cleanup = {
            self.timers.values.forEach { $0.cancel() }; self.timers.removeAll()
            self.context = nil
            if let shell = self.shell { sf_shell_stop(shell); self.shell = nil }
        }
        if DispatchQueue.getSpecific(key: queueKey) == true { cleanup() } else { queue.sync(execute: cleanup) }
    }

    func connect() -> UInt64 {
        queue.sync {
            let client = UInt64(context?.objectForKeyedSubscript("__stillfail")?.invokeMethod("connect", withArguments: [])?.toDouble() ?? 0)
            clients.insert(client); return client
        }
    }
    func receive(client: UInt64, json: String) {
        queue.async { [weak self] in
            guard let self, !failed else { return }
            context?.objectForKeyedSubscript("__stillfail")?.invokeMethod("receive", withArguments: [client, json])
        }
    }
    func disconnect(client: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            context?.objectForKeyedSubscript("__stillfail")?.invokeMethod("disconnect", withArguments: [client])
            clients.remove(client)
        }
    }
    fileprivate func complete(id: UInt64, json: String, error: String?, bytes: Data?) {
        queue.async { [weak self] in
            guard let self, !failed else { return }
            context?.objectForKeyedSubscript("__stillfail")?.invokeMethod("complete", withArguments:
                [id, json, error as Any? ?? NSNull(), bytes.map { Array($0) } as Any? ?? NSNull()])
        }
    }
    private func fatal(_ reason: String) {
        guard !failed else { return }; failed = true
        timers.values.forEach { $0.cancel() }; timers.removeAll()
        let json = String(data: try! JSONSerialization.data(withJSONObject: ["fatal": reason]), encoding: .utf8)!
        for client in clients.isEmpty ? Set([UInt64(1)]) : clients { callback(client, json) }
    }

    private func call(id: UInt64, op: String, json: String, bytes: Data?) {
        guard !failed else { return }
        if op.hasPrefix("storage.") {
            do {
                let args = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
                guard let key = args?["key"] as? String else { throw SecureStorageError.unavailable }
                switch op {
                case "storage.get":
                    let value = try storage.get(key: key)
                    complete(id: id, json: value == nil ? "{\"none\":true}" : "{}", error: nil, bytes: value)
                case "storage.set":
                    try storage.set(key: key, value: bytes ?? Data())
                    complete(id: id, json: "{}", error: nil, bytes: nil)
                case "storage.delete":
                    try storage.delete(key: key)
                    complete(id: id, json: "{}", error: nil, bytes: nil)
                default: throw SecureStorageError.unavailable
                }
            } catch { fatal("secure_storage") }
            return
        }
        guard let shell else { return }
        let jsonBytes = Array(json.utf8), body = Array(bytes ?? Data())
        op.withCString { name in
            jsonBytes.withUnsafeBufferPointer { j in
                body.withUnsafeBufferPointer { b in
                    sf_shell_call(shell, id, name, j.baseAddress, j.count, b.baseAddress, b.count, bytes == nil ? 0 : 1)
                }
            }
        }
    }

    private func callSync(op: String, json: String) -> String {
        guard let shell, !failed else { return "{\"error\":\"core_unavailable\"}" }
        var length = 0
        let jsonBytes = Array(json.utf8)
        let result = op.withCString { name in
            jsonBytes.withUnsafeBufferPointer { sf_shell_call_sync(shell, name, $0.baseAddress, $0.count, &length) }
        }
        guard let result else { return "{\"error\":\"core_unavailable\"}" }
        defer { sf_free(result, length) }
        return String(decoding: UnsafeBufferPointer(start: result, count: length), as: UTF8.self)
    }

    private func installNative(in ctx: JSContext) {
        let native = JSValue(newObjectIn: ctx)!
        let call: @convention(block) (Double, String, String, JSValue) -> Void = { [weak self] id, op, json, bytes in
            let body = bytes.isNull || bytes.isUndefined ? nil : Data((bytes.toArray() as? [NSNumber] ?? []).map { $0.uint8Value })
            self?.call(id: UInt64(id), op: op, json: json, bytes: body)
        }
        let sync: @convention(block) (String, String) -> String = { [weak self] op, json in self?.callSync(op: op, json: json) ?? "{\"error\":\"core_unavailable\"}" }
        let emit: @convention(block) (Double, String) -> Void = { [weak self] client, json in self?.callback(UInt64(client), json) }
        let fatal: @convention(block) (String) -> Void = { [weak self] reason in self?.fatal(reason) }
        let now: @convention(block) () -> Double = { Date().timeIntervalSince1970 * 1000 }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let milliseconds = Double(timebase.numer) / Double(timebase.denom) / 1_000_000
        // Like Android's BOOTTIME, deadlines continue while the phone sleeps.
        let monotonic: @convention(block) () -> Double = { Double(mach_continuous_time()) * milliseconds }
        let utcOffset: @convention(block) (Double) -> Double = { Double(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: $0 / 1000))) / 60 }
        let random: @convention(block) (Int) -> [NSNumber] = { [weak self] count in
            guard count >= 0, count <= 65536 else { self?.fatal("random_failed"); return [] }
            if count == 0 { return [] }
            var bytes = [UInt8](repeating: 0, count: count)
            let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
            guard status == errSecSuccess else { self?.fatal("random_failed"); return [] }
            return bytes.map { NSNumber(value: $0) }
        }
        let setTimer: @convention(block) (Double, Double) -> Void = { [weak self] id, ms in
            guard let self, !failed else { return }
            let key = UInt64(id)
            timers.removeValue(forKey: key)?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(wallDeadline: .now() + max(0, ms) / 1000)
            timer.setEventHandler { [weak self] in
                guard let self, !failed else { return }
                timers.removeValue(forKey: key)?.cancel()
                context?.objectForKeyedSubscript("__stillfail_timer")?.call(withArguments: [key])
            }
            timers[key] = timer; timer.resume()
        }
        let clearTimer: @convention(block) (Double) -> Void = { [weak self] id in self?.timers.removeValue(forKey: UInt64(id))?.cancel() }
        // Core errors are returned through the protocol; console data may contain credentials.
        let log: @convention(block) (Int, String) -> Void = { _, _ in }
        for (key, value) in ["call": call as Any, "callSync": sync, "emit": emit, "fatal": fatal,
                             "now": now, "monotonic": monotonic, "utcOffset": utcOffset,
                             "random": random, "setTimer": setTimer, "clearTimer": clearTimer, "log": log] {
            native.setObject(value, forKeyedSubscript: key as NSString)
        }
        ctx.setObject(native, forKeyedSubscript: "__native" as NSString)
    }
}
