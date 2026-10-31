// The pointer's shape over a node of the window's tree (View::cursor), as what it is over says it: said where it is
// none of what a node is shown by without being told (a hand over what takes presses), what a press on it holds kept
// while held (Tree::cursor_of). ui's (Ctx::cursor, @ui.Cursor) the same type: one shape, said either side.

///|
/// The pointer's shape over something: the arrow, a hand (what takes presses), the text's I-beam, a resizing edge's
/// (sideways, up and down), an open hand (what is dragged), and what another machine's pointer may be drawn as besides
/// (a remote screen's: a closed hand dragging, a crosshair, what cannot be done). What it is over says it
/// (ui's Ctx::show_cursor, Tree::cursor_of): a field the I-beam, what takes presses the hand, words picked with the
/// pointer the I-beam; what is none of those as it is (an edge, what a press on goes to a field, a remote screen's
/// pointer) is said so (ui's Ctx::cursor, View::cursor).
pub(all) enum Cursor {
  Arrow
  Hand
  IBeam
  ResizeX
  ResizeY
  Grab
  Grabbing
  Crosshair
  NotAllowed
} derive(Eq, Show, Debug)

///|
/// The number a host is told it by (@hostapi.set_cursor).
pub fn Cursor::code(self : Cursor) -> Int {
  match self {
    Arrow => 0
    Hand => 1
    IBeam => 2
    ResizeX => 3
    ResizeY => 4
    Grab => 5
    Grabbing => 6
    Crosshair => 7
    NotAllowed => 8
  }
}

///|
/// The pointer's shape over it, as it changes (None: what it is shown by without being told, Tree::cursor_of): a still
/// pointer over it shows it anew by the frame then owed.
pub fn View::cursor(self : View, shape : Live[Cursor?]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(20) {
    Some(stop) => {
      n.props.remove(20)
      stop()
    }
    None => ()
  }
  let set = fn(c : Cursor?) {
    guard self.live() is Some(n) else { return }
    if n.cursor != c {
      n.cursor = c
      // (a frame owed: a still pointer over it shown it anew as the frame ends, view_cursor_tell)
      self.tree.marked()
    }
  }
  match shape {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[20] = stop
      })
  }
  self
}

///|
/// The pointer's shape over node `id` as it is now: the one it says (View::cursor); else a hand where a press on it
/// does something (its on_press) and it takes presses; else the arrow (a node only dragged, a ground). One gone: the
/// arrow.
pub fn Tree::cursor_of(self : Tree, id : NodeId) -> Cursor {
  guard self.alive_id(id) else { return Arrow }
  let n = self.nodes[id.at]
  match n.cursor {
    Some(c) => c
    None => if n.on_press is Some(_) && self.takes_presses(id) { Hand } else { Arrow }
  }
}
