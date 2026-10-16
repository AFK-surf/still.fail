// still.fail Helper: the station's macOS app (station/src/helper/app.ts starts it, docs/station-ts-native.md §4). What
// macOS grants (Screen Recording, Accessibility) is granted to this app, which LaunchServices starts as its own
// process: a grant that takes effect only once the process starts again restarts this app, never the station.
//
//   stillfail-helper status    one JSON line: what this process may do, which process macOS asks about, the display
//   (started by `open -n -g --env STILLFAIL_HELPER_SOCKET=… --env STILLFAIL_HELPER_TOKEN=… <app>`): the helper,
//   listening on that Unix socket until it is told to quit or nobody has connected for IDLE.
//
// Each connection to the socket is one request: a JSON line `{token, op, …}`, the token the station gave it at start.
//   hello               → {ok, v: 1, pid, app, capabilities: ["screen"]}
//   status              → {capture, control, display, responsible, live: {capture, control}, asking}: `live` what this
//                         very process may do (macOS gives a running process a new grant only once it starts again)
//   permissions.show    {words}: the window that asks for the grants (Permissions.swift) → {ok}
//   screen.view         {maxWidth, maxHeight, display?, fps?, bitrate?, synthetic?}: a view of the display; the
//                       connection then carries ScreenView.swift's messages both ways until either side closes it
//   restart             → {ok}, then this app starts again (a grant to take effect)
//   quit                → {ok}, then it ends
// Capabilities to come (the drive's protected folders, the camera) are ops of their own namespace in this one app, so
// they share its one grant identity.
import AppKit

signal(SIGPIPE, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "status" {
  Channel(fd: 1).line(Status.now())
  exit(0)
}

let environment = ProcessInfo.processInfo.environment
guard let socketPath = environment["STILLFAIL_HELPER_SOCKET"], let token = environment["STILLFAIL_HELPER_TOKEN"], !socketPath.isEmpty, !token.isEmpty else {
  FileHandle.standardError.write(Data("usage: stillfail-helper status | (STILLFAIL_HELPER_SOCKET, STILLFAIL_HELPER_TOKEN set, started by open)\n".utf8))
  exit(2)
}

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
