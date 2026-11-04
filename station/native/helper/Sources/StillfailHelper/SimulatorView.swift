// A view of an iOS Simulator (`simulator.view`, docs/remote-screens.md "Simulators"): serve-sim's capture
// (vendor/serve-sim) reads the booted device's framebuffer through CoreSimulator, each new picture scaled into the
// view's bounds and encoded as the display's are (ScreenView.swift: its messages, its encoders, a picture only when
// one is asked for and new); its HID injector posts the input as the device's own touches, keys and buttons. Nothing
// of macOS is asked for (no Screen Recording, no Accessibility), and Simulator.app need not run.
//
//   in   3 input  JSON  {op:"touch", type:"begin"|"move"|"end", x, y, edge?}, {op:"scroll", x, y, dx, dy},
//                       {op:"key", type:"down"|"up", usage} (a USB HID keyboard usage), {op:"button", name}
//                       ("home", "lock", "siri", "side_button", "app_switcher", "keyboard": the software
//                       keyboard shown or hidden), {op:"paste", text} (the device's pasteboard set, then ⌘V);
//                       {op:"pose", name} (an iPhone Duo's hinge: "closed", "book", "open"), {op:"rotate"} (the device
//                       turned a quarter; its picture follows what its UI does);
//                       x, y 0..1 of the device's screen, edge 0 none, 2 top, 3 bottom (a system gesture)
// The rest is as ScreenView's; clipboard, reveal and the cursor are not had.
import CoreMedia
import CoreVideo
import Foundation
import SimNative
import SimNativeSupport
import VideoToolbox

final class SimulatorView: ScreenView {
  let udid: String
  let capture = FrameCapture()
  let injector = HIDInjector()
  /// A foldable's: what follows its panels, the panel shown, its hinge as far as is known (the cover's until told).
  var panels: Process?
  var followed: AsyncStream<Bool>.Continuation?
  var coverShown: Bool?
  var hinge = 0.0
  /// How far the picture is turned to stand as its panel's UI does, clockwise in quarter turns (an iPhone Duo's inner panel
  /// has its framebuffer upright and its UI on its side); under `scaling`, what a finger or a part asked for is turned back by.
  var turn = 0
  var rotation: VTPixelRotationSession?
  var rotationTurn = 0
  var rotationPool: CVPixelBufferPool?
  var rotationSize = (0, 0)
  /// The ops posted, one after another.
  var ops: AsyncStream<[String: Any]>.Continuation?
  /// The bounds and the part of the device's screen as the capture reads them (on its own queue), and the part the
  /// latest picture shows (nil: the whole).
  let scaling = NSLock()
  var limits = (0, 0)
  var limitsPart: [Double]?
  var latestPart: [Double]?
  /// The device's framebuffer as last captured (what it shows now: the device draws its next picture in it), for a part
  /// asked of a still screen.
  var source: CVPixelBuffer?
  /// The device's screen as captured, in its pixels.
  var screen = (0, 0)

  init(channel: Channel, options: [String: Any], udid: String) {
    self.udid = udid
    super.init(channel: channel, options: options)
    limits = (maxWidth, maxHeight)
  }

  override func start() {
    let started = DispatchSemaphore(value: 0)
    Task {
      defer { started.signal() }
      do {
        let helper = Bundle.main.resourceURL?.appendingPathComponent("stillfail-duo-hid").path ?? ""
        try await injector.setup(deviceUDID: udid, duoHelper: helper)
        if await injector.isFoldable() {
          await followPanels()
        } else if let said = await enumerated() {
          // (a device left on its side by an earlier view: as it stands from the first picture)
          _ = setTurn(Self.turnOf(said, panel: "primary"))
        }
        let first = AsyncStream<(Int, Int)>.makeStream()
        await capture.setReemitsIdle(false)
        try await capture.start(deviceUDID: udid, pixelConsumers: PixelConsumerCount()) { [weak self] buffer, time, _ in
          guard let self else { return }
          let size = (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
          first.continuation.yield(size)
          // The framebuffer is the device's, used again for its next picture: scaled into one of ours now.
          guard let got = self.scaled(buffer) else { return }
          let at = Int64(CMTimeGetSeconds(time) * 1_000_000)
          self.queue.async {
            self.screen = size
            self.source = buffer
            self.latestPart = got.1
            self.took(got.0, at)
          }
        }
        // Its first picture says its size (a device asleep still has one: the black screen).
        let size = await withTaskGroup(of: (Int, Int)?.self) { group in
          group.addTask {
            for await size in first.stream { return size }
            return nil
          }
          group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return nil
          }
          let size = await group.next() ?? nil
          group.cancelAll()
          first.continuation.finish()
          return size
        }
        guard let (width, height) = size else {
          channel.sendJSON(1, ["error": "the simulator showed no picture", "code": "simulator"])
          return
        }
        let (w, h) = fitted(width, height)
        queue.sync {
          self.screen = (width, height)
          self.opened(w, h)
        }
      } catch {
        channel.sendJSON(1, ["error": error.localizedDescription, "code": "simulator"])
      }
    }
    started.wait()
    let (stream, continuation) = AsyncStream<[String: Any]>.makeStream()
    ops = continuation
    Task {
      for await op in stream { await perform(op) }
    }
  }

