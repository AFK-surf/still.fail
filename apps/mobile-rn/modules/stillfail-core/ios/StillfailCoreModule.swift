import ExpoModulesCore
import os

/// The core's engine for the UI in JavaScript (as the Android module, StillfailCoreModule.kt): one per process (its
/// files are the app's, one SQLite open at a time), kept across the UI's reloads; each module (each JavaScript
/// runtime) is a client of its own, and what the core says goes to the module started last.
public final class StillfailCoreModule: Module {
  public func definition() -> ModuleDefinition {
    Name("StillfailCore")
    Events("message")

    Function("start") { (cloudOrigin: String, beta: Bool) in
      try CoreProcess.shared.start(for: self, cloudOrigin: cloudOrigin, beta: beta)
    }

    Function("post") { (json: String) in
      try CoreProcess.shared.post(json)
    }

    Function("stop") {
      CoreProcess.shared.stop()
    }

    OnDestroy {
      CoreProcess.shared.forget(self)
    }
  }

  fileprivate func said(_ json: String, _ bytes: Data?) {
    if let bytes {
      sendEvent("message", ["json": json, "bytes": bytes.base64EncodedString()])
    } else {
      sendEvent("message", ["json": json])
    }
  }
}

struct CoreNotStarted: Error, CustomStringConvertible {
  var description: String { "the core is not started" }
}

struct CoreScriptMissing: Error, CustomStringConvertible {
  var description: String { "the core's script (StillfailCore.bundle/core.hbc) is not in the app" }
}

/// The process's engine, and who hears it.
private final class CoreProcess {
  static let shared = CoreProcess()

  /// The core's script as the app carries it (scripts/core-ios.sh: client/core-ts as Hermes bytecode).
  private static let script = "core.hbc"

  /// What the UI tells the core and what the core says, at the debug level (kept only while someone streams it:
  /// `log stream --level debug --predicate 'subsystem == "fail.still.core"'`).
  private let told = Logger(subsystem: "fail.still.core", category: "told")
  private let said = Logger(subsystem: "fail.still.core", category: "said")

  private let lock = NSLock()
  private var running: SFCoreEngine?
  private weak var listener: StillfailCoreModule?
  private var client: Int64 = 0

  func start(for module: StillfailCoreModule, cloudOrigin: String, beta: Bool) throws {
    lock.lock()
    defer { lock.unlock() }
    listener = module
    let engine = try running ?? begin(cloudOrigin: cloudOrigin, beta: beta)
    running = engine
    client = engine.connect()
  }

  func post(_ json: String) throws {
    lock.lock()
    let engine = running
    let to = client
    lock.unlock()
    guard let engine else { throw CoreNotStarted() }
    told.debug("\(String(json.prefix(300)), privacy: .public)")
    engine.receive(to, json: json)
  }

  func stop() {
    lock.lock()
    let engine = running
    running = nil
    lock.unlock()
    engine?.close()
  }

  func forget(_ module: StillfailCoreModule) {
    lock.lock()
    if listener === module { listener = nil }
    lock.unlock()
  }


  private func heard(_ json: String, _ bytes: Data?) {
    said.debug("\(String(json.prefix(300)), privacy: .public)")
    lock.lock()
    let module = listener
    lock.unlock()
    module?.said(json, bytes)
  }

  private func begin(cloudOrigin: String, beta: Bool) throws -> SFCoreEngine {
    guard let bundle = Bundle.main.url(forResource: "StillfailCore", withExtension: "bundle").flatMap(Bundle.init(url:)),
          let path = bundle.path(forResource: "core", ofType: "hbc"),
          let script = FileManager.default.contents(atPath: path)
    else { throw CoreScriptMissing() }
    return SFCoreEngine(
      script: script, url: Self.script, dataDir: try dataDir(), cloudOrigin: cloudOrigin, beta: beta,
      said: { [weak self] json, bytes in self?.heard(json, bytes) },
      secure: { engine, id, op, json, bytes in
        // Off the engine's thread (a prompt waits on the person); the answer is dropped once the engine is closed.
        SecureStore.shared.answer(op: op, json: json, bytes: bytes) { result in
          switch result {
          case .success(let (head, body)): engine.complete(id, json: head, error: nil, bytes: body)
          case .failure(let e): engine.complete(id, json: nil, error: e.code, bytes: nil)
          }
        }
      })
  }

  /// The core's files: the app's Application Support/stillfail-core, never backed up (the Android app allows no backup).
  private func dataDir() throws -> String {
    var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("stillfail-core", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try dir.setResourceValues(values)
    return dir.path
  }
}
