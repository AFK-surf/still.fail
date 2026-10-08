// The desktop's dock (docs/desktop-dock.md): a half circle of Liquid Glass on the screen's right edge with what waits
// for the person. The app (apps/desktop/src/dock.mts) starts it and talks to it a JSON object a line: on stdin
//   {"type":"items","items":[Item…]}   what there is now (Model.swift `Item`), every time it changes
//   {"type":"words","words":{…}}       what it says, in the app's language
// and on stdout
//   {"type":"open","id":…}  {"type":"read","id":…}  {"type":"answer","id":…,"key":…,"option":…}  {"type":"off"}
// It quits when stdin closes (the app went).
import AppKit
import SwiftUI

enum Outgoing {
  case open(Item), read(Item), answer(Item, String), later, off
}

/// A borderless panel along the right edge, as tall as the screen: it never takes focus, floats over full-screen apps
/// and on every Space, and lets the mouse through everywhere but the glass.
final class DockPanel: NSPanel {
  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    hidesOnDeactivate = false
    isMovable = false
    ignoresMouseEvents = true
  }
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class Dock: NSObject, NSApplicationDelegate {
  let model = DockModel()
  let panel = DockPanel()
  var timer: Timer?
  var inside = false
  var since = Date.distantPast
  /// After 稍后 or 打开 the mouse is still on the glass: nothing opens again until it has left.
  var suppressed = false
  var swipedAt = Date.distantPast
  var swipe: CGFloat = 0

  /// How long the mouse rests on the handle before the card opens (longer on a peek, so a swipe on it can start), and
  /// how long it is off the glass before the card closes.
  let openDelay: TimeInterval = 0.12
  let peekOpenDelay: TimeInterval = 0.3
  let closeDelay: TimeInterval = 0.4
  /// Room round the glass that still counts as on it.
  let slack: CGFloat = 14
  let spring = Animation.spring(response: 0.45, dampingFraction: 0.72)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let view = NSHostingView(rootView: DockView(model: model, send: { [weak self] in self?.send($0) }))
    view.sizingOptions = []
    panel.contentView = view
    place()
    panel.orderFrontRegardless()
    NotificationCenter.default.addObserver(self, selector: #selector(place), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(timer!, forMode: .common)
    NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.scrolled(event) ?? event }
    listen()
  }

  /// On the screen with the menu bar, its right edge, full height.
  @objc func place() {
    guard let screen = NSScreen.screens.first else { return }
    let frame = screen.frame
    let width = Size.handle + Size.gap + Size.card + 40
    panel.setFrame(NSRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height), display: true)
  }

  func toScreen(_ rect: CGRect) -> CGRect {
    guard rect != .zero else { return .zero }
    let window = panel.frame
    return CGRect(x: window.minX + rect.minX, y: window.maxY - rect.maxY, width: rect.width, height: rect.height)
  }

  func tick() {
    let mouse = NSEvent.mouseLocation
    let handle = toScreen(model.handleRect).insetBy(dx: -slack, dy: -slack)
    let card = toScreen(model.cardRect)
    // With the card out, the gap between it and the handle counts too, so crossing it does not close the card.
    let over = model.phase == .card && card != .zero ? handle.union(card.insetBy(dx: -slack, dy: -slack)) : handle
    let now = Date()
    // The screen's right edge, anywhere along it, opens what waits (nothing waiting, there is nothing to open).
    let screen = panel.screen?.frame ?? panel.frame
    let atEdge = !model.items.isEmpty && mouse.x >= screen.maxX - 2 && mouse.y >= screen.minY && mouse.y <= screen.maxY
    let isIn = model.dragging || over.contains(mouse) || (atEdge && model.phase != .card)
    panel.ignoresMouseEvents = !isIn
    if isIn != inside { inside = isIn; since = now }
    if !inside { suppressed = false }
    switch model.phase {
    case .collapsed, .peek:
      let delay = model.phase == .peek ? peekOpenDelay : openDelay
      if inside, !model.items.isEmpty, !suppressed, !model.dragging, now.timeIntervalSince(since) >= delay, now.timeIntervalSince(swipedAt) > 0.5 {
        withAnimation(spring) { model.openCard() }
      }
    case .card:
      // Seen is enough: the card closing takes the peek with it; what it showed waits in the half circle, unread.
      if !inside, now.timeIntervalSince(since) >= closeDelay { withAnimation(spring) { model.putAway() } }
    }
  }

  /// Two fingers sideways on the peek push it back in.
  func scrolled(_ event: NSEvent) -> NSEvent? {
    guard event.window === panel else { return event }
    switch model.phase {
    case .card:
      // The card's own scroll view goes through the messages.
      return event
    case .peek:
      if event.phase == .began { swipe = 0 }
      swipe += event.scrollingDeltaX
      swipedAt = Date()
      if abs(swipe) > 30, abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) {
        swipe = 0
        withAnimation(spring) { model.putAway() }
      }
      return nil
    case .collapsed:
      return event
    }
  }

  func send(_ message: Outgoing) {
    switch message {
    case .later:
      suppressed = true
      withAnimation(spring) { model.putAway() }
    case .off:
      write(["type": "off"])
    case .open(let item):
      write(["type": "open", "id": item.id])
      suppressed = true
      withAnimation(spring) { model.handled(item); model.putAway() }
    case .read(let item):
      write(["type": "read", "id": item.id, "key": item.key])
      withAnimation(spring) { model.handled(item) }
    case .answer(let item, let option):
      write(["type": "answer", "id": item.id, "key": item.key, "option": option])
      withAnimation(spring) { model.handled(item) }
    }
  }

  func write(_ object: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
  }

  struct Incoming: Decodable {
    var type: String
    var items: [Item]?
    var words: Words?
  }

  /// The app's lines, read on a thread of their own; each applied on the main thread. The end of them is the app gone.
  func listen() {
    Thread.detachNewThread { [weak self] in
      while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8), let message = try? JSONDecoder().decode(Incoming.self, from: data) else { continue }
        DispatchQueue.main.async {
          guard let self else { return }
          if let words = message.words { self.model.words = words }
          if let items = message.items { withAnimation(self.spring) { self.model.update(items) } }
        }
      }
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}

let app = NSApplication.shared
let dock = Dock()
app.delegate = dock
app.setActivationPolicy(.accessory)
app.run()
