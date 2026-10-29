// The Mac's system output for a view that asks for it (`screen.view` with `audio: true`, docs/remote-screens.md,
// "System audio"): ScreenCaptureKit's audio of the display's stream (every app's sound but this helper's own; never the
// microphone), 48 kHz stereo, made into 20 ms packets of interleaved PCM16 as Windows' stillfail-screen makes them
// (native/screen/src/audio.rs). Nothing more of macOS's than Screen Recording, which the view has already.
//
// Pulled as the station's transport takes them: message 9 in asks for one packet, sent as message 9 out once one is
// there (8 bytes timestamp, µs of the capture clock the video's frames have, then 3840 bytes); at most 300 ms is kept,
// the oldest dropped first. Message 8 out says the format once the capture is set up.
@preconcurrency import ScreenCaptureKit
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

  init(channel: Channel) {
    self.channel = channel
  }

  /// The format the packets are in (message 8), said before the first.
  func said() {
    channel.sendJSON(8, ["codec": "pcm_s16le", "sampleRate": SystemAudio.rate, "channels": SystemAudio.channels])
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

  private func flush() {
    guard wanted, let (ts, data) = packets.pop() else { return }
    wanted = false
    var payload = Data(count: 8)
    var be = UInt64(max(0, ts)).bigEndian
    payload.replaceSubrange(0..<8, with: Data(bytes: &be, count: 8))
    payload.append(data)
    channel.send(9, payload)
  }

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

/// Interleaved stereo PCM16 as it comes, made into packets of exactly 960 frames (20 ms), each with the capture time of
/// its first frame; at most 15 kept (300 ms), the oldest dropped first. Sound that does not follow on from the last (a
/// gap, as ScreenCaptureKit sends nothing while nothing plays) starts a packet of its own: the part made before it is
/// dropped, not joined to it under a time it was not captured at.
struct AudioPackets {
  static let frames = 960
  static let bytes = frames * 4
  static let kept = 15
  /// How far from where the last sound ended new sound may start and still follow on (µs).
  static let slack: Int64 = 5_000

  private var building: [Int16] = []
  private var buildingAt: Int64 = 0
  /// Where the last sound added ends (µs); nil before any.
  private var end: Int64?
  private(set) var queued: [(Int64, Data)] = []

  /// `pcm` (interleaved stereo) captured from `at` (µs) on.
  mutating func add(_ pcm: [Int16], at: Int64) {
    let count = pcm.count / 2
    if let end, abs(at - end) > AudioPackets.slack { building.removeAll(keepingCapacity: true) }
    end = at + Int64(count) * 1_000_000 / Int64(SystemAudio.rate)
    var frame = 0
    while frame < count {
      if building.isEmpty { buildingAt = at + Int64(frame) * 1_000_000 / Int64(SystemAudio.rate) }
      let take = min(count - frame, AudioPackets.frames - building.count / 2)
      building.append(contentsOf: pcm[(frame * 2)..<((frame + take) * 2)])
      frame += take
      if building.count == AudioPackets.frames * 2 {
        let data = building.withUnsafeBufferPointer { b in Data(buffer: UnsafeBufferPointer(start: b.baseAddress, count: b.count)) }
        // Little-endian on every Mac this runs on (arm64, x86_64): the bytes as they are.
        if queued.count == AudioPackets.kept { queued.removeFirst() }
        queued.append((buildingAt, data))
        building.removeAll(keepingCapacity: true)
      }
    }
  }

  mutating func pop() -> (Int64, Data)? {
    queued.isEmpty ? nil : queued.removeFirst()
  }
}
