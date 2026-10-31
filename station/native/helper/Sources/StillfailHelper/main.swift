// still.fail Helper: the station's macOS app (station/src/helper/app.ts starts it, docs/station-ts-native.md §4). What
// macOS grants (Screen Recording, Accessibility) is granted to this app, which LaunchServices starts as its own
// process: a grant that takes effect only once the process starts again restarts this app, never the station.
//
//   stillfail-helper status    one JSON line: what this process may do, which process macOS asks about, the display
//   (started by `open -n -g <app>`, or by macOS itself: its Quit & Reopen after a grant): the helper, listening on
//   helper.sock beside the app (the station's <data>/helper) for requests with the token in `token` there, until it
//   is told to quit or nobody has connected for IDLE. STILLFAIL_HELPER_SOCKET and STILLFAIL_HELPER_TOKEN say
//   otherwise. One helper a directory (a lock beside the app): another started there ends at once, unless it is this
//   one starting itself again (STILLFAIL_HELPER_TAKEOVER), which waits for the lock.
//
// Each connection to the socket is one request: a JSON line `{token, op, …}`, the token the station gave it at start.
//   hello               → {ok, v: 1, pid, app, capabilities: ["screen", "files", "simulator", "outflow", "ui"]}
//   status              → {capture, control, display, responsible, files, live: {capture, control}, asking, asked}:
//                         `live` what this very process may do (macOS gives a running process a new grant only once it
//                         starts again); `files` the folder grants (Files.swift); `asked` what the window shows
//   permissions.show    {words, grants?, paths?}: the window that asks for the grants (Permissions.swift; `grants` the
//                       screen's two when none named, `paths` a disk's folder for its grant) → {ok}
//   screen.view         {maxWidth, maxHeight, display?, fps?, bitrate?, audio?, synthetic?}: a view of the display
//                       (`audio: true`: and the Mac's system output, SystemAudio.swift); the connection then carries
//                       ScreenView.swift's messages both ways until either side closes it
//   simulator.view      {udid, maxWidth, maxHeight, codec, fps?, bitrate?}: a view of a booted iOS Simulator, its messages
//                       ScreenView's (SimulatorView.swift says its input)
//   files.*             the drive's protected folders (Files.swift says them)
//   ui                  {args}: agent-desktop run with them (Ui.swift: the apps' accessibility trees, acted on by ref)
//                       → {ok, status, out}: its exit status and its JSON envelope
//   watch               → {ok}, then held open for as long as this process is (the station's supervision); a grant
//                         changing while the window is up, and the window closing, are told on it as a line
//                         {event: "grants"}
//   restart             → {ok}, then this app starts again (a grant to take effect)
//   quit                → {ok}, then it ends
// Capabilities to come (the camera) are ops of their own namespace in this one app, as `screen.*` and `files.*` are, so
// they share its one grant identity.
import AppKit

signal(SIGPIPE, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "status" {
  Channel(fd: 1).line(Status.now())
  exit(0)
}

let environment = ProcessInfo.processInfo.environment
/// Where the station put this app: its socket and token beside it.
let home = Bundle.main.bundleURL.deletingLastPathComponent().path
let socketPath = environment["STILLFAIL_HELPER_SOCKET"] ?? (home as NSString).appendingPathComponent("helper.sock")
let token = environment["STILLFAIL_HELPER_TOKEN"]
  ?? ((try? String(contentsOfFile: (home as NSString).appendingPathComponent("token"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
guard !token.isEmpty else {
  FileHandle.standardError.write(Data("stillfail-helper: no token beside the app (\(home)/token): the station starts it\n".utf8))
  exit(2)
}
// One helper here: the lock is held for as long as this process is.
let lockPath = (home as NSString).appendingPathComponent("helper.lock")
let lock = open(lockPath, O_CREAT | O_RDWR, 0o600)
var locked = lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0
if !locked && environment["STILLFAIL_HELPER_TAKEOVER"] == "1" {
  // This app starting itself again: the one before ends in a moment.
  for _ in 0..<100 where !locked {
    usleep(100_000)
    locked = flock(lock, LOCK_EX | LOCK_NB) == 0
  }
}
guard locked else { exit(0) }

let application = NSApplication.shared
_ = application.setActivationPolicy(.accessory)
let daemon = Daemon(socketPath: socketPath, token: token)
do {
  try daemon.start()
} catch {
  FileHandle.standardError.write(Data("stillfail-helper: \(error)\n".utf8))
  exit(1)
}
application.run()
