// The Mac's system output for a view that asks for it (`screen.view` with `audio: true`, docs/remote-screens.md,
// "System audio"): ScreenCaptureKit's audio of the display's stream (every app's sound but this helper's own; never the
// microphone), 48 kHz stereo, made into 20 ms packets of interleaved PCM16 as Windows' stillfail-screen makes them
// (native/screen/src/audio.rs). Nothing more of macOS's than Screen Recording, which the view has already.
//
// Pulled as the station's transport takes them: message 9 in asks for one packet, sent as message 9 out once one is
// there (8 bytes timestamp, µs of the capture clock the video's frames have, then 3840 bytes, or one Opus packet of
// those 20 ms for a view that asked `audioCodec: "opus"`: about 64 kbit/s, a twentieth of PCM's, by AudioToolbox's own
// encoder); at most 300 ms is kept, the oldest dropped first. Message 8 out says the format once the capture is set up.
@preconcurrency import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Foundation

final class SystemAudio: NSObject, SCStreamOutput {
  static let rate = 48_000
  static let channels = 2

  let channel: Channel
  /// Everything below happens on this queue (ScreenCaptureKit's audio comes on it too).
  let queue = DispatchQueue(label: "fail.still.helper.audio", qos: .userInteractive)
  private var packets = AudioPackets()
  /// A packet asked for and not sent yet.
  private var wanted = false
  /// A format it cannot take was said (an error, message 8): nothing more.
  private var refused = false

  /// What makes each packet Opus, for a view that asked it; nil: PCM16 (not asked, or this Mac encodes none).
  let encoder: OpusPackets?

  init(channel: Channel, opus: Bool = false) {
    self.channel = channel
    encoder = opus ? OpusPackets() : nil
  }

  /// The format the packets are in (message 8), said before the first.
  func said() {
    channel.sendJSON(8, ["codec": encoder == nil ? "pcm_s16le" : "opus", "sampleRate": SystemAudio.rate, "channels": SystemAudio.channels])
  }

