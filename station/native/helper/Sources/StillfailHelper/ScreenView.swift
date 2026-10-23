// A view of the display (`screen.view`, docs/remote-screens.md): ScreenCaptureKit captures it scaled into the view's
// bounds; VideoToolbox encodes H.264 on the hardware encoder (`codec: "h265"`: H.265 where this Mac encodes it, else
// H.264; `codec: "jpeg"`: Core Image each picture as a JPEG of quality 0.8), a picture only once one is asked for and
// only a new one (the screen changed) unless a key frame is asked for; CGEvent posts the input. While a view is open the display is kept on: opening one wakes a display gone to
// sleep (whose capture is black but for the cursor), and it does not go to sleep again until the view ends.
//
// After the request line the connection carries messages (Channel.swift) both ways:
//   in   1 next      (empty)  the next new picture, encoded
//        2 keyframe  (empty)  the next one a key frame, the screen changed or not
//        3 input     JSON     {op:"mouse", type:"move"|"down"|"up", x, y, button, buttons, clicks, flags},
//                             {op:"scroll", x, y, dx, dy, flags}, {op:"key", keycode, down, flags}, {op:"text", text};
//                             x, y are 0..1 of the display, flags CGEventFlags
//        4 clipboard 1 byte flags (bit 0: paste with ⌘V), 1 byte type (1 text, 2 PNG), the bytes: set (Clipboard.swift)
//        5 watch     1 byte       1: say each copy made on the Mac from now on (message 5 out), 0: stop
//        6 reveal    UTF-8        a file's path, shown selected in Finder
//        7 rate      4 bytes      bits a second (big-endian) to encode at from the next frame on (the link carries no
//                                 more: docs/remote-screens.md, "Pace")
//        8 bounds    JSON         {maxWidth, maxHeight}: the pictures from now on fitted into these (a config first)
//   out  1 info      JSON     first: {width, height, encoder, codec}, or {error, code: "capture"|"restart"|"display"|"encoder"}
//        2 config    4 bytes width, 4 bytes height, then the avcC or hvcC (none for JPEG): before the first frame and
//                             whenever it changes
//        3 frame     1 byte flags (bit 0: key frame), 8 bytes timestamp (µs), then the frame (AVCC or HVCC, or one JPEG)
//        4 event     JSON     {refused: "control"}: input was posted without the grant (macOS drops it)
//        5 clipboard 1 byte type (1 text, 2 PNG), the bytes: what was copied, while watched
//        6 cursor    JSON     {x, y, shape} (x, y 0..1 of the display; shape a CSS cursor's name) as it moves or
//                             changes: a video's pictures leave the pointer out (the client draws it, or shows its own in
//                             its shape); a JPEG's have it drawn in
// The view ends when the connection does. `synthetic: "moving"|"still"` encodes made-up pictures instead of capturing
// (the side test's measurement of the encoder and the link): never what a person sees.
import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import ImageIO
import CoreVideo
import Foundation
import IOKit.pwr_mgt
@preconcurrency import ScreenCaptureKit
import VideoToolbox

final class ScreenView: NSObject, SCStreamOutput, SCStreamDelegate {
  let channel: Channel
  let displayID: CGDirectDisplayID
  /// The view's bounds: as it opened, then as the station asks (`bounds`).
  var maxWidth: Int
  var maxHeight: Int
  let fps: Int
  /// The bit rate asked when the view opened, then as the station asks (`rate`); none: the picture's size's.
  var bitrate: Int?
  let synthetic: String?
  /// "h264", "h265" (H.264 where this Mac has no encoder of it), or "jpeg": each picture a JPEG of its own (an agent's
  /// view, a client without either).
  let jpeg: Bool
  let hevc: Bool
  /// What the session encodes: "h264", "h265", or "jpeg".
  var codec = "h264"
  lazy var images = CIContext(options: [.useSoftwareRenderer: false])
  /// Everything below happens on this queue.
  let queue = DispatchQueue(label: "fail.still.helper.screen", qos: .userInteractive)
  let input: ScreenInput
  lazy var clipboard = Clipboard(channel: channel, input: input)
  var stream: SCStream?
  var configuration: SCStreamConfiguration?
  /// The made-up pictures' size (`synthetic`), as the bounds have it.
  var syntheticSize = (0, 0)
  var timer: DispatchSourceTimer?
  /// Where the pointer is and its shape, looked at 60 times a second (on the main thread, as AppKit has it); the last said.
  var cursorTimer: DispatchSourceTimer?
  var cursorSaid: [String: Any] = [:]
  var cursorTicks = 0
  var cursorShape = "default"
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
  var ended = false
  /// Keeps the display on while the view is open (0: none held).
  var awake: IOPMAssertionID = 0