  override func stop() {
    panels?.terminate()
    followed?.finish()
    if let rotation { VTPixelRotationSessionInvalidate(rotation) }
    ops?.finish()
    super.stop()
    let done = DispatchSemaphore(value: 0)
    Task {
      await capture.stop()
      await injector.close()
      done.signal()
    }
    _ = done.wait(timeout: .now() + 2)
  }

  /// From its next picture, fitted into `width`×`height`, of `region` of the device's screen alone (nil: the whole).
  /// Its framebuffer is read whole at its own pixels anyway: the part is cut from each picture as it is scaled.
  override func bounds(_ width: Int, _ height: Int, region: [Double]?) {
    queue.async {
      self.maxWidth = max(16, width)
      self.maxHeight = max(16, height)
      self.scaling.lock()
      self.limits = (self.maxWidth, self.maxHeight)
      self.limitsPart = region
      self.scaling.unlock()
      guard region != self.region else { return }
      self.region = region
      // a still screen brings no picture: the part cut from what it shows now
      if let source = self.source, let got = self.scaled(source) {
        self.latestPart = got.1
        self.took(got.0, self.now())
      }
    }
  }

  /// The latest picture as scaled, and the part it shows.
  override func framed() -> (CVPixelBuffer, [Double]?)? {
    latest.map { ($0, latestPart) }
  }

  /// The picture (the part asked of it) fitted into the view's bounds, in a buffer of the view's own: NV12 for the
  /// video's encoder, BGRA for a JPEG; and the part it shows. On the capture's queue.
  func scaled(_ source: CVPixelBuffer) -> (CVPixelBuffer, [Double]?)? {
    scaling.lock()
    let (limits, region, turn) = (self.limits, limitsPart, self.turn)
    scaling.unlock()
    let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
    let cut = region.map { ScreenView.crop(Self.unturned($0, turn), width, height) }
    let (w, h) = cut.map { (Int($0.0.width), Int($0.0.height)) } ?? (width, height)
    let (limitW, limitH) = turn % 2 == 1 ? (limits.1, limits.0) : limits
    let scale = min(1.0, Double(limitW) / Double(w), Double(limitH) / Double(h))
    let even = { (v: Double) in max(2, Int(v.rounded()) & ~1) }
    guard let picture = transferred(source, crop: cut?.0, to: (even(Double(w) * scale), even(Double(h) * scale))) else {
      return nil
    }
    guard turn != 0 else { return (picture, cut?.1) }
    guard let turned = rotated(picture, turn) else { return nil }
    return (turned, cut.map { Self.turned($0.1, turn) })
  }