  /// One packet asked for (message 9 in): sent now when one is kept, else as one is made.
  func next() {
    queue.async {
      self.wanted = true
      self.flush()
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .audio, !refused, sample.isValid, let format = CMSampleBufferGetFormatDescription(sample),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
    else { return }
    guard Int(asbd.mSampleRate) == SystemAudio.rate, let pcm = SystemAudio.stereo(sample, asbd) else {
      refused = true
      channel.sendJSON(8, ["error": "system audio in a format not taken: \(asbd.mSampleRate) Hz, flags \(asbd.mFormatFlags), \(asbd.mBitsPerChannel) bits"])
      return
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    let at = pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000) : Int64(DispatchTime.now().uptimeNanoseconds / 1000)
    packets.add(pcm, at: at)
    flush()
  }

  /// Sound captured from `at` (µs on the capture's clock), as a capture's handler takes it (on the queue).
  func took(_ pcm: [Int16], at: Int64) {
    queue.async {
      self.packets.add(pcm, at: at)
      self.flush()
    }
  }

  /// Made-up sound (a view's `synthetic`): 440 Hz and 1250 Hz on the left, 660 Hz on the right, a packet each 20 ms on
  /// `now`'s clock (µs), as the capture's would come, until the view goes.
  func tone(now: @escaping () -> Int64) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    var at = 0
    timer.schedule(deadline: .now(), repeating: .milliseconds(20))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      var pcm = [Int16](repeating: 0, count: AudioPackets.frames * 2)
      for i in 0..<AudioPackets.frames {
        let t = Double(at + i) / Double(SystemAudio.rate)
        pcm[i * 2] = Int16((sin(2 * .pi * 440 * t) * 0.3 + sin(2 * .pi * 1250 * t) * 0.1) * 32767)
        pcm[i * 2 + 1] = Int16(sin(2 * .pi * 660 * t) * 0.3 * 32767)
      }
      at += AudioPackets.frames
      self.packets.add(pcm, at: now())
      self.flush()
    }
    timer.resume()
    toneTimer = timer
  }
  private var toneTimer: DispatchSourceTimer?

  /// The view went: no more made-up sound.
  func end() {
    queue.sync {
      toneTimer?.cancel()
      toneTimer = nil
    }
  }

  private func flush() {
    while wanted, let (ts, pcm) = packets.pop() {
      // Digital silence (an app holding its output open with nothing playing; ScreenCaptureKit itself sends nothing
      // then) is not sent once it has lasted `quiet` packets: as PCM it was 1.5 Mbit/s of zeros, as Opus 3-byte packets.
      // Shorter (between two sounds, between a voice's words) it goes as any sound does. The sound after it starts anew.
      if pcm.allSatisfy({ $0 == 0 }) {
        zeros += 1
        if zeros >= SystemAudio.quiet {
          sentEnd = nil
          continue
        }
      } else {
        zeros = 0
      }
      var data = pcm
      if let encoder {
        // After a gap (silence left out, sound that does not follow on) the encoder starts anew, as the client's
        // decoder does (client/shell ScreenTap): neither carries the sound before the gap into the packet after it.
        if let end = sentEnd, abs(ts - end) <= AudioPackets.slack {} else { encoder.reset() }
        // (one in, one out: a packet the encoder gives nothing for is none to send; the next is)
        guard let encoded = encoder.encode(pcm) else { return }
        data = encoded
      }
      wanted = false
      sentEnd = ts + AudioPackets.micros(Int64(AudioPackets.frames))
      var payload = Data(count: 8)
      var be = UInt64(max(0, ts)).bigEndian
      payload.replaceSubrange(0..<8, with: Data(bytes: &be, count: 8))
      payload.append(data)
      channel.send(9, payload)
    }
  }
  /// Packets of digital silence in a row so far; how many make silence that is not sent (200 ms).
  private var zeros = 0
  static let quiet = 10
  /// Where the sound last sent ends (µs of the capture clock); nil before any, and after silence left out.
  private var sentEnd: Int64?

  /// A sample buffer's PCM as interleaved stereo PCM16: 32-bit float or 16-bit integer samples, interleaved or not;
  /// one channel given to both sides, past two the first two. Nil in any other format.
  static func stereo(_ sample: CMSampleBuffer, _ asbd: AudioStreamBasicDescription) -> [Int16]? {
    let frames = CMSampleBufferGetNumSamples(sample)
    let channels = Int(asbd.mChannelsPerFrame)
    guard frames > 0, channels > 0 else { return [] }
    let float = asbd.mFormatID == kAudioFormatLinearPCM && asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 && asbd.mBitsPerChannel == 32
    let int16 = asbd.mFormatID == kAudioFormatLinearPCM && asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && asbd.mBitsPerChannel == 16
      && asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
    guard float || int16 else { return nil }
    let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
    var needed = 0
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sample, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr
    else { return nil }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    var block: CMBlockBuffer?
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sample, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block) == noErr
    else { return nil }
    let buffers = UnsafeMutableAudioBufferListPointer(list).map { UnsafeRawBufferPointer(start: $0.mData, count: Int($0.mDataByteSize)) }
    return interleave(buffers, frames: frames, channels: channels, planar: planar, float: float)
  }

  /// `frames` frames of `channels` channels (each a buffer of its own when `planar`, else together in the first) as
  /// interleaved stereo PCM16; a buffer too short is silence where it ends.
  static func interleave(_ buffers: [UnsafeRawBufferPointer], frames: Int, channels: Int, planar: Bool, float: Bool) -> [Int16] {
    let width = float ? 4 : 2
    func value(_ channel: Int, _ frame: Int) -> Int16 {
      let (buffer, index) = planar ? (channel < buffers.count ? buffers[channel] : nil, frame) : (buffers.first, frame * channels + channel)
      guard let buffer, let base = buffer.baseAddress, (index + 1) * width <= buffer.count else { return 0 }
      if !float { return base.loadUnaligned(fromByteOffset: index * 2, as: Int16.self) }
      let v = base.loadUnaligned(fromByteOffset: index * 4, as: Float32.self)
      return v.isFinite ? Int16((min(1, max(-1, v)) * 32767).rounded()) : 0
    }
    var out = [Int16](repeating: 0, count: frames * 2)
    let right = min(1, channels - 1)
    for frame in 0..<frames {
      out[frame * 2] = value(0, frame)
      out[frame * 2 + 1] = value(right, frame)
    }
    return out
  }
}

/// Interleaved stereo PCM16 as it comes, made into packets of exactly 960 frames (20 ms); at most 15 kept (300 ms), the
/// oldest dropped first. Sound that follows on from the sound before it is one run: a buffer follows on when its said
/// time is within `slack` of where the run's frames say it starts. A packet's time is where it starts in its run by the
/// frames before it, from the run's start, which each buffer draws a 64th of the way to its said time: so neither the
/// said times' jitter nor the two clocks' drift (the capture's host time, the sound card's frames: tens of ppm apart)
/// moves packets off by more than a fraction of a millisecond, and the run never breaks for drift. Sound that does not
/// follow on (a gap, as ScreenCaptureKit sends nothing while nothing plays) starts a run of its own: the part made before
/// it is dropped, not joined to it under a time it was not captured at.
struct AudioPackets {
  static let frames = 960
  static let bytes = frames * 4
  static let kept = 15
  /// How far from where the run's frames say it starts a buffer's said time may be and still follow on (µs): half a
  /// packet, more than a capture's said time jitters, less than any gap.
  static let slack: Int64 = 10_000

