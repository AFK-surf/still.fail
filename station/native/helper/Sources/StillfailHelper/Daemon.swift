// The helper's Unix socket (main.swift says its requests): listened on as Cue's Computer Use daemon does
// (CommaComputerUseSocketServer.swift: bound under a private name, then renamed into place, so the path never names a
// socket that refuses), each connection one request after the token.
import AppKit
import CoreGraphics
import Foundation

/// Nobody connected for this long: the helper ends (the station starts it again when it needs it).
let IDLE: TimeInterval = 30 * 60

final class Daemon {
  let socketPath: String
  let token: String
  private var server: Int32 = -1
  private let lock = NSLock()
  private var connections = 0
  private var lastSeen = Date()
  /// What this process may do, as it was when it started: a grant since takes effect once it starts again.
  let started: (capture: Bool, control: Bool)
  /// The folder grants as they were when it started (Files.grants()).
  let startedFiles: [String: String]
  /// The station's watches (`watch`), told when a grant changes.
  private var watchers: [Channel] = []

  init(socketPath: String, token: String) {
    self.socketPath = socketPath
    self.token = token
    started = (CGPreflightScreenCaptureAccess(), Status.inputAllowed())
    startedFiles = Files.grants()
  }

  /// Every watch told `event` (a JSON line after its `{ok}`).
  func notify(_ event: [String: Any]) {
    lock.lock()
    let all = watchers
    lock.unlock()
    for channel in all { channel.line(event) }
  }

  func start() throws {
    let directory = (socketPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let staging = (directory as NSString).appendingPathComponent(".helper-\(getpid())")
    unlink(staging)
    guard socketPath.utf8CString.count <= 104, staging.utf8CString.count <= 104 else { throw HelperError("socket path too long: \(socketPath)") }
    server = socket(AF_UNIX, SOCK_STREAM, 0)
    guard server >= 0 else { throw HelperError("no socket") }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = staging.utf8CString
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      bytes.withUnsafeBufferPointer { buffer in UnsafeMutableRawPointer(pointer).copyMemory(from: buffer.baseAddress!, byteCount: buffer.count) }
    }
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, chmod(staging, S_IRUSR | S_IWUSR) == 0, listen(server, 16) == 0, rename(staging, socketPath) == 0 else {
      let why = String(cString: strerror(errno))
      close(server)
      unlink(staging)
      throw HelperError("socket not listened on: \(why)")
    }
    Thread.detachNewThread { [self] in accepting() }
    let idle = DispatchSource.makeTimerSource(queue: .main)
    idle.schedule(deadline: .now() + 60, repeating: 60)
    idle.setEventHandler { [self] in
      lock.lock()
      let quiet = connections == 0 && Date().timeIntervalSince(lastSeen) > IDLE
      lock.unlock()
      if quiet && !MainActor.assumeIsolated({ Permissions.shared.isShown }) { exit(0) }
    }
    idle.resume()
    idleTimer = idle
  }

  private var idleTimer: DispatchSourceTimer?

  private func accepting() {
    while true {
      let client = accept(server, nil, nil)
      if client < 0 {
        if errno == EINTR || errno == ECONNABORTED { continue }
        return
      }
      Thread.detachNewThread { [self] in serve(client) }
    }
  }

