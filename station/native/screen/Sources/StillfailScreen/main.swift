// stillfail-screen: this Mac's display as a screen source of the station (docs/remote-screens.md; started by
// station/src/screens/desktop.ts, one process per view, so a view's capture, encoder and input end with it).
//
//   stillfail-screen status     one JSON line: whether this process may capture the screen and post input, which
//                               process macOS asks about (the one the grants are given to), the main display
//   stillfail-screen request    asks macOS for both (its prompts show on this Mac, and the process is then listed in
//                               System Settings), then answers as `status`
//   stillfail-screen view [--display ID] [--max-width W] [--max-height H] [--fps N] [--bitrate BPS]
//                         [--synthetic moving|still]
//
// A view talks in messages both ways on stdin/stdout: a kind byte, the payload's length (4 bytes, big-endian), the
// payload. It is pull-driven: a picture is encoded only once one is asked for, and only a new one (the screen changed)
// unless a key frame is asked for.
//   in   1 next      (empty)  the next new picture, encoded
//        2 keyframe  (empty)  the next one a key frame, the screen changed or not
//        3 input     JSON     an input operation: {op:"mouse", type:"move"|"down"|"up", x, y, button, buttons, clicks,
//                             flags}, {op:"scroll", x, y, dx, dy, flags}, {op:"key", keycode, down, flags},
//                             {op:"text", text}; x, y are 0..1 of the display, flags CGEventFlags
//   out  1 info      JSON     first: {width, height, encoder}, or {error, code: "capture"|"display"|"encoder"}
//        2 config    4 bytes width, 4 bytes height, then the avcC: before the first frame and whenever it changes
//        3 frame     1 byte flags (bit 0: key frame), 8 bytes timestamp (µs), then the frame (AVCC)
//        4 event     JSON     {refused: "control"}: input was posted without the permission (macOS drops it)
// It ends when its stdin does. `--synthetic` encodes made-up pictures instead of capturing (the side test's
// measurement of the encoder and the link on a Mac that has not granted Screen Recording): never what a person sees.
import AppKit
import ApplicationServices
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

signal(SIGPIPE, SIG_IGN)

// MARK: - Output

let outLock = NSLock()

/// Writes all of `data` to stdout, or ends the process: whoever read it is gone.
func writeAll(_ data: Data) {
  data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    var at = 0
    while at < raw.count {
      let n = write(1, raw.baseAddress! + at, raw.count - at)
      if n < 0 {
        if errno == EINTR { continue }
        exit(0)
      }
      at += n
    }
  }
}

func emit(_ kind: UInt8, _ payload: Data) {
  var head = Data([kind])
  var n = UInt32(payload.count).bigEndian
  head.append(Data(bytes: &n, count: 4))
  outLock.lock()
  writeAll(head + payload)
  outLock.unlock()
}

func json(_ value: Any) -> Data {
  (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
}

func emitJSON(_ kind: UInt8, _ value: [String: Any]) {
  emit(kind, json(value))
}

func line(_ value: [String: Any]) {
  writeAll(json(value) + Data("\n".utf8))
}

// MARK: - Status

/// The process macOS asks about for this one: the one that started the chain under launchd (the station's launcher,
/// or the desktop app), whose grants this process has.
func responsible() -> [String: Any] {
  typealias Responsible = @convention(c) (pid_t) -> pid_t
  var pid = getpid()
  if let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") {
    pid = unsafeBitCast(symbol, to: Responsible.self)(getpid())
  }
  var path = executablePath(pid) ?? ""
  // An app's process: it is the app that System Settings lists.
  if let range = path.range(of: ".app/Contents/MacOS/") { path = String(path[..<range.lowerBound]) + ".app" }
  var name = (path as NSString).lastPathComponent
  if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
  return ["pid": Int(pid), "path": path, "name": name]
}

