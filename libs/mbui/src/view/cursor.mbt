// The pointer's shape over a node of the window's tree (View::cursor), as what it is over says it: said where it is
// none of what a node is shown by without being told (a hand over what takes presses), what a press on it holds kept
// while held (Tree::cursor_of). ui's (Ctx::cursor, @ui.Cursor) the same type: one shape, said either side.

///|
/// The pointer's shape over something: the arrow, a hand (what takes presses), the text's I-beam, a resizing edge's
/// (sideways, up and down), a resizing corner's (ResizeNWSE a top left or bottom right one's, ResizeNESW a top right or
/// bottom left one's), an open hand (what is dragged), and what another machine's pointer may be drawn as besides
/// (a remote screen's: a closed hand dragging, a crosshair, what cannot be done). What it is over says it
/// (ui's Ctx::show_cursor, Tree::cursor_of): a field the I-beam, what takes presses the hand, words picked with the
/// pointer the I-beam; what is none of those as it is (an edge or a corner, what a press on goes to a field, a remote
/// screen's pointer) is said so (ui's Ctx::cursor, View::cursor).
#derive(Eq, Debug)
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
  ResizeNWSE
  ResizeNESW
}

///|
/// By its name, as a Tester's export writes the pointer's shape: what `derive(Show)` wrote.
pub impl Show for Cursor with output(self, logger) {
  logger.write_string(
    match self {
      Arrow => "Arrow"
      Hand => "Hand"
      IBeam => "IBeam"
      ResizeX => "ResizeX"
      ResizeY => "ResizeY"
      Grab => "Grab"
      Grabbing => "Grabbing"
      Crosshair => "Crosshair"
      NotAllowed => "NotAllowed"
      ResizeNWSE => "ResizeNWSE"
      ResizeNESW => "ResizeNESW"
    },
  )
}

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
    ResizeNWSE => 9
    ResizeNESW => 10
  }
}

///|
/// The pointer's shape over it, as it changes (None: what it is shown by without being told, Tree::cursor_of): a still
/// pointer over it shows it anew at that change (Tree::on_cursor), no frame asked for it. Said at `loc` (kept where the
/// tree keeps that, as a property bound by View::bind is: source.mbt).
#callsite(autofill(loc))
pub fn View::cursor(self : View, shape : Live[Cursor?], loc~ : SourceLoc) -> View {
  guard self.live() is Some(n) else { return self }
  match n.source {
    Some(s) => s.said[Prop::Cursor.ord()] = (Prop::Cursor, loc)
    None => ()
  }
  match n.props.get(Prop::Cursor.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Cursor.ord())
      stop()
    }
    None => ()
  }
  let set = fn(c : Cursor?) {
    guard self.live() is Some(n) else { return }
    if n.cursor != c {
      n.cursor = c
      // (a still pointer over it shown it anew at once, what hosts the tree told (Tree::on_cursor: ui's
      // view_cursor_tell): nothing drawn for a shape, no frame asked)
      (self.tree.on_cursor)()
    }
  }
  match shape {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) }, draws=false)
        n.props[Prop::Cursor.ord()] = stop
      })
  }
  self
}

///|
/// The pointer's shape over node `id` as it is now: the one it says (View::cursor); else the shape of what is pressed
/// (Tree::pressed_shape: a hand, unless the app said otherwise) where a press on it does something (its on_press) and
/// it takes presses; else the arrow (a node only dragged, a ground). One gone: the arrow.
pub fn Tree::cursor_of(self : Tree, id : NodeId) -> Cursor {
  guard self.alive_id(id) else { return Arrow }
  let n = self.nodes[id.at]
  match n.cursor {
    Some(c) => c
    None => if n.on_press is Some(_) && !n.points && self.takes_presses(id) { self.pressed_shape() } else { Arrow }
  }
}

///|
/// Whether what is pressed shows the hand as the pointer is over it (true, as it starts), or the arrow: a button, a row,
/// a link in words, of the window's tree and of the old views hosted in it (ui's Ctx::show_cursor, its links'
/// nodes: tree_links.mbt). An app says false once for the whole window where its platform's own apps keep the arrow
/// over what they press (Windows' native apps do; the web's and macOS' links show the hand), so none of it shows a
/// hand; a shape a node or an old view says itself (View::cursor, ui's Ctx::cursor) is still its own. Told anew at
/// once to a still pointer over the tree (Tree::on_cursor); an old view's at the pointer's next move.
pub fn Tree::hand_over_presses(self : Tree, on : Bool) -> Unit {
  if @signals.untracked(fn() { self.hands.get() }) != on {
    self.hands.set(on)
    (self.on_cursor)()
  }
}

///|
/// The pointer's shape over what is pressed, as the app said (Tree::hand_over_presses): the hand, else the arrow.
pub fn Tree::pressed_shape(self : Tree) -> Cursor {
  if self.hands.get() {
    Hand
  } else {
    Arrow
  }
}

///|
/// It a ground, no control, for as long as it lives: what a press on it does is the ground's (a message's words a hold
/// picks in and the links in them, ui's runs_links; the room round a panel's rows), so it has no room of its own to be
/// pressed in and cuts none from what is beside it (Tree::press_boxes, ui's rooms.mbt), whatever the pointer's shape
/// over it (View::cursor: that is how it looks, not what it is).
pub fn View::as_ground(self : View) -> View {
  guard self.live() is Some(n) else { return self }
  n.as_ground = true
  self
}
