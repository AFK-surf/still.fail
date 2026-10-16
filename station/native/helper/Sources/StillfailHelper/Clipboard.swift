// The Mac's clipboard for a view a person drives (docs/remote-screens.md `clipboard`, ScreenView.swift's messages 4–6):
// set from the viewer and pasted with ⌘V, watched while the view asks (its changeCount looked at every half a second,
// on the main queue, nothing else read until it changes), and a file shown in Finder. Text first, else a picture as
// PNG (from PNG or TIFF), each within its bound; what this view set itself is not said back to it.
import AppKit
import CoreGraphics
import Foundation

final class Clipboard {
  /// What a view carries each way at most (station/src/screens/source.ts CLIP_TEXT_MAX, CLIP_PNG_MAX).
  static let textMax = 1024 * 1024
  static let pngMax = 8 * 1024 * 1024
  /// How often the changeCount is looked at while watched.
  static let interval: TimeInterval = 0.5

  let channel: Channel
  let input: ScreenInput
  private var timer: DispatchSourceTimer?
  /// The changeCount last seen (or set here): a change after it is a copy made on the Mac.
  private var seen = 0

  init(channel: Channel, input: ScreenInput) {
    self.channel = channel
    self.input = input
  }

  /// Message 4: flags (bit 0: paste), type (1 text, 2 PNG), the bytes. Set after the input before it, on its queue,
  /// then ⌘V where the focus is.
  func set(_ payload: Data) {
    guard payload.count >= 3 else { return }
    let bytes = [UInt8](payload)
    let paste = bytes[0] & 1 == 1
    let type = bytes[1]
    let body = payload.subdata(in: payload.startIndex + 2..<payload.endIndex)
    input.queue.async {
      let done = DispatchQueue.main.sync { () -> Bool in
        let board = NSPasteboard.general
        switch type {
        case 1:
          guard body.count <= Clipboard.textMax, let text = String(data: body, encoding: .utf8) else { return false }
          board.clearContents()
          board.setString(text, forType: .string)
        case 2:
          guard body.count <= Clipboard.pngMax, let image = NSBitmapImageRep(data: body) else { return false }
          board.clearContents()
          board.setData(body, forType: .png)
          // Apps that read only TIFF (older ones) find it too.
          if let tiff = image.tiffRepresentation { board.setData(tiff, forType: .tiff) }
        default:
          return false
        }
        self.seen = board.changeCount
        return true
      }
      if done && paste { self.input.paste() }
    }
  }

  /// Message 5: watched (1) or not (0).
  func watch(_ payload: Data) {
    let on = payload.first == 1
    DispatchQueue.main.async {
      self.timer?.cancel()
      self.timer = nil
      guard on else { return }
      // What it holds now is not a copy made while watched.
      self.seen = NSPasteboard.general.changeCount
      let timer = DispatchSource.makeTimerSource(queue: .main)
      timer.schedule(deadline: .now() + Clipboard.interval, repeating: Clipboard.interval, leeway: .milliseconds(100))
      timer.setEventHandler { [weak self] in self?.look() }
      timer.resume()
      self.timer = timer
    }
  }

  func stop() {
    DispatchQueue.main.async {
      self.timer?.cancel()
      self.timer = nil
    }
  }

  /// Message 6: the path, shown selected in Finder.
  func reveal(_ payload: Data) {
    guard let path = String(data: payload, encoding: .utf8), path.hasPrefix("/") else { return }
    DispatchQueue.main.async {
      let url = URL(fileURLWithPath: path)
      if FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } else {
        NSWorkspace.shared.open(url.deletingLastPathComponent())
      }
    }
  }

  /// The clipboard changed since last seen: what it holds now, said as message 5 (type, bytes).
  private func look() {
    let board = NSPasteboard.general
    let count = board.changeCount
    guard count != seen else { return }
    seen = count
    if let text = board.string(forType: .string), !text.isEmpty {
      let data = Data(text.utf8)
      if data.count <= Clipboard.textMax { channel.send(5, Data([1]) + data) }
      return
    }
    var png = board.data(forType: .png)
    if png == nil, let tiff = board.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff) {
      png = image.representation(using: .png, properties: [:])
    }
    if let png, !png.isEmpty, png.count <= Clipboard.pngMax { channel.send(5, Data([2]) + png) }
  }
}
