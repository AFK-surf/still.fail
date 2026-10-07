import Foundation
import Observation
import SwiftUI

/// A chat with something for the person, as the app sends it (apps/desktop/src/dock.mts `DockItem`).
struct Item: Codable, Identifiable, Equatable {
  /// The chat.
  var id: String
  /// Its newest message: a new one is a new notification.
  var key: String
  var title: String
  var station: String
  /// The sidebar's mark (web/src/ChatMark.tsx): "wait" (a card waits on the person), "alert" (failed), "done" (unread).
  var tone: String
  var who: String?
  var text: String
  /// The card's question, and its options when it is one to pick from.
  var ask: String?
  var options: [Option]?
  /// When its newest message came, ms since 1970.
  var at: Double
}

struct Option: Codable, Equatable, Hashable {
  var label: String
  var recommended: Bool?
}

/// The words the dock says, in the app's language (client/i18n/catalog/*/desktop.json, desktop.dock.*).
struct Words: Codable, Equatable {
  var open = "打开"
  var read = "已读"
  var later = "稍后"
  var empty = "都看过了"
  var next = "滚动看下一条"
  var last = "已经是最后一条"
  var waiting = "等你"
  var hide = "隐藏浮窗"
  var locale = "zh-Hans"
}

enum Phase { case collapsed, peek, card }

/// Everything the views show. The phases (docs/desktop-dock.md): collapsed, a half circle on the edge with the marks;
/// peek, a new one stretched out of it, staying until it is seen; card, one message to read and act on.
@Observable final class DockModel {
  var items: [Item] = []
  var words = Words()
  var phase: Phase = .collapsed
  var peeking: Item?
  /// New ones since the peek came out: it shows the newest and how many more.
  var unseen = 0
  /// The card shown, as an index into `items`.
  var current = 0
  /// Which way the last flip went, for the card's content to come from that side.
  var flipDown = true
  /// The handle's centre from the top of the screen, where it was last put.
  var handleY: CGFloat = UserDefaults.standard.object(forKey: "handleY") as? CGFloat ?? 0 {
    didSet { UserDefaults.standard.set(handleY, forKey: "handleY") }
  }
  var dragging = false

  /// The keys of every message the dock has had: one not among them is new. The first list counts as known.
  @ObservationIgnored private var known = Set<String>()
  @ObservationIgnored private var primed = false
  // In window coordinates (top-left origin), as the views measure them.
  @ObservationIgnored var handleRect: CGRect = .zero
  @ObservationIgnored var cardRect: CGRect = .zero

  /// What waits on the person first, then what failed, then the rest; newest first in each.
  static func ordered(_ items: [Item]) -> [Item] {
    let rank = ["wait": 0, "alert": 1, "done": 2]
    return items.sorted { a, b in
      let ra = rank[a.tone] ?? 3, rb = rank[b.tone] ?? 3
      return ra != rb ? ra < rb : a.at > b.at
    }
  }

  /// The handle's marks: the loudest first, at most four.
  var marks: [String] { Array(items.prefix(4).map(\.tone)) }

  func update(_ list: [Item]) {
    let shownID = phase == .card && items.indices.contains(current) ? items[current].id : nil
    items = Self.ordered(list)
    if !primed {
      primed = true
      known = Set(items.map(\.key))
    } else {
      let fresh = items.filter { !known.contains($0.key) }
      known.formUnion(items.map(\.key))
      if let newest = fresh.max(by: { $0.at < $1.at }), phase != .card {
        peeking = newest
        unseen += fresh.count
        phase = .peek
      }
    }
    if let p = peeking {
      if let now = items.first(where: { $0.id == p.id }) { peeking = now } else { putAway() }
    }
    if let id = shownID, let i = items.firstIndex(where: { $0.id == id }) { current = i }
    current = max(0, min(current, items.count - 1))
  }

  /// Back into the half circle: the peek is gone, what it showed stays unread.
  func putAway() {
    peeking = nil
    unseen = 0
    phase = .collapsed
  }

  /// The card for what the peek shows, else the first.
  func openCard() {
    current = peeking.flatMap { p in items.firstIndex(where: { $0.id == p.id }) } ?? 0
    flipDown = true
    phase = .card
  }

  func flip(_ by: Int) {
    let next = max(0, min(items.count - 1, current + by))
    guard next != current else { return }
    flipDown = by > 0
    current = next
  }

  /// One dealt with (answered, read, opened): out of the list here at once; the app's next list agrees.
  func handled(_ item: Item) {
    items.removeAll { $0.id == item.id }
    if peeking?.id == item.id { peeking = nil; unseen = 0 }
    current = max(0, min(current, items.count - 1))
    if items.isEmpty { putAway() }
  }
}
