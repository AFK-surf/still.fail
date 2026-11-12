import Foundation
import Testing
@testable import StillfailHelper

/// 512 frames (as ScreenCaptureKit's buffers often are) of a tone, the n-th of them.
private func buffer(_ n: Int, silent: Bool = false) -> [Int16] {
  (0..<512).flatMap { i -> [Int16] in
    let v = silent ? 0 : Int16(sin(Double(n * 512 + i) * 2 * .pi * 440 / 48_000) * 8000)
    return [v, v]
  }
}

/// The said time of buffer n, jittered as a capture's clock may say it (±3 ms, now and then ±8).
private func said(_ n: Int, from base: Int64 = 1_000_000) -> Int64 {
  let jitter: [Int64] = [0, 3_000, -3_000, 1_000, -2_000, 8_000, -8_000, 2_000, -1_000, 3_000]
  return base + Int64(n) * 512 * 1_000_000 / 48_000 + jitter[n % jitter.count]
}

/// What a packet is said to start at against when its first frame was captured: ten minutes of 512-frame buffers whose
/// said times run `ppm` fast (or slow) against the frames, and jitter as `said` does.
private func drifted(_ ppm: Double) -> (runs: Int, packets: Int, worst: Int64) {
  var packets = AudioPackets()
  let buffers = 10 * 60 * 48_000 / 512
  let jitter: [Int64] = [0, 3_000, -3_000, 1_000, -2_000, 8_000, -8_000, 2_000, -1_000, 3_000]
  // the capture's clock at frame f
  let clock = { (f: Int) -> Double in 1_000_000 + Double(f) * 1_000_000 / 48_000 * (1 + ppm / 1_000_000) }
  var count = 0, worst: Int64 = 0
  let sound = [Int16](repeating: 1, count: 1024)
  for n in 0..<buffers {
    packets.add(sound, at: Int64(clock(n * 512)) + jitter[n % jitter.count])
    while let (ts, _) = packets.pop() {
      worst = max(worst, abs(ts - Int64(clock(count * 960))))
      count += 1
    }
  }
  return (packets.runs, count, worst)
}

@Test
func drift100ppmEitherWayKeepsOneRunAndPacketsOnTheirTime() {
  for ppm in [100.0, -100.0] {
    let (runs, count, worst) = drifted(ppm)
    #expect(runs == 1, "\(ppm) ppm")
    #expect(count == 10 * 60 * 48_000 / 512 * 512 / 960, "\(ppm) ppm: none dropped")
    #expect(worst <= 3_000, "\(ppm) ppm: \(worst) µs off")
  }
}

@Test
func jitteredCaptureTimesMakePackets20msApart() {
  var packets = AudioPackets()
  var times: [Int64] = []
  for n in 0..<100 {
    packets.add(buffer(n), at: said(n))
    while let (ts, _) = packets.pop() { times.append(ts) }
  }
  #expect(times.count == 100 * 512 / 960)
  // 20 ms apart, the jitter a 64th of it at most
  #expect(zip(times, times.dropFirst()).allSatisfy { abs($1 - $0 - 20_000) <= 300 })
  #expect(packets.runs == 1)
  // nothing for 100 ms: a run of its own, from its own time
  packets.add(buffer(0), at: said(100) + 100_000)
  packets.add(buffer(1), at: said(100) + 100_000 + 10_667)
  #expect(abs((packets.pop()?.0 ?? 0) - (said(100) + 100_000)) <= 100)
  #expect(packets.runs == 2)
}

private func pair() -> (Channel, Int32) {
  var fds: [Int32] = [0, 0]
  socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
  return (Channel(fd: fds[0]), fds[1])
}

/// The audio packets' times written to `fd` so far (it read without waiting: what the helper's queue had written).
private func times(_ fd: Int32, _ carry: inout Data) -> [Int64] {
  var chunk = [UInt8](repeating: 0, count: 65536)
  while true {
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { break }
    carry.append(contentsOf: chunk[0..<n])
  }
  var out: [Int64] = []
  while carry.count >= 5 {
    let b = [UInt8](carry.prefix(5))
    let n = Int(b[1]) << 24 | Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
    guard carry.count >= 5 + n else { break }
    let payload = [UInt8](carry[carry.startIndex + 5..<carry.startIndex + 5 + n])
    if b[0] == 9 { out.append(payload.prefix(8).reduce(Int64(0)) { $0 << 8 | Int64($1) }) }
    carry = Data(carry.dropFirst(5 + n))
  }
  return out
}

@Test
func opusGoesWholeOverJitterAndShortSilenceAndStartsAnewAfterLongSilence() throws {
  let (channel, other) = pair()
  defer { close(other) }
  _ = fcntl(other, F_SETFL, fcntl(other, F_GETFL) | O_NONBLOCK)
  let audio = SystemAudio(channel: channel, opus: true)
  let encoder = try #require(audio.encoder)
  var n = 0
  var carry = Data()
  var sent: [Int64] = []
  // Each buffer as the capture gives it, a packet asked for before each (the station asks as the last went): every
  // packet made goes as it is made, or is left out.
  func feed(_ buffers: Int, silent: Bool) {
    for _ in 0..<buffers {
      audio.next()
      audio.took(buffer(n, silent: silent), at: said(n))
      n += 1
    }
    audio.queue.sync {}
    sent += times(other, &carry)
  }
  // 640 ms of sound, 43 ms of digital silence (a pause between two sounds), and so on: one run, all of it sent
  for _ in 0..<10 {
    feed(60, silent: false)
    feed(4, silent: true)
  }
  #expect(sent.count == n * 512 / 960)
  #expect(zip(sent, sent.dropFirst()).allSatisfy { abs($1 - $0 - 20_000) <= 300 }, "short silence goes: one run")
  #expect(encoder.resets == 1, "the encoder made anew for the first packet alone")
  // 400 ms of silence: from its 10th packet none goes; the sound after it, its encoder anew
  let before = sent.count
  feed(38, silent: true)
  feed(20, silent: false)
  let after = Array(sent[before...])
  #expect(zip(after, after.dropFirst()).filter { abs($1 - $0 - 20_000) > 10_000 }.count == 1, "one gap, where the silence went unsent")
  #expect(encoder.resets == 2)
}

@Test
func tenMinutesDriftingAt100ppmStartTheEncoderOnce() throws {
  for ppm in [100.0, -100.0] {
    let (channel, other) = pair()
    defer { close(other) }
    _ = fcntl(other, F_SETFL, fcntl(other, F_GETFL) | O_NONBLOCK)
    let audio = SystemAudio(channel: channel, opus: true)
    let encoder = try #require(audio.encoder)
    var carry = Data()
    var sent = 0
    let jitter: [Int64] = [0, 3_000, -3_000, 1_000, -2_000, 8_000, -8_000, 2_000, -1_000, 3_000]
    let buffers = 10 * 60 * 48_000 / 512
    for n in 0..<buffers {
      audio.next()
      let at = 1_000_000 + Double(n * 512) * 1_000_000 / 48_000 * (1 + ppm / 1_000_000)
      audio.took(buffer(n), at: Int64(at) + jitter[n % jitter.count])
      if n % 16 == 15 {
        audio.queue.sync {}
        sent += times(other, &carry).count
      }
    }
    audio.queue.sync {}
    sent += times(other, &carry).count
    #expect(sent == buffers * 512 / 960, "\(ppm) ppm: every packet sent")
    #expect(encoder.resets == 1, "\(ppm) ppm: the encoder made anew once")
  }
}