  /// `picture` turned `turn` quarter turns clockwise, in a buffer of the view's own.
  func rotated(_ picture: CVPixelBuffer, _ turn: Int) -> CVPixelBuffer? {
    transferring.lock()
    defer { transferring.unlock() }
    if rotation == nil || rotationTurn != turn {
      if let rotation { VTPixelRotationSessionInvalidate(rotation) }
      rotation = nil
      VTPixelRotationSessionCreate(nil, &rotation)
      guard let rotation else { return nil }
      let angle = turn == 1 ? kVTRotation_CW90 : turn == 2 ? kVTRotation_180 : kVTRotation_CCW90
      VTSessionSetProperty(rotation, key: kVTPixelRotationPropertyKey_Rotation, value: angle)
      rotationTurn = turn
    }
    let w = CVPixelBufferGetWidth(picture), h = CVPixelBufferGetHeight(picture)
    let size = turn % 2 == 1 ? (h, w) : (w, h)
    if rotationPool == nil || rotationSize != size {
      let attributes: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(picture),
        kCVPixelBufferWidthKey: size.0,
        kCVPixelBufferHeightKey: size.1,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
      ]
      rotationPool = nil
      CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &rotationPool)
      rotationSize = size
    }
    guard let rotation, let rotationPool else { return nil }
    var made: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, rotationPool, &made) == kCVReturnSuccess, let turned = made,
      VTPixelRotationSessionRotateImage(rotation, picture, turned) == noErr
    else { return nil }
    return turned
  }

  /// A point of the picture as shown, as a point of the device's framebuffer.
  static func unturned(_ x: Double, _ y: Double, _ turn: Int) -> (Double, Double) {
    switch turn {
    case 1: return (y, 1 - x)
    case 2: return (1 - x, 1 - y)
    case 3: return (1 - y, x)
    default: return (x, y)
    }
  }

  /// A part of the picture as shown (x, y, w, h), as a part of the framebuffer.
  static func unturned(_ p: [Double], _ turn: Int) -> [Double] {
    switch turn {
    case 1: return [p[1], 1 - p[0] - p[2], p[3], p[2]]
    case 2: return [1 - p[0] - p[2], 1 - p[1] - p[3], p[2], p[3]]
    case 3: return [1 - p[1] - p[3], p[0], p[3], p[2]]
    default: return p
    }
  }

  /// A part of the framebuffer, as a part of the picture as shown.
  static func turned(_ p: [Double], _ turn: Int) -> [Double] {
    unturned(p, (4 - turn) % 4)
  }

  override func post(_ op: [String: Any]) {
    ops?.yield(op)
  }

  func perform(_ op: [String: Any]) async {
    let (width, height) = queue.sync { screen }
    let turn = turnNow()
    let unit = { (key: String) in min(1, max(0, (op[key] as? NSNumber)?.doubleValue ?? 0)) }
    switch op["op"] as? String {
    case "touch":
      guard let type = op["type"] as? String, ["begin", "move", "end"].contains(type) else { return }
      // (an edge is the framebuffer's; a picture turned has its gestures by the device's own buttons)
      let edge = turn == 0 ? UInt32((op["edge"] as? NSNumber)?.intValue ?? 0) : 0
      let (tx, ty) = Self.unturned(unit("x"), unit("y"), turn)
      await injector.sendTouch(type: type, x: tx, y: ty, screenWidth: width, screenHeight: height, edge: [0, 2, 3].contains(edge) ? edge : 0)
    case "scroll":
      let dx = (op["dx"] as? NSNumber)?.doubleValue ?? 0, dy = (op["dy"] as? NSNumber)?.doubleValue ?? 0
      let (x, y) = Self.unturned(unit("x"), unit("y"), turn)
      // (a wheel's way, turned as the point is about the picture's middle)
      let (ux, uy) = Self.unturned(0.5 + dx, 0.5 + dy, turn)
      let (sx, sy) = (ux - 0.5, uy - 0.5)
      // A wheel's burst is one drag the injector ends once it stops: not waited for, or each event would hold the next.
      Task { await injector.sendScroll(dx: sx, dy: sy, anchorX: x, anchorY: y, screenWidth: width, screenHeight: height) }
    case "key":
      guard let type = op["type"] as? String, ["down", "up"].contains(type), let usage = (op["usage"] as? NSNumber)?.uint32Value, usage > 0, usage < 0x100 else { return }
      await injector.sendKey(type: type, usage: usage)
    case "button":
      switch op["name"] as? String {
      case "keyboard": await injector.toggleSoftwareKeyboard()
      case let name? where ["home", "lock", "siri", "side_button", "app_switcher", "volume_up", "volume_down"].contains(name): await injector.sendButton(button: name, deviceUDID: udid)
      default: return
      }
    case "memory_warning":
      await injector.simulateMemoryWarning()
    case "pose":
      guard let name = op["name"] as? String, let pose = DevicePose.preset(named: name) else { return }
      guard await injector.setPose(name, fromDegrees: hinge) else { return }
      hinge = pose.hingeDegrees
      await showPanel(cover: pose.hingeDegrees < 90)
    case "rotate":
      let turned = ((KnownTurns.shared[udid] ?? 0) + 1) % 4
      let orientation = [HIDInjector.orientationPortrait, HIDInjector.orientationLandscapeRight, HIDInjector.orientationPortraitUpsideDown, HIDInjector.orientationLandscapeLeft][turned]
      guard await injector.sendOrientation(orientation: orientation) else { return }
      KnownTurns.shared[udid] = turned
      // (a device under load is seconds behind the turn it was told of)
      Task { await lookTurn(cover: coverShown, waits: [0] + Array(repeating: 1, count: 12)) }
    case "paste":
      guard let text = op["text"] as? String, !text.isEmpty else { return }
      guard await pasteboard(text) else { return }
      // ⌘V: the left GUI key held round V.
      await injector.sendKey(type: "down", usage: 0xE3)
      await injector.sendKey(type: "down", usage: 0x19)
      await injector.sendKey(type: "up", usage: 0x19)
      await injector.sendKey(type: "up", usage: 0xE3)
    default:
      return
    }
  }

  /// A foldable's picture is of the panel in use, not the smallest one capture would pick by itself: SpringBoard says which as
  /// it changes (a pose from here, or from Device Hub), and what it last said since the boot says which it is now.
  func followPanels() async {
    let simctl = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"
    let predicate = "subsystem == \"com.apple.SpringBoard\" AND category == \"DisplayContentMode\""
    let run = { (arguments: [String], ended: (() -> Void)?, line: @escaping (String) -> Void) -> Process in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: simctl)
      process.arguments = ["spawn", self.udid, "log"] + arguments + ["--style", "compact", "--predicate", predicate]
      let out = Pipe()
      process.standardOutput = out
      process.standardError = FileHandle.nullDevice
      var pending = ""
      out.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
          ended?()
          return
        }
        pending += String(decoding: data, as: UTF8.self)
        var parts = pending.components(separatedBy: "\n")
        pending = parts.removeLast()
        parts.forEach(line)
      }
      try? process.run()
      return process
    }
    let said = { (text: String) -> Bool? in
      text.contains(".cover:pri") ? true : text.contains(".inner:pri") ? false : nil
    }
    // As they come, one after another: each its own task, a quick few could end in another order than they came, the capture
    // left at the size of the panel not in use (its picture stretched to that).
    let (changes, change) = AsyncStream<Bool>.makeStream()
    followed = change
    Task { [weak self] in
      for await cover in changes { await self?.showPanel(cover: cover) }
    }
    let boot = BootPanel()
    panels = run(["stream"], nil) { text in
      guard let cover = said(text) else { return }
      boot.overtaken()
      change.yield(cover)
    }
    // Only the last the boot's log says is what shows now (every fold since the boot, one by one, was the picture going back and
    // forth as the view opened): before the first picture where it is read in time, unless one has come since.
    _ = run(["show", "--last", "boot"], { boot.read() }) { text in
      if let cover = said(text) { boot.said(cover) }
    }
    // The panel an earlier view here left it on, at once: the boot's log is read whole, longer the longer the device has been up,
    // and on a busy Mac past the wait below (the first pictures the cover's, then the inner's, side run 41673108710). The log
    // still says, as it comes, a fold made with no view following it.
    if let cover = KnownPanels.shared[udid] {
      await showPanel(cover: cover, opening: true)
      Task {
        while !boot.done { try? await Task.sleep(for: .milliseconds(100)) }
        if let cover = boot.taken() { change.yield(cover) }
      }
      return
    }
    for _ in 0..<150 where !boot.done {
      try? await Task.sleep(for: .milliseconds(20))
    }
    if boot.done {
      if let cover = boot.taken() { await showPanel(cover: cover, opening: true) }
    } else {
      Task {
        while !boot.done { try? await Task.sleep(for: .milliseconds(100)) }
        if let cover = boot.taken() { change.yield(cover) }
      }
    }
  }

  /// The picture to be of the cover or the inner panel; the hinge where a next pose sweeps from.
  func showPanel(cover: Bool, opening: Bool = false) async {
    guard coverShown != cover else { return }
    coverShown = cover
    KnownPanels.shared[udid] = cover
    if cover { hinge = min(hinge, 0) } else if hinge < 90 { hinge = 180 }
    let size = cover ? (DevicePose.coverWidth, DevicePose.coverHeight) : (DevicePose.innerWidth, DevicePose.innerHeight)
    await capture.setPreferredScreenSize(width: size.0, height: size.1)
    if opening {
      // (as it stands for the first picture, then once it has settled, not holding the view's opening back)
      if let said = await enumerated() {
        _ = setTurn(Self.turnOf(said, panel: cover ? "primary" : "primary-1"))
      }
    }
    // (not waited for: the next press would wait for all of it, seconds, behind it)
    Task { await lookTurn(cover: cover) }
  }

  /// How the panel's UI stands as CoreSimulator says it, the picture turned to match. Asked as a panel comes up, and again
  /// once it has settled (its orientation follows the panel by a moment).
  func lookTurn(cover: Bool?, waits: [Int] = [0, 1, 2]) async {
    for wait in waits {
      try? await Task.sleep(for: .seconds(wait))
      guard coverShown == cover, let said = await enumerated() else { continue }
      let now = Self.turnOf(said, panel: cover == false ? "primary-1" : "primary")
      if setTurn(now) {
        // a still screen brings no picture: what it shows now, turned
        queue.async {
          if let source = self.source, let got = self.scaled(source) {
            self.latestPart = got.1
            self.took(got.0, self.now())
          }
        }
      }
    }
  }

  func turnNow() -> Int {
    scaling.lock()
    defer { scaling.unlock() }
    return turn
  }

  /// Whether that was a change.
  func setTurn(_ now: Int) -> Bool {
    scaling.lock()
    defer { scaling.unlock() }
    let changed = turn != now
    turn = now
    return changed
  }

  /// The quarter turns clockwise a panel's picture is shown at, from `simctl io enumerate`'s words of it.
  static func turnOf(_ said: String, panel: String) -> Int {
    // (a device of one panel: "primary" on the newer runtimes, "PurpleMain" on the older)
    for block in said.components(separatedBy: "Device Name: ").dropFirst()
    where block.hasPrefix(panel + "\n") || (panel == "primary" && block.hasPrefix("PurpleMain\n")) {
      guard let line = block.split(separator: "\n").first(where: { $0.contains("UI Orientation:") }) else { return 0 }
      if line.hasSuffix("Landscape Left") { return 1 }
      if line.hasSuffix("Landscape Right") { return 3 }
      if line.hasSuffix("Portrait Upside Down") { return 2 }
      return 0
    }
    return 0
  }

  func enumerated() async -> String? {
    await withCheckedContinuation { done in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl")
      process.arguments = ["io", udid, "enumerate"]
      let out = Pipe()
      process.standardOutput = out
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { return done.resume(returning: nil) }
      DispatchQueue.global().async {
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        done.resume(returning: String(decoding: data, as: UTF8.self))
      }
    }
  }

  /// The device's pasteboard set to `text`: through CoreDevice from Xcode 27, whose guest takes no legacy snapshots while
  /// Device Hub's stack is in use (`simctl pbcopy` succeeds and changes nothing), else `simctl pbcopy` (CoreSimulator's own
  /// simctl: Xcode's is a script that may ask for a password first, screens/simulator.ts).
  func pasteboard(_ text: String) async -> Bool {
    if HIDInjector.usesDTUHID {
      // (CoreDevice's own devicectl: Xcode's, as its simctl, is a script that may first run `xcodebuild -runFirstLaunch`, which
      // waits for an administrator's password nobody at this view can give)
      let copied = await piped(text, "/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/Resources/bin/devicectl", ["device", "pasteboard", "copy", "--device", udid, "--timeout", "5", "--quiet"])
      if copied { return true }
    }
    return await piped(text, "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl", ["pbcopy", udid])
  }

  /// `file` run with `text` on its stdin; whether it succeeded. Ended after a while: a person's next keys wait on it.
  private func piped(_ text: String, _ file: String, _ arguments: [String]) async -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: file)
    process.arguments = arguments
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    return await withCheckedContinuation { done in
      process.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
      do {
        try process.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { if process.isRunning { process.terminate() } }
      } catch {
        process.terminationHandler = nil
        done.resume(returning: false)
      }
    }
  }
}

