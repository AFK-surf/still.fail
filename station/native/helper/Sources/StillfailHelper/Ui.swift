// The apps' accessibility trees (docs/remote-screens.md, "Agents on a screen"): agent-desktop (vercel-labs, Apache-2.0),
// carried in this app beside its executable (scripts/native.ts), run with the arguments the station gives. Started by
// this app, it is this app's: what macOS granted it (Accessibility) is what agent-desktop may do, and the command host
// it keeps for 15 minutes (its refs' native objects) is this app's too.
import Foundation

enum Ui {
  /// A command longer than this is ended (agent-desktop's own waits are shorter).
  static let limit: TimeInterval = 60

  /// One agent-desktop command: its exit status and what it printed (one JSON envelope).
  static func run(_ arguments: [String]) -> [String: Any] {
    guard let executable = Bundle.main.url(forAuxiliaryExecutable: "agent-desktop") else {
      return ["error": "this still.fail Helper carries no agent-desktop", "code": "missing"]
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return ["error": "agent-desktop did not start: \(error)", "code": "start"]
    }
    let ending = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: ending)
    // Read to its end before waiting: a long tree fills the pipe otherwise.
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    ending.cancel()
    return ["ok": true, "status": Int(process.terminationStatus), "out": String(decoding: data, as: UTF8.self)]
  }
}
