// What this process may do, and which process macOS asks about for it.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum Status {
  static func inputAllowed() -> Bool {
    CGPreflightPostEventAccess() || AXIsProcessTrusted()
  }

  /// This process's grants as macOS has them now, the main display, and who macOS asks about.
  static func now() -> [String: Any] {
    [
      "capture": CGPreflightScreenCaptureAccess(),
      "control": inputAllowed(),
      "responsible": responsible(),
      "display": display(CGMainDisplayID()),
      "app": Bundle.main.bundlePath,
      "files": Files.grants(),
    ]
  }

  /// The grants as a process started now would have them: asked of a new process (this executable's `status`), as a
  /// running one keeps what it had when it started. Its parent's (this app's) are what it reports.
  static func fresh() -> [String: Any]? {
    guard let executable = Bundle.main.executablePath else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["status"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  /// The process macOS asks about for this one: LaunchServices made this app its own; a process started by another
  /// is that one's (the station's launcher, under launchd).
  static func responsible() -> [String: Any] {
    typealias Responsible = @convention(c) (pid_t) -> pid_t
    var pid = getpid()
    if let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") {
      pid = unsafeBitCast(symbol, to: Responsible.self)(getpid())
    }
    var path = executablePath(pid) ?? ""
    // An app's process: it is the app that System Settings lists.
    if let range = path.range(of: ".app/Contents/MacOS/") { path = String(path[..<range.lowerBound]) + ".app" }
    var name = (path as NSString).lastPathComponent
    if name.hasSuffix(".app") {
      name = (Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? String(name.dropLast(4))
    }
    return ["pid": Int(pid), "path": path, "name": name]
  }

  static func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
    // A process whose file was moved away since (updated in place): its executable path as it was started.
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 4 { return nil }
    var args = [UInt8](repeating: 0, count: size)
    if sysctl(&mib, 3, &args, &size, nil, 0) != 0 { return nil }
    guard let end = args[4..<size].firstIndex(of: 0) else { return nil }
    return String(decoding: args[4..<end], as: UTF8.self)
  }

  static func display(_ id: CGDirectDisplayID) -> [String: Any] {
    let bounds = CGDisplayBounds(id)
    let mode = CGDisplayCopyDisplayMode(id)
    return [
      "id": Int(id),
      "width": mode?.pixelWidth ?? Int(bounds.width),
      "height": mode?.pixelHeight ?? Int(bounds.height),
      "points": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height],
    ]
  }
}