/// What the boot's log says of the panel in use, as it is read: its last, once all of it has been, unless the live log has
/// said one since.
private final class BootPanel: @unchecked Sendable {
  private let lock = NSLock()
  private var last: Bool?
  private var finished = false

  var done: Bool {
    lock.lock()
    defer { lock.unlock() }
    return finished
  }

  func said(_ cover: Bool) {
    lock.lock()
    defer { lock.unlock() }
    last = cover
  }

  func read() {
    lock.lock()
    defer { lock.unlock() }
    finished = true
  }

  func overtaken() {
    lock.lock()
    defer { lock.unlock() }
    last = nil
  }

  func taken() -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    defer { last = nil }
    return last
  }
}

/// How many quarter turns from upright a device was last turned from here, for the views after this one.
private final class KnownTurns: @unchecked Sendable {
  static let shared = KnownTurns()
  private let lock = NSLock()
  private var turns: [String: Int] = [:]

  subscript(udid: String) -> Int? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return turns[udid]
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      turns[udid] = newValue
    }
  }
}

/// The panel each device was last shown on by a view here, by its UDID (true: the cover).
private final class KnownPanels: @unchecked Sendable {
  static let shared = KnownPanels()
  private let lock = NSLock()
  private var covers: [String: Bool] = [:]

  subscript(udid: String) -> Bool? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return covers[udid]
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      covers[udid] = newValue
    }
  }
}
