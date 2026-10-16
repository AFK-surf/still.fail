// A view of the display (`screen.view`, docs/remote-screens.md): ScreenCaptureKit captures it scaled into the view's
// bounds; VideoToolbox encodes H.264 on the hardware encoder (or, `codec: "jpeg"`, Core Image each picture as a JPEG
// of quality 0.8), a picture only once one is asked for and only a new one (the screen changed) unless a key frame is
// asked for; CGEvent posts the input.
//
// After the request line the connection carries messages (Channel.swift) both ways:
//   in   1 next      (empty)  the next new picture, encoded
//        2 keyframe  (empty)  the next one a key frame, the screen changed or not
//        3 input     JSON     {op:"mouse", type:"move"|"down"|"up", x, y, button, buttons, clicks, flags},
//                             {op:"scroll", x, y, dx, dy, flags}, {op:"key", keycode, down, flags}, {op:"text", text};
//                             x, y are 0..1 of the display, flags CGEventFlags
//   out  1 info      JSON     first: {width, height, encoder}, or {error, code: "capture"|"restart"|"display"|"encoder"}
//        2 config    4 bytes width, 4 bytes height, then the avcC (none for JPEG): before the first frame and whenever
//                             it changes
//        3 frame     1 byte flags (bit 0: key frame), 8 bytes timestamp (µs), then the frame (AVCC, or one JPEG)
//        4 event     JSON     {refused: "control"}: input was posted without the grant (macOS drops it)
// The view ends when the connection does. `synthetic: "moving"|"still"` encodes made-up pictures instead of capturing
// (the side test's measurement of the encoder and the link): never what a person sees.
import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import ImageIO
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

final class ScreenView: NSObject, SCStreamOutput, SCStreamDelegate {
  let channel: Channel
  let displayID: CGDirectDisplayID
  let maxWidth: Int
  let maxHeight: Int
  let fps: Int
  let bitrate: Int?
  let synthetic: String?
  /// "h264", or "jpeg": each picture a JPEG of its own (an agent's view, a client without H.264).
  let jpeg: Bool
  lazy var images = CIContext(options: [.useSoftwareRenderer: false])
  /// Everything below happens on this queue.
  let queue = DispatchQueue(label: "fail.still.helper.screen", qos: .userInteractive)
  let input: ScreenInput
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
  var ended = false

  init(channel: Channel, options: [String: Any]) {
    self.channel = channel
    displayID = (options["display"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    maxWidth = max(16, (options["maxWidth"] as? Int) ?? 1920)
    maxHeight = max(16, (options["maxHeight"] as? Int) ?? 1080)
    fps = min(120, max(1, (options["fps"] as? Int) ?? 60))
    bitrate = options["bitrate"] as? Int
    synthetic = options["synthetic"] as? String
    jpeg = (options["codec"] as? String) == "jpeg"
    input = ScreenInput(channel: channel, displayID: displayID)
  }

  /// Until the connection ends: the capture started, the station's asks answered.
  func run() {
    start()
    while let (kind, payload) = channel.message() {
      switch kind {
      case 1: next()
      case 2: keyframe()
      case 3:
        if let op = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] { input.post(op) }
      default: break
      }
    }
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
        configuration.showsCursor = true
        let stream = SCStream(filter: SCContentFilter(display: shown, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.sync {
          self.stream = stream
          self.opened(width, height)
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
      channel.sendJSON(1, ["width": width, "height": height, "encoder": encoder])
      return pump()
    }
    if !makeSession(width, height) {
      channel.sendJSON(1, ["error": "no H.264 encoder", "code": "encoder"])
      return
    }
    channel.sendJSON(1, ["width": width, "height": height, "encoder": encoder])
    pump()
  }

  func stop() {
    queue.sync {
      ended = true
      timer?.cancel()
      timer = nil
      if let session { VTCompressionSessionInvalidate(session) }
      session = nil
      latest = nil
    }
    if let stream {
      let done = DispatchSemaphore(value: 0)
      stream.stopCapture { _ in done.signal() }
      _ = done.wait(timeout: .now() + 2)
    }
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
      var profile = "default"
      for p in [kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel, kVTProfileLevel_H264_Baseline_AutoLevel, kVTProfileLevel_H264_Main_AutoLevel]
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
      let avcC = atoms["avcC"] as? Data, avcC != lastConfig
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

  func keyframe() {
    queue.async {
      self.forceKey = true
      // The same picture again, as a key frame, when the screen does not change.
      if self.latest != nil { self.fresh = true }
      self.pump()
    }
  }
}