  init(channel: Channel, options: [String: Any]) {
    self.channel = channel
    displayID = (options["display"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    maxWidth = max(16, (options["maxWidth"] as? Int) ?? 1920)
    maxHeight = max(16, (options["maxHeight"] as? Int) ?? 1080)
    fps = min(120, max(1, (options["fps"] as? Int) ?? 60))
    bitrate = options["bitrate"] as? Int
    synthetic = options["synthetic"] as? String
    jpeg = (options["codec"] as? String) == "jpeg"
    hevc = (options["codec"] as? String) == "h265"
    input = ScreenInput(channel: channel, displayID: displayID)
  }

  /// Until the connection ends: the capture started, the station's asks answered.
  func run() {
    start()
    // A picture on the clipboard is the largest message.
    while let (kind, payload) = channel.message(limit: 2 + Clipboard.pngMax) {
      switch kind {
      case 1: next()
      case 2: keyframe()
      case 3:
        if let op = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] { input.post(op) }
      case 4: clipboard.set(payload)
      case 5: clipboard.watch(payload)
      case 6: clipboard.reveal(payload)
      case 8:
        if let b = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any], let w = b["maxWidth"] as? Int, let h = b["maxHeight"] as? Int {
          bounds(w, h)
        }
      case 7: if payload.count == 4 { rate(Int(payload.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) })) }
      default: break
      }
    }
    clipboard.stop()
    stop()
  }

  /// The source's size fitted into the view's bounds, never larger, in even pixels (what 4:2:0 encodes).
  func fitted(_ width: Int, _ height: Int) -> (Int, Int) {
    let scale = min(1.0, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
    let even = { (v: Double) in max(2, Int(v.rounded()) & ~1) }
    return (even(Double(width) * scale), even(Double(height) * scale))
  }

  // MARK: capture

  func start() {
    let display = Status.display(displayID)
    let (width, height) = fitted(display["width"] as! Int, display["height"] as! Int)
    if let mode = synthetic {
      startSynthetic(width, height, moving: mode != "still")
      return
    }
    wake()
    let started = DispatchSemaphore(value: 0)
    Task {
      defer { started.signal() }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shown = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
          channel.sendJSON(1, ["error": "no display to capture", "code": "display"])
          return
        }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.queueDepth = 5
        // In a JPEG (an agent's view: the pointer is part of what it sees); a video's pointer goes as message 6.
        configuration.showsCursor = jpeg
        let stream = SCStream(filter: SCContentFilter(display: shown, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.sync {
          self.stream = stream
          self.configuration = configuration
          self.opened(width, height)
          if !self.jpeg { self.followCursor() }
        }
      } catch {
        channel.sendJSON(1, ["error": error.localizedDescription, "code": "capture", "capture": CGPreflightScreenCaptureAccess()])
      }
    }
    started.wait()
  }

  func opened(_ width: Int, _ height: Int) {
    if jpeg {
      encoder = "JPEG, quality 0.8"
      codec = "jpeg"
      channel.sendJSON(1, ["width": width, "height": height, "encoder": encoder, "codec": codec])
      return pump()
    }
    if !makeSession(width, height) {
      channel.sendJSON(1, ["error": "no H.264 encoder", "code": "encoder"])
      return
    }
    channel.sendJSON(1, ["width": width, "height": height, "encoder": encoder, "codec": codec])
    pump()
  }

  func stop() {
    queue.sync {
      ended = true
      timer?.cancel()
      timer = nil
      cursorTimer?.cancel()
      cursorTimer = nil
      if let session { VTCompressionSessionInvalidate(session) }
      session = nil
      latest = nil
    }
    if let stream {
      let done = DispatchSemaphore(value: 0)
      stream.stopCapture { _ in done.signal() }
      _ = done.wait(timeout: .now() + 2)
    }
    if awake != 0 {
      IOPMAssertionRelease(awake)
      awake = 0
    }
  }

  /// The display woken (as a person touching the Mac does) and kept on until the view ends: a display asleep is
  /// captured black.
  func wake() {
    let reason = "A still.fail view of this screen is open" as CFString
    var activity: IOPMAssertionID = 0
    IOPMAssertionDeclareUserActivity(reason, kIOPMUserActiveLocal, &activity)
    IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &awake)
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
    // Only a picture that is new: an idle one says the screen did not change.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete
    {
      return
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    took(buffer, pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000) : now())
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    channel.sendJSON(4, ["stopped": error.localizedDescription])
    shutdown(channel.fd, SHUT_RDWR)
  }

  /// A new picture: kept as the latest, encoded once one is wanted.
  func took(_ buffer: CVPixelBuffer, _ at: Int64) {
    if ended { return }
    latest = buffer
    latestAt = at
    fresh = true
    pump()
  }

  func startSynthetic(_ width: Int, _ height: Int, moving: Bool) {
    queue.sync {
      self.opened(width, height)
      self.took(self.picture(width, height), self.now())
      guard moving else { return }
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps))
      self.syntheticSize = (width, height)
      timer.setEventHandler { self.took(self.picture(self.syntheticSize.0, self.syntheticSize.1), self.now()) }
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
    // Hardware with low-latency rate control first (frames come out as they go in), then hardware, then any; H.265
    // (asked for) on the hardware only, H.264 where it is not had (a codec's settings once it is kept: one size's
    // session made anew keeps the codec it had).
    let lowLatency: [CFString: Any] = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true, kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
    let hardware: [CFString: Any] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
    let h265 = hevc && (encoder.isEmpty || codec == "h265")
    var tries: [(String, String, [CFString: Any])] = []
    if h265 { tries += [("h265", "hardware, low latency", lowLatency), ("h265", "hardware", hardware)] }
    tries += [("h264", "hardware, low latency", lowLatency), ("h264", "hardware", hardware), ("h264", "software", [:])]
    for (kind, name, specification) in tries {
      var made: VTCompressionSession?
      let status = VTCompressionSessionCreate(
        allocator: nil, width: Int32(width), height: Int32(height), codecType: kind == "h265" ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
        encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
        outputCallback: nil, refcon: nil, compressionSessionOut: &made)
      guard status == noErr, let made else { continue }
      let set = { (key: CFString, value: Any) in VTSessionSetProperty(made, key: key, value: value as CFTypeRef) }
      _ = set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue!)
      _ = set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse!)
      // H.264: Baseline, as every decoder takes it (constrained where the system has it); Main if neither is taken.
      // H.265: Main.
      var profile = "default"
      let profiles = kind == "h265" ? [kVTProfileLevel_HEVC_Main_AutoLevel] : [kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel, kVTProfileLevel_H264_Baseline_AutoLevel, kVTProfileLevel_H264_Main_AutoLevel]
      for p in profiles
      where set(kVTCompressionPropertyKey_ProfileLevel, p) == noErr {
        profile = p as String
        break
      }
      let rate = bitrate ?? max(1_000_000, width * height * 3)
      _ = set(kVTCompressionPropertyKey_AverageBitRate, rate)
      _ = set(kVTCompressionPropertyKey_ExpectedFrameRate, fps)
      // A key frame when asked for, and at least every 10 s besides.
      _ = set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 10)
      VTCompressionSessionPrepareToEncodeFrames(made)
      session = made
      size = (width, height)
      codec = kind
      encoder = "\(name), \(profile), \(rate) bps"
      return true
    }
    return false
  }

  /// Encodes the latest picture when one is wanted and it is new (or a key frame was asked for).
  func pump() {
    if jpeg { return pumpJPEG() }
    guard !ended, wanted > 0, !encoding, fresh, let picture = latest, let current = session else { return }
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
    if ended { return }
    guard status == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample) else {
      // Dropped: still owed, and from a key frame if one was asked for.
      wanted += 1
      forceKey = forceKey || asked
      fresh = latest != nil
      return pump()
    }
    if let format = CMSampleBufferGetFormatDescription(sample),
      let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
      let avcC = atoms[codec == "h265" ? "hvcC" : "avcC"] as? Data, avcC != lastConfig
    {
      lastConfig = avcC
      let dimensions = CMVideoFormatDescriptionGetDimensions(format)
      var config = Data()
      var w = UInt32(dimensions.width).bigEndian, h = UInt32(dimensions.height).bigEndian
      config.append(Data(bytes: &w, count: 4))
      config.append(Data(bytes: &h, count: 4))
      config.append(avcC)
      channel.send(2, config)
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
    channel.send(3, payload)
    pump()
  }

  /// The latest picture as one JPEG, when one is wanted and it is new (or a key frame was asked for: every one is).
  func pumpJPEG() {
    guard !ended, wanted > 0, fresh, let picture = latest else { return }
    wanted -= 1
    fresh = false
    forceKey = false
    let width = CVPixelBufferGetWidth(picture), height = CVPixelBufferGetHeight(picture)
    if (width, height) != size {
      size = (width, height)
      var config = Data()
      var w = UInt32(width).bigEndian, h = UInt32(height).bigEndian
      config.append(Data(bytes: &w, count: 4))
      config.append(Data(bytes: &h, count: 4))
      channel.send(2, config)
    }
    let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
    guard let data = images.jpegRepresentation(of: CIImage(cvPixelBuffer: picture), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [quality: 0.8]) else {
      wanted += 1
      return
    }
    let ts = max(lastTs + 1, latestAt)
    lastTs = ts
    var payload = Data([1])
    var be = UInt64(ts).bigEndian
    payload.append(Data(bytes: &be, count: 8))
    payload.append(data)
    channel.send(3, payload)
    pumpJPEG()
  }

  // MARK: asks

  func next() {
    queue.async {
      self.wanted += 1
      self.pump()
    }
  }

  /// The pointer said (message 6) as it moves or changes shape, while the view lasts: where it is on the display (0..1),
  /// and its shape as CSS names it (the standard cursors; any other "default"). A shape is looked at 10 times a second.
  func followCursor() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(16))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      MainActor.assumeIsolated {
        guard let at = CGEvent(source: nil)?.location else { return }
        let b = CGDisplayBounds(self.displayID)
        guard b.width > 0, b.height > 0 else { return }
        if self.cursorTicks % 6 == 0 { self.cursorShape = CursorShapes.name(of: NSCursor.currentSystem) }
        self.cursorTicks += 1
        let x = min(1, max(0, (at.x - b.minX) / b.width)), y = min(1, max(0, (at.y - b.minY) / b.height))
        let said: [String: Any] = ["x": (x * 10000).rounded() / 10000, "y": (y * 10000).rounded() / 10000, "shape": self.cursorShape]
        if NSDictionary(dictionary: said).isEqual(to: self.cursorSaid) { return }
        self.cursorSaid = said
        self.channel.sendJSON(6, said)
      }
    }
    timer.resume()
    cursorTimer = timer
  }

  /// The pictures from now on fitted into `width`×`height`: the capture asked for the new size (its next picture is
  /// that size, and the encoder is made anew for it, from a key frame).
  func bounds(_ width: Int, _ height: Int) {
    queue.async {
      self.maxWidth = max(16, width)
      self.maxHeight = max(16, height)
      let display = Status.display(self.displayID)
      let (w, h) = self.fitted(display["width"] as! Int, display["height"] as! Int)
      if self.synthetic != nil {
        self.syntheticSize = (w, h)
        return
      }
      guard let stream = self.stream, let configuration = self.configuration else { return }
      if configuration.width == w && configuration.height == h { return }
      configuration.width = w
      configuration.height = h
      stream.updateConfiguration(configuration) { error in
        if let error { self.channel.sendJSON(4, ["bounds": error.localizedDescription]) }
      }
    }
  }

  /// From the next frame on, about this many bits a second.
  func rate(_ bits: Int) {
    queue.async {
      self.bitrate = max(100_000, bits)
      if let session = self.session {
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: self.bitrate! as CFTypeRef)
      }
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

/// The system's standard cursors by the CSS names a client shows them with, told apart by their hot spots and pixels
/// (an NSCursor is made anew each time it is asked for: the same object it never is). One not told apart (a picture
/// macOS draws itself, an app's own) is "default".
@MainActor
enum CursorShapes {
  struct Look: Equatable {
    let hotSpot: NSPoint
    let pixels: Data
  }

  static func look(_ cursor: NSCursor) -> Look? {
    guard let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = image.dataProvider?.data else { return nil }
    return Look(hotSpot: cursor.hotSpot, pixels: data as Data)
  }

  static let known: [(Look, String)] = [
    (NSCursor.iBeam, "text"), (NSCursor.pointingHand, "pointer"), (NSCursor.resizeLeftRight, "ew-resize"),
    (NSCursor.resizeUpDown, "ns-resize"), (NSCursor.crosshair, "crosshair"), (NSCursor.openHand, "grab"),
    (NSCursor.closedHand, "grabbing"), (NSCursor.operationNotAllowed, "not-allowed"),
    (NSCursor.iBeamCursorForVerticalLayout, "vertical-text"), (NSCursor.arrow, "default"),
  ].compactMap { cursor, name in look(cursor).map { ($0, name) } }

  static func name(of cursor: NSCursor?) -> String {
    guard let cursor, let seen = look(cursor) else { return "default" }
    return known.first { $0.0 == seen }?.1 ?? "default"
  }
}