  private func serve(_ fd: Int32) {
    lock.lock()
    connections += 1
    lastSeen = Date()
    lock.unlock()
    defer {
      lock.lock()
      connections -= 1
      lastSeen = Date()
      lock.unlock()
      close(fd)
    }
    let channel = Channel(fd: fd)
    guard let line = channel.readLine(), let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
    guard let given = request["token"] as? String, same(given, token) else {
      channel.line(["error": "not the station's token"])
      return
    }
    switch request["op"] as? String {
    case "hello":
      channel.line(["ok": true, "v": 1, "pid": Int(getpid()), "app": Bundle.main.bundlePath, "capabilities": ["screen", "files", "simulator", "outflow", "ui"]])
    case "status":
      var status = Status.fresh() ?? Status.now()
      status["live"] = ["capture": CGPreflightScreenCaptureAccess(), "control": Status.inputAllowed()]
      let window = DispatchQueue.main.sync { MainActor.assumeIsolated { (Permissions.shared.isShown, Permissions.shared.asked) } }
      status["asking"] = window.0
      // What its window asks for, while it is up.
      status["asked"] = window.0 ? window.1 : []
      channel.line(status)
    case "permissions.show":
      let words = request["words"] as? [String: Any] ?? [:]
      let grants = (request["grants"] as? [String]) ?? [Grant.screenRecording.rawValue, Grant.accessibility.rawValue]
      let paths = request["paths"] as? [String: String] ?? [:]
      DispatchQueue.main.async { MainActor.assumeIsolated { Permissions.shared.show(words: words, grants: grants, paths: paths, daemon: self) } }
      channel.line(["ok": true])
    case "ui":
      // An agent-desktop command (Ui.swift): its arguments, its envelope.
      guard let arguments = request["args"] as? [String] else {
        channel.line(["error": "no arguments", "code": "args"])
        return
      }
      channel.line(Ui.run(arguments))
    case "outflow.identify":
      // Who a program at the other end of the station's outflow socket is (docs/data-outflow.md).
      channel.line(Outflow.identify(request["auditToken"] as? String ?? ""))
    case "screen.view":
      // Granted since this process started: it starts again to have it (the station asks again once it is back).
      if !CGPreflightScreenCaptureAccess() && request["synthetic"] == nil {
        let granted = (Status.fresh()?["capture"] as? Bool) ?? false
        channel.sendJSON(1, ["error": granted ? "restarting to take Screen Recording" : "Screen Recording is not granted", "code": granted ? "restart" : "capture", "capture": granted])
        if granted { DispatchQueue.main.async { self.restart() } }
        return
      }
      ScreenView(channel: channel, options: request).run()
    case "simulator.view":
      // A booted simulator's screen: nothing of macOS's to grant (SimulatorView.swift).
      guard let udid = request["udid"] as? String, UUID(uuidString: udid) != nil else {
        channel.sendJSON(1, ["error": "no simulator named", "code": "simulator"])
        return
      }
      SimulatorView(channel: channel, options: request, udid: udid).run()
    case "watch":
      // The station's watch: open for as long as this process is (its end is how the station learns this one ended).
      channel.line(["ok": true])
      lock.lock()
      watchers.append(channel)
      lock.unlock()
      while channel.readLine() != nil {}
      lock.lock()
      watchers.removeAll { $0 === channel }
      lock.unlock()
    case "restart":
      channel.line(["ok": true])
      DispatchQueue.main.async { self.restart() }
    case "quit":
      // Gone from its path before it answers: whoever asks next starts another.
      unlink(socketPath)
      close(server)
      channel.line(["ok": true])
      DispatchQueue.main.async { exit(0) }
    case let op? where Files.serve(op, request, channel, daemon: self):
      break
    default:
      channel.line(["error": "unknown op \(request["op"] ?? "")"])
    }
  }

  /// A grant taken since it started: whether it starts again to have it.
  func grantedSince() -> Bool {
    guard let fresh = Status.fresh() else { return false }
    return ((fresh["capture"] as? Bool) == true && !started.capture) || ((fresh["control"] as? Bool) == true && !started.control)
  }

  /// This app again, a new process with the same socket and token (it takes the socket over as it starts), then this
  /// one ends: what macOS granted since is had from then on. The station's process is left as it is.
  func restart() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.environment = ["STILLFAIL_HELPER_SOCKET": socketPath, "STILLFAIL_HELPER_TOKEN": token, "STILLFAIL_HELPER_TAKEOVER": "1"]
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
      if let error { FileHandle.standardError.write(Data("stillfail-helper: not started again: \(error)\n".utf8)) }
      exit(0)
    }
  }
}

/// Compared in constant time.
func same(_ a: String, _ b: String) -> Bool {
  let x = Array(a.utf8), y = Array(b.utf8)
  guard x.count == y.count else { return false }
  var differ: UInt8 = 0
  for i in 0..<x.count { differ |= x[i] ^ y[i] }
  return differ == 0
}

struct HelperError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) {
    self.description = description
  }
}