func executablePath(_ pid: pid_t) -> String? {
  var buffer = [CChar](repeating: 0, count: 4096)
  if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
  // A process whose file was moved away since (a station updated in place): its executable path as it was started.
  var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
  var size = 0
  if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 4 { return nil }
  var args = [UInt8](repeating: 0, count: size)
  if sysctl(&mib, 3, &args, &size, nil, 0) != 0 { return nil }
  let start = 4
  guard let end = args[start..<size].firstIndex(of: 0) else { return nil }
  return String(decoding: args[start..<end], as: UTF8.self)
}

func displayInfo(_ id: CGDirectDisplayID) -> [String: Any] {
  let bounds = CGDisplayBounds(id)
  let mode = CGDisplayCopyDisplayMode(id)
  return [
    "id": Int(id),
    "width": mode?.pixelWidth ?? Int(bounds.width),
    "height": mode?.pixelHeight ?? Int(bounds.height),
    "points": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height],
  ]
}

func inputAllowed() -> Bool {
  CGPreflightPostEventAccess() || AXIsProcessTrusted()
}

func status() -> [String: Any] {
  [
    "capture": CGPreflightScreenCaptureAccess(),
    "control": inputAllowed(),
    "responsible": responsible(),
    "display": displayInfo(CGMainDisplayID()),
  ]
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? ""
func option(_ name: String) -> String? {
  guard let at = arguments.firstIndex(of: name), at + 1 < arguments.count else { return nil }
  return arguments[at + 1]
}

switch command {
case "status":
  line(status())
  exit(0)
case "request":
  _ = CGRequestScreenCaptureAccess()
  _ = CGRequestPostEventAccess()
  let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
  _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
  line(status())
  exit(0)
case "view":
  break
default:
  FileHandle.standardError.write(Data("usage: stillfail-screen status | request | view [--display ID] [--max-width W] [--max-height H] [--fps N] [--bitrate BPS] [--synthetic moving|still]\n".utf8))
  exit(2)
}

// MARK: - The view

let displayID = option("--display").flatMap { UInt32($0) } ?? CGMainDisplayID()
let maxWidth = max(16, Int(option("--max-width") ?? "") ?? 1920)
let maxHeight = max(16, Int(option("--max-height") ?? "") ?? 1080)
let fps = min(120, max(1, Int(option("--fps") ?? "") ?? 60))
let synthetic = option("--synthetic")

/// The source's size fitted into the view's bounds, never larger, in even pixels (what 4:2:0 encodes).
func fitted(_ width: Int, _ height: Int) -> (Int, Int) {
  let scale = min(1.0, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
  let even = { (v: Double) in max(2, Int(v.rounded()) & ~1) }
  return (even(Double(width) * scale), even(Double(height) * scale))
}

final class View: NSObject, SCStreamOutput, SCStreamDelegate {
  /// Everything below happens on this queue.
  let queue = DispatchQueue(label: "fail.still.screen.view", qos: .userInteractive)
  var stream: SCStream?
  var timer: DispatchSourceTimer?
  var session: VTCompressionSession?
  var size = (0, 0)
  var encoder = ""
  /// The latest picture, whether it was encoded yet, and when it was captured (µs).
  var latest: CVPixelBuffer?
  var latestAt: Int64 = 0
  var fresh = false
  /// Frames asked for and not given yet; one is being encoded.
  var wanted = 0
  var encoding = false
  var forceKey = true
  var lastTs: Int64 = 0
  var lastConfig = Data()
  var tick = 0

  // MARK: capture

  func start() {
    let display = displayInfo(displayID)
    let (width, height) = fitted(display["width"] as! Int, display["height"] as! Int)
    if let mode = synthetic {
      startSynthetic(width, height, moving: mode != "still")
      return
    }
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shown = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
          emitJSON(1, ["error": "no display to capture", "code": "display"])
          exit(1)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.queueDepth = 5
        configuration.showsCursor = true
        let stream = SCStream(filter: SCContentFilter(display: shown, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.async {
          self.stream = stream
          self.opened(width, height)
        }
      } catch {
        // Screen Recording not granted is what this usually is (SCStreamError.userDeclined).
        emitJSON(1, ["error": error.localizedDescription, "code": "capture", "capture": CGPreflightScreenCaptureAccess()])
        exit(1)
      }
    }
  }

  func opened(_ width: Int, _ height: Int) {
    if !makeSession(width, height) {
      emitJSON(1, ["error": "no H.264 encoder", "code": "encoder"])
      exit(1)
    }
    emitJSON(1, ["width": width, "height": height, "encoder": encoder])
    pump()
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
    // Only a picture that is new: an idle one says the screen did not change.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let raw = attachments.first?[.status] as? Int, let frameStatus = SCFrameStatus(rawValue: raw), frameStatus != .complete
    {
      return
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    took(buffer, pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000) : Int64(DispatchTime.now().uptimeNanoseconds / 1000))
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    emitJSON(4, ["stopped": error.localizedDescription])
    exit(1)
  }

  /// A new picture: kept as the latest, encoded once one is wanted.
  func took(_ buffer: CVPixelBuffer, _ at: Int64) {
    latest = buffer
    latestAt = at
    fresh = true
    pump()
  }

  func startSynthetic(_ width: Int, _ height: Int, moving: Bool) {
    queue.async {
      self.opened(width, height)
      self.took(self.picture(width, height), self.now())
      guard moving else { return }
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps))
      timer.setEventHandler { self.took(self.picture(width, height), self.now()) }
      timer.resume()
      self.timer = timer
    }
  }

  func now() -> Int64 { Int64(DispatchTime.now().uptimeNanoseconds / 1000) }

  /// A made-up picture: text-like stripes that scroll (as a page does) and a box that moves, each tick.
  func picture(_ width: Int, _ height: Int) -> CVPixelBuffer {
    var made: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &made)
    let buffer = made!
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let rows = height / 24 + 1
    for row in 0..<rows {
      let line = row + tick
      context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1))
      let length = Double((line * 7919) % (width / 2)) + Double(width) / 4
      // Words: dashes of their own lengths along the line.
      var x = 40.0
      var word = line * 31
      while x < 40 + length {
        let w = Double(20 + (word * 37) % 90)
        context.fill(CGRect(x: x, y: Double(height - 24 - row * 24 + (tick * 6) % 24), width: min(w, 40 + length - x), height: 10))
        x += w + 12
        word += 1
      }
    }
    context.setFillColor(CGColor(red: 0.85, green: 0.3, blue: 0.2, alpha: 1))
    let side = Double(height) / 5
    let x = Double((tick * 8) % max(1, width - Int(side)))
    context.fill(CGRect(x: x, y: Double(height) / 2 - side / 2, width: side, height: side))
    tick += 1
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
  }

  // MARK: encoding

  func makeSession(_ width: Int, _ height: Int) -> Bool {
    if let session { VTCompressionSessionInvalidate(session) }
    session = nil
    // Hardware with low-latency rate control first (frames come out as they go in), then hardware, then any.
    let tries: [(String, [CFString: Any])] = [
      ("hardware, low latency", [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true, kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]),
      ("hardware", [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]),
      ("software", [:]),
    ]
    for (name, specification) in tries {
      var made: VTCompressionSession?
      let status = VTCompressionSessionCreate(
        allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
        encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
        outputCallback: nil, refcon: nil, compressionSessionOut: &made)
      guard status == noErr, let made else { continue }
      let set = { (key: CFString, value: Any) in VTSessionSetProperty(made, key: key, value: value as CFTypeRef) }
      _ = set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue!)
      _ = set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse!)
      // Baseline, as every decoder takes it (constrained where the system has it); Main if neither is taken.
      var profiles: [CFString] = [kVTProfileLevel_H264_Baseline_AutoLevel, kVTProfileLevel_H264_Main_AutoLevel]
      if #available(macOS 12.0, *) { profiles.insert(kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel, at: 0) }
      var profile = "default"
      for p in profiles where set(kVTCompressionPropertyKey_ProfileLevel, p) == noErr {
        profile = p as String
        break
      }
      let bitrate = Int(option("--bitrate") ?? "") ?? max(1_000_000, width * height * 3)
      _ = set(kVTCompressionPropertyKey_AverageBitRate, bitrate)
      _ = set(kVTCompressionPropertyKey_ExpectedFrameRate, fps)
      // A key frame when asked for, and at least every 10 s besides.
      _ = set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 10)
      VTCompressionSessionPrepareToEncodeFrames(made)
      session = made
      size = (width, height)
      encoder = "\(name), \(profile), \(bitrate) bps"
      return true
    }
    return false
  }

  /// Encodes the latest picture when one is wanted and it is new (or a key frame was asked for).
  func pump() {
    guard wanted > 0, !encoding, fresh, let picture = latest, let current = session else { return }
    let width = CVPixelBufferGetWidth(picture), height = CVPixelBufferGetHeight(picture)
    if (width, height) != size {
      if !makeSession(width, height) { return }
      forceKey = true
      return pump()
    }
    wanted -= 1
    encoding = true
    fresh = false
    let key = forceKey
    forceKey = false
    let ts = max(lastTs + 1, latestAt)
    lastTs = ts
    let properties = key ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue!] as CFDictionary : nil
    let status = VTCompressionSessionEncodeFrame(
      current, imageBuffer: picture, presentationTimeStamp: CMTime(value: ts, timescale: 1_000_000), duration: .invalid,
      frameProperties: properties, infoFlagsOut: nil
    ) { status, _, sample in
      self.queue.async { self.encoded(status, sample, ts, key) }
    }
    if status != noErr {
      encoding = false
      wanted += 1
      forceKey = forceKey || key
    }
  }

  func encoded(_ status: OSStatus, _ sample: CMSampleBuffer?, _ ts: Int64, _ asked: Bool) {
    encoding = false
    guard status == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample) else {
      // Dropped: still owed, and from a key frame if one was asked for.
      wanted += 1
      forceKey = forceKey || asked
      fresh = latest != nil
      return pump()
    }
    if let format = CMSampleBufferGetFormatDescription(sample),
      let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
      let avcC = atoms["avcC"] as? Data, avcC != lastConfig
    {
      lastConfig = avcC
      let dimensions = CMVideoFormatDescriptionGetDimensions(format)
      var config = Data()
      var w = UInt32(dimensions.width).bigEndian, h = UInt32(dimensions.height).bigEndian
      config.append(Data(bytes: &w, count: 4))
      config.append(Data(bytes: &h, count: 4))
      config.append(avcC)
      emit(2, config)
    }
    var key = true
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
      let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool
    {
      key = !notSync
    }
    let length = CMBlockBufferGetDataLength(block)
    var payload = Data(count: 9 + length)
    payload[0] = key ? 1 : 0
    var be = UInt64(ts).bigEndian
    payload.replaceSubrange(1..<9, with: Data(bytes: &be, count: 8))
    payload.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
      _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress! + 9)
    }
    emit(3, payload)
    pump()
  }

  // MARK: requests

  func next() {
    queue.async {
      self.wanted += 1
      self.pump()
    }
  }

  func keyframe() {
    queue.async {
      self.forceKey = true
      // The same picture again, as a key frame, when the screen does not change.
      if self.latest != nil { self.fresh = true }
      self.pump()
    }
  }
}

