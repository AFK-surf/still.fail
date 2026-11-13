// What a test reads of each page's list of the window's tree (View::scrolls_window) and asks of it, as it reads an old
// view's list (mbui/ui's Tester::rows, visible, at_end, scroll_to): which rows show, by where each is among its keys,
// where each is drawn, how many there are, where it is scrolled to, whether it is at its foot.

///|
/// What a page's list gives a test (Tree::lists_seen): its scroll, how many keys it has, and asked of it, a row brought to
/// its top by where it is among its keys, and its foot.
priv struct ListAsked {
  scroll : Scroll
  count : () -> Int
  bring : (Int) -> Unit
  to_end : () -> Unit
}

///|
/// A page's list as a test reads it (Tree::lists_seen).
#derive(Debug)
pub(all) struct ListSeen {
  /// its node
  list : NodeId
  /// the rows drawn in sight (any of them within where it shows), top to bottom: where each is among its keys
  /// (View::row_order), its node (the slot it is made in), and where it is drawn in the window (x, y, w, h)
  rows : Array[(Int, NodeId, (Double, Double, Double, Double))]
  /// how many keys it has
  count : Int
  /// how far it is scrolled, as of the logic's moment (Scroll::at)
  at : Double
  /// how far it shows past an end (Scroll::past: from its top positive, from its foot negative)
  past : Double
  /// whether it is on by itself (a fling, what shows past an end going back)
  moving : Bool
  /// whether it is at its foot (Scroll::at_foot_now)
  at_foot : Bool
}

///|
/// Each page's list live now, in the order its node was made, as a test reads it (ListSeen), the tree laid out as of
/// the logic's moment.
pub fn Tree::lists_seen(self : Tree) -> Array[ListSeen] {
  self.laid_as_now()
  let ats = self.lists_asked.keys().to_array()
  ats.sort()
  ats.filter_map(fn(at) {
    guard self.nodes[at].live && self.lists_asked.get(at) is Some(a) else { return None }
    let list : NodeId = { at, gen: self.nodes[at].gen }
    guard self.drawn_of(list) is Some(ld) else { return None }
    // (each row's outermost node named for it, drawn within where the list shows)
    let found : Array[(Int, NodeId, (Double, Double, Double, Double))] = []
    let named : Map[Int, Int] = Map([])
    self.rows_named.each(fn(k, r) {
      guard r.0 == list && self.nodes[k].live else { return }
      named[k] = (r.2)()
    })
    named.each(fn(k, order) {
      guard order >= 0 else { return }
      // (one held by another named for the same row: that one's)
      let mut p = self.nodes[k].parent
      while p >= 0 && p != at {
        if named.get(p) == Some(order) {
          return
        }
        p = self.nodes[p].parent
      }
      match self.drawn_of({ at: k, gen: self.nodes[k].gen }) {
        Some(d) if d.y < ld.y + ld.h && d.y + d.h > ld.y && d.h > 0.0 => found.push((order, d.id, (d.x, d.y, d.w, d.h)))
        _ => ()
      }
    })
    found.sort_by(fn(p, q) { p.0.compare(q.0) })
    let s = a.scroll
    Some({
      list,
      rows: found,
      count: (a.count)(),
      at: s.at(self),
      past: s.past(self),
      moving: s.glides_till() is Some(_),
      at_foot: @signals.untracked(fn() { s.at_foot_now() }),
    })
  })
}

///|
/// Page's list `list`'s row `order` (where it is among its keys) brought to its top, as its ListPlace::bring is: done as
/// the list is next laid out. Nothing where it is no page's list or has no such row.
pub fn Tree::list_bring(self : Tree, list : NodeId, order : Int) -> Unit {
  match self.lists_asked.get(list.at) {
    Some(a) if self.alive_id(list) => (a.bring)(order)
    _ => ()
  }
}

///|
/// Page's list `list` to its foot, at once, as its ListPlace::to_end is.
pub fn Tree::list_to_end(self : Tree, list : NodeId) -> Unit {
  match self.lists_asked.get(list.at) {
    Some(a) if self.alive_id(list) => (a.to_end)()
    _ => ()
  }
}
