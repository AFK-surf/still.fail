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
//                       x, y 0..1 of the device's screen, edge 0 none, 2 top, 3 bottom (a system gesture)
// The rest is as ScreenView's; clipboard, reveal and the cursor are not had.
import CoreMedia
import CoreVideo
import Foundation
import SimNative
import VideoToolbox

final class SimulatorView: ScreenView {
  let udid: String
  let capture = FrameCapture()
  let injector = HIDInjector()
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
        try await injector.setup(deviceUDID: udid, duoHelper: "")
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
    let (limits, region) = (self.limits, limitsPart)
    scaling.unlock()
    let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
    let cut = region.map { ScreenView.crop($0, width, height) }
    let (w, h) = cut.map { (Int($0.0.width), Int($0.0.height)) } ?? (width, height)
    let scale = min(1.0, Double(limits.0) / Double(w), Double(limits.1) / Double(h))
    let even = { (v: Double) in max(2, Int(v.rounded()) & ~1) }
    guard let picture = transferred(source, crop: cut?.0, to: (even(Double(w) * scale), even(Double(h) * scale))) else { return nil }
    return (picture, cut?.1)
  }

  override func post(_ op: [String: Any]) {
    ops?.yield(op)
  }

  func perform(_ op: [String: Any]) async {
    let (width, height) = queue.sync { screen }
    let unit = { (key: String) in min(1, max(0, (op[key] as? NSNumber)?.doubleValue ?? 0)) }
    switch op["op"] as? String {
    case "touch":
      guard let type = op["type"] as? String, ["begin", "move", "end"].contains(type) else { return }
      let edge = UInt32((op["edge"] as? NSNumber)?.intValue ?? 0)
      await injector.sendTouch(type: type, x: unit("x"), y: unit("y"), screenWidth: width, screenHeight: height, edge: [0, 2, 3].contains(edge) ? edge : 0)
    case "scroll":
      let dx = (op["dx"] as? NSNumber)?.doubleValue ?? 0, dy = (op["dy"] as? NSNumber)?.doubleValue ?? 0
      let (x, y) = (unit("x"), unit("y"))
      // A wheel's burst is one drag the injector ends once it stops: not waited for, or each event would hold the next.
      Task { await injector.sendScroll(dx: dx, dy: dy, anchorX: x, anchorY: y, screenWidth: width, screenHeight: height) }
    case "key":
      guard let type = op["type"] as? String, ["down", "up"].contains(type), let usage = (op["usage"] as? NSNumber)?.uint32Value, usage > 0, usage < 0x100 else { return }
      await injector.sendKey(type: type, usage: usage)
    case "button":
      switch op["name"] as? String {
      case "keyboard": await injector.toggleSoftwareKeyboard()
      case let name? where ["home", "lock", "siri", "side_button", "app_switcher"].contains(name): await injector.sendButton(button: name, deviceUDID: udid)
      default: return
      }
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

  /// The device's pasteboard set to `text` (`simctl pbcopy`).
  func pasteboard(_ text: String) async -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "pbcopy", udid]
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
      } catch {
        process.terminationHandler = nil
        done.resume(returning: false)
      }
    }
  }
}
