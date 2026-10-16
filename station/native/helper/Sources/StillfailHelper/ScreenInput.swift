// A person's input to a view, posted (station/src/screens/mac-input.ts says what each op is).
import CoreGraphics
import Foundation

final class ScreenInput {
  let channel: Channel
  let displayID: CGDirectDisplayID
  let queue = DispatchQueue(label: "fail.still.helper.input")
  let source = CGEventSource(stateID: .hidSystemState)
  var pointer = CGPoint(x: -1, y: -1)
  var refusedTold = false

  init(channel: Channel, displayID: CGDirectDisplayID) {
    self.channel = channel
    self.displayID = displayID
  }

  func post(_ op: [String: Any]) {
    queue.async { self.perform(op) }
  }

  func point(_ x: Double, _ y: Double) -> CGPoint {
    let bounds = CGDisplayBounds(displayID)
    let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
    return CGPoint(x: bounds.minX + cx * (bounds.width - 1), y: bounds.minY + cy * (bounds.height - 1))
  }

  func send(_ event: CGEvent?, flags: UInt64) {
    guard let event else { return }
    event.flags = CGEventFlags(rawValue: flags)
    event.post(tap: .cghidEventTap)
  }

  func perform(_ op: [String: Any]) {
    if !Status.inputAllowed() {
      if !refusedTold {
        refusedTold = true
        channel.sendJSON(4, ["refused": "control"])
      }
      return
    }
    let flags = (op["flags"] as? NSNumber)?.uint64Value ?? 0
    switch op["op"] as? String {
    case "mouse":
      let at = point((op["x"] as? Double) ?? 0, (op["y"] as? Double) ?? 0)
      let button = (op["button"] as? Int) ?? 0
      let buttons = (op["buttons"] as? Int) ?? 0
      let pressed: CGMouseButton = button == 2 ? .right : button == 1 ? .center : .left
      var type: CGEventType
      var held = pressed
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
      send(event, flags: flags)
      pointer = at
    case "scroll":
      let at = point((op["x"] as? Double) ?? 0, (op["y"] as? Double) ?? 0)
      // A wheel turns what is under the pointer: it goes there first.
      if at != pointer {
        send(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left), flags: flags)
        pointer = at
      }
      let dx = Int32(((op["dx"] as? Double) ?? 0).rounded()), dy = Int32(((op["dy"] as? Double) ?? 0).rounded())
      // A page's deltas are positive down and right; a wheel's, up and left.
      let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0)
      event?.location = at
      send(event, flags: flags)
    case "key":
      let keycode = CGKeyCode((op["keycode"] as? Int) ?? 0)
      send(CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: (op["down"] as? Bool) ?? true), flags: flags)
    case "text":
      let units = Array(((op["text"] as? String) ?? "").utf16)
      // At most 20 UTF-16 units an event (what a keyboard event carries); a surrogate pair is not split.
      var at = 0
      while at < units.count {
        var chunk = Array(units[at..<min(at + 20, units.count)])
        if chunk.count == 20, UTF16.isLeadSurrogate(chunk[19]) { chunk.removeLast() }
        for down in [true, false] {
          let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
          event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
          send(event, flags: 0)
        }
        at += chunk.count
      }
    default:
      break
    }
  }
}
