// A connection's bytes: JSON lines, and messages of a kind byte, the payload's length (4 bytes, big-endian), the payload.
import Foundation

final class Channel {
  let fd: Int32
  private let lock = NSLock()
  private(set) var broken = false

  init(fd: Int32) {
    self.fd = fd
  }

  /// All of `data`, or the channel is broken (whoever read it is gone).
  func write(_ data: Data) {
    lock.lock()
    defer { lock.unlock() }
    if broken { return }
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var at = 0
      while at < raw.count {
        let n = Darwin.write(fd, raw.baseAddress! + at, raw.count - at)
        if n < 0 {
          if errno == EINTR { continue }
          broken = true
          return
        }
        at += n
      }
    }
  }

  func send(_ kind: UInt8, _ payload: Data) {
    var head = Data([kind])
    var n = UInt32(payload.count).bigEndian
    head.append(Data(bytes: &n, count: 4))
    write(head + payload)
  }

  func sendJSON(_ kind: UInt8, _ value: [String: Any]) {
    send(kind, Channel.json(value))
  }

  func line(_ value: [String: Any]) {
    write(Channel.json(value) + Data("\n".utf8))
  }

  static func json(_ value: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
  }

  /// Exactly `n` bytes, or nil at the end.
  func read(_ n: Int) -> Data? {
    var data = Data(count: n)
    var at = 0
    while at < n {
      let got = data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in Darwin.read(fd, raw.baseAddress! + at, n - at) }
      if got < 0 && errno == EINTR { continue }
      if got <= 0 { return nil }
      at += got
    }
    return data
  }

  /// Up to `n` bytes as they come (at least one), or nil at the end.
  func read(upTo n: Int) -> Data? {
    var data = Data(count: n)
    while true {
      let got = data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in Darwin.read(fd, raw.baseAddress!, n) }
      if got < 0 && errno == EINTR { continue }
      if got <= 0 { return nil }
      return data.prefix(got)
    }
  }

  /// One line (without its newline), at most `limit` bytes; nil at the end or past it.
  func readLine(limit: Int = 1 << 16) -> Data? {
    var line = Data()
    var byte: UInt8 = 0
    while line.count <= limit {
      let got = Darwin.read(fd, &byte, 1)
      if got < 0 && errno == EINTR { continue }
      if got <= 0 { return nil }
      if byte == 10 { return line }
      line.append(byte)
    }
    return nil
  }

  /// The next message: its kind and payload; nil at the end or for one past `limit`.
  func message(limit: Int = 1 << 20) -> (UInt8, Data)? {
    guard let head = read(5) else { return nil }
    let length = Int(head[1]) << 24 | Int(head[2]) << 16 | Int(head[3]) << 8 | Int(head[4])
    guard length <= limit else { return nil }
    if length == 0 { return (head[0], Data()) }
    guard let payload = read(length) else { return nil }
    return (head[0], payload)
  }
}
