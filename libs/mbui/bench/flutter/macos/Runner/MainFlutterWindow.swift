import Cocoa
import FlutterMacOS

// The bench's window, kept out of the way: the scene's size (900×640
// points), borderless, in the bottom-left corner of the screen, on every
// Space. It never becomes key or main and lets mouse clicks through; the
// app is an agent (LSUIElement, set by scripts/bench_flutter.sh), so it has
// no Dock icon and is not activated at launch. The Dart side exits the
// process when it is done, which closes the window.
class MainFlutterWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.styleMask = [.borderless]
    let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first
    let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 640)
    self.setFrame(NSRect(x: area.minX, y: area.minY, width: 900, height: 640), display: true)
    self.ignoresMouseEvents = true
    self.hidesOnDeactivate = false
    self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

    // No App Nap or timer coalescing while the bench runs in the background.
    benchActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical], reason: "mbui bench")

    let scale = screen?.backingScaleFactor ?? 0
    FileHandle.standardError.write(
      "bench window: 900×640 at (\(Int(area.minX)), \(Int(area.minY))), screen \(Int(screen?.frame.width ?? 0))×\(Int(screen?.frame.height ?? 0)) at \(scale)x, \(NSScreen.screens.count) screen(s)\n"
        .data(using: .utf8)!)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    self.orderFrontRegardless()
  }
}

var benchActivity: NSObjectProtocol?