  private var building: [Int16] = []
  /// The run: when it started (µs, drawn to the buffers' said times), the frames that came in it, those of them in
  /// packets made; nil before any.
  private var runAt: Int64?
  private var runFrames: Int64 = 0
  private var made: Int64 = 0
  /// How many runs there have been.
  private(set) var runs = 0
  private(set) var queued: [(Int64, Data)] = []

  static func micros(_ frames: Int64) -> Int64 { frames * 1_000_000 / Int64(SystemAudio.rate) }

  /// `pcm` (interleaved stereo) captured from `at` (µs) on.
  mutating func add(_ pcm: [Int16], at: Int64) {
    let count = pcm.count / 2
    if let start = runAt, abs(at - (start + AudioPackets.micros(runFrames))) <= AudioPackets.slack {
      runAt = start + (at - (start + AudioPackets.micros(runFrames))) / 64
    } else {
      building.removeAll(keepingCapacity: true)
      runAt = at
      runFrames = 0
      made = 0
      runs += 1
    }
    let start = runAt!
    var frame = 0
    while frame < count {
      let take = min(count - frame, AudioPackets.frames - building.count / 2)
      building.append(contentsOf: pcm[(frame * 2)..<((frame + take) * 2)])
      frame += take
      if building.count == AudioPackets.frames * 2 {
        let data = building.withUnsafeBufferPointer { b in Data(buffer: UnsafeBufferPointer(start: b.baseAddress, count: b.count)) }
        // Little-endian on every Mac this runs on (arm64, x86_64): the bytes as they are.
        if queued.count == AudioPackets.kept { queued.removeFirst() }
        queued.append((start + AudioPackets.micros(made), data))
        made += Int64(AudioPackets.frames)
        building.removeAll(keepingCapacity: true)
      }
    }
    runFrames += Int64(count)
  }

  mutating func pop() -> (Int64, Data)? {
    queued.isEmpty ? nil : queued.removeFirst()
  }
}

/// 20 ms packets of interleaved stereo PCM16 at 48 kHz made into Opus packets of the same 20 ms (RFC 6716), one for
/// one, by AudioToolbox's encoder at `bitrate`. Nil where this Mac has no such encoder. Used on SystemAudio's queue alone.
final class OpusPackets {
  static let bitrate = 64_000

  private let converter: AVAudioConverter
  private let input: AVAudioPCMBuffer
  private let format: AVAudioFormat

  init?() {
    guard let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(SystemAudio.rate), channels: AVAudioChannelCount(SystemAudio.channels), interleaved: true),
      let input = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(AudioPackets.frames))
    else { return nil }
    var opus = AudioStreamBasicDescription(
      mSampleRate: Double(SystemAudio.rate), mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
      mFramesPerPacket: UInt32(AudioPackets.frames), mBytesPerFrame: 0, mChannelsPerFrame: UInt32(SystemAudio.channels),
      mBitsPerChannel: 0, mReserved: 0)
    guard let format = AVAudioFormat(streamDescription: &opus), let converter = AVAudioConverter(from: pcm, to: format) else { return nil }
    converter.bitRate = OpusPackets.bitrate
    self.converter = converter
    self.input = input
    self.format = format
  }

  /// The next packet starts the sound anew (after a gap): nothing of the sound before it is carried into it.
  func reset() {
    converter.reset()
    resets += 1
  }
  /// How many times it started anew.
  private(set) var resets = 0

  /// One packet's PCM (3840 bytes) as one Opus packet; nil when the encoder gave none for it.
  func encode(_ pcm: Data) -> Data? {
    guard pcm.count == AudioPackets.bytes, let samples = input.int16ChannelData?[0] else { return nil }
    pcm.withUnsafeBytes { raw in _ = raw.copyBytes(to: UnsafeMutableRawBufferPointer(start: samples, count: AudioPackets.bytes)) }
    input.frameLength = AVAudioFrameCount(AudioPackets.frames)
    let out = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: max(1, converter.maximumOutputPacketSize))
    var given = false
    var error: NSError?
    let status = converter.convert(to: out, error: &error) { _, said in
      if given {
        said.pointee = .noDataNow
        return nil
      }
      given = true
      said.pointee = .haveData
      return self.input
    }
    guard status != .error, error == nil, out.packetCount == 1, out.byteLength > 0 else { return nil }
    return Data(bytes: out.data, count: Int(out.byteLength))
  }
}