// MARK: - Input

let inputQueue = DispatchQueue(label: "fail.still.screen.input")
let source = CGEventSource(stateID: .hidSystemState)
var pointer = CGPoint(x: -1, y: -1)
var refusedTold = false

func point(_ x: Double, _ y: Double) -> CGPoint {
  let bounds = CGDisplayBounds(displayID)
  let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
  return CGPoint(x: bounds.minX + cx * (bounds.width - 1), y: bounds.minY + cy * (bounds.height - 1))
}

func post(_ event: CGEvent?, flags: UInt64) {
  guard let event else { return }
  event.flags = CGEventFlags(rawValue: flags)
  event.post(tap: .cghidEventTap)
}

func perform(_ op: [String: Any]) {
  if !inputAllowed() {
    if !refusedTold {
      refusedTold = true
      emitJSON(4, ["refused": "control"])
    }
    return
  }
  let flags = (op["flags"] as? NSNumber)?.uint64Value ?? 0
  switch op["op"] as? String {
  case "mouse":
    let at = point((op["x"] as? Double) ?? 0, (op["y"] as? Double) ?? 0)
    let button = (op["button"] as? Int) ?? 0
    let buttons = (op["buttons"] as? Int) ?? 0
    let cgButton: CGMouseButton = button == 2 ? .right : button == 1 ? .center : .left
    var type: CGEventType
    var held = cgButton
    switch op["type"] as? String {
    case "down": type = button == 2 ? .rightMouseDown : button == 1 ? .otherMouseDown : .leftMouseDown
    case "up": type = button == 2 ? .rightMouseUp : button == 1 ? .otherMouseUp : .leftMouseUp
    default:
      if buttons & 1 != 0 { type = .leftMouseDragged; held = .left }
      else if buttons & 2 != 0 { type = .rightMouseDragged; held = .right }
      else if buttons & 4 != 0 { type = .otherMouseDragged; held = .center }
      else { type = .mouseMoved }
    }
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: held)
    if let clicks = op["clicks"] as? Int, type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks)) }
    post(event, flags: flags)
    pointer = at
  case "scroll":
    let at = point((op["x"] as? Double) ?? 0, (op["y"] as? Double) ?? 0)
    // A wheel turns what is under the pointer: it goes there first.
    if at != pointer {
      post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left), flags: flags)
      pointer = at
    }
    let dx = Int32(((op["dx"] as? Double) ?? 0).rounded()), dy = Int32(((op["dy"] as? Double) ?? 0).rounded())
    // A page's deltas are positive down and right; a wheel's, up and left.
    let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0)
    event?.location = at
    post(event, flags: flags)
  case "key":
    let keycode = CGKeyCode((op["keycode"] as? Int) ?? 0)
    post(CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: (op["down"] as? Bool) ?? true), flags: flags)
  case "text":
    let units = Array(((op["text"] as? String) ?? "").utf16)
    // At most 20 UTF-16 units an event (what a keyboard event carries).
    var at = 0
    while at < units.count {
      var chunk = Array(units[at..<min(at + 20, units.count)])
      // A surrogate pair is not split.
      if chunk.count == 20, UTF16.isLeadSurrogate(chunk[19]) { chunk.removeLast() }
      for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
        post(event, flags: 0)
      }
      at += chunk.count
    }
  default:
    break
  }
}

// MARK: - Main

let view = View()

/// Messages from the station, until its end of stdin.
func readInput() {
  let stdin = FileHandle.standardInput
  func exactly(_ n: Int) -> Data? {
    var data = Data()
    while data.count < n {
      let more = stdin.readData(ofLength: n - data.count)
      if more.isEmpty { return nil }
      data.append(more)
    }
    return data
  }
  while let head = exactly(5) {
    let kind = head[0]
    let length = Int(head[1]) << 24 | Int(head[2]) << 16 | Int(head[3]) << 8 | Int(head[4])
    guard length <= 1 << 20, let payload = length == 0 ? Data() : exactly(length) else { break }
    switch kind {
    case 1: view.next()
    case 2: view.keyframe()
    case 3:
      if let op = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] { inputQueue.async { perform(op) } }
    default: break
    }
  }
  exit(0)
}

// The window server's connection, before ScreenCaptureKit is asked.
_ = NSApplication.shared
view.start()
Thread.detachNewThread(readInput)
dispatchMain()
