// What goes beside another (a tip by what it tells of, a menu by its trigger): which side of its anchor, lined up how
// along it (Side, Along), where it goes then, kept in the window (place_beside: Radix's Popper, flip then shift; one
// way of working it out, the old frame's Ctx::place's and a node's, View::beside); a node said to go so placed by its
// anchor as the tree is laid out and placed, by its anchor's place then, not as it was drawn before.

///|
/// Which side of its anchor a layer's content goes.
pub(all) enum Side {
  Top
  Right
  Bottom
  Left
} derive(Eq, Show, Debug)

///|
/// Where along the side it lines up with the anchor: their starts (the left, right to left the right), their middles,
/// their ends.
pub(all) enum Along {
  Start
  Middle
  End
} derive(Eq, Show, Debug)

///|
/// Where content `w` by `h` goes by an anchor (x, y, w, h, in a window `vw` by `vh`), Radix's Popper: on `side`,
/// `offset` away, lined up `along` it (moved `along_offset` further), kept `padding` inside the window (`flip`: to the
/// other side when it does not fit on its own and fits better there; moved along the side to stay in, and over the
/// anchor where it fits on neither: Radix's shift on both axes); `rtl`: right to left, a start the right. Its top left,
/// and the side it went on.
pub fn place_beside(
  anchor : (Double, Double, Double, Double),
  w : Double,
  h : Double,
  vw : Double,
  vh : Double,
  side? : Side = Bottom,
  along? : Along = Middle,
  offset? : Double = 4.0,
  along_offset? : Double = 0.0,
  padding? : Double = 8.0,
  flip? : Bool = true,
  rtl? : Bool = false,
) -> (Double, Double, Side) {
  let (ax, ay, aw, ah) = anchor
  // the room on each side
  let room = fn(s : Side) {
    match s {
      Top => ay - offset - padding
      Bottom => vh - (ay + ah) - offset - padding
      Left => ax - offset - padding
      Right => vw - (ax + aw) - offset - padding
    }
  }
  let opposite = fn(s : Side) {
    match s {
      Top => Bottom
      Bottom => Top
      Left => Right
      Right => Left
    }
  }
  let need = fn(s : Side) {
    match s {
      Top | Bottom => h
      Left | Right => w
    }
  }
  let side = if flip && room(side) < need(side) && room(opposite(side)) > room(side) {
    opposite(side)
  } else {
    side
  }
  // right to left, a start is the right
  let across = side == Top || side == Bottom
  let along = if rtl && across {
    match along {
      Start => End
      End => Start
      Middle => Middle
    }
  } else {
    along
  }
  let sign = if rtl && across { -1.0 } else { 1.0 }
  let line = fn(a0 : Double, alen : Double, len : Double) {
    match along {
      Start => a0
      Middle => a0 + (alen - len) / 2.0
      End => a0 + alen - len
    }
  }
  let (x, y) = match side {
    Top => (line(ax, aw, w) + along_offset * sign, ay - offset - h)
    Bottom => (line(ax, aw, w) + along_offset * sign, ay + ah + offset)
    Left => (ax - offset - w, line(ay, ah, h) + along_offset)
    Right => (ax + aw + offset, line(ay, ah, h) + along_offset)
  }
  // moved along to stay in the window, and across where neither side has the room for it: over its anchor rather
  // than out of the window (never past its start)
  let keep = fn(v : Double, len : Double, max : Double) {
    let hi = max - padding - len
    let v = if v < hi { v } else { hi }
    if v > padding {
      v
    } else {
      padding
    }
  }
  (keep(x, w, vw), keep(y, h, vh), side)
}

///|
/// What a node goes beside (View::beside): its anchor, on which side of it, lined up how, how far off, kept how far
/// inside the window; `at_pointer`: beside the point of it the pointer is at while the pointer is on it, not all of it.
pub(all) struct Beside {
  anchor : NodeId
  side : Side
  along : Along
  offset : Double
  padding : Double
  at_pointer : Bool
} derive(Eq, Debug)

///|
/// Placed beside node `anchor` (place_beside: on `side`, `offset` away, lined up `along` it, kept `padding` inside the
/// window, to the other side where it has not the room on its own), by where the anchor is and how big both are as the
/// tree is placed, each time it is: what it holds with it. Out of its holder's flow, as big as what it holds says (its
/// width, its words). Leaving, or its anchor gone or drawn nowhere (let go, left out of its row, leaving), where it
/// last went beside it: it follows its anchor while both are there, and never goes anywhere else. `at_pointer`: beside
/// the point in the window the pointer is at while it is on the anchor (Tree::point_at, placed again as it moves), as
/// the anchor were that point (a tip by the pointer along a tall thin thing); the pointer gone off it, by the point of
/// it the pointer was last at (following the anchor still); never on it, beside all of it.
pub fn View::beside(
  self : View,
  anchor : NodeId,
  side? : Side = Bottom,
  along? : Along = Middle,
  offset? : Double = 4.0,
  padding? : Double = 8.0,
  at_pointer? : Bool = false,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.beside = Some({ anchor, side, along, offset, padding, at_pointer })
  if !self.tree.besides_at.contains(self.at) {
    self.tree.besides_at.push(self.at)
  }
  // (out of its holder's flow, as big as what it holds: where it is, its anchor's say)
  let st = n.flex.style
  st.position = Absolute
  st.set_inset_left(Pt(0.0))
  st.set_inset_top(Pt(0.0))
  st.set_inset_right(Auto)
  st.set_inset_bottom(Auto)
  self.tree.layout_marked_at(self.at)
  self
}

///|
/// What goes beside another placed by it (View::beside), as the tree is placed now (Tree::laid_out, where anything was
/// laid out or placed again): each after what it goes beside where that goes beside another in turn, and after what
/// holds it where that does (a chain of them in its order, whatever order they were made or said in), what lands
/// elsewhere than it was composed again there. What goes beside itself or what it holds, or beside what comes round to
/// it again (a ring of them), goes beside nothing: where it is laid out, each time. Those let go dropped.
fn Tree::besides_placed(self : Tree) -> Unit {
  let live = self.besides_at.filter(fn(at) { self.nodes[at].live && self.nodes[at].beside is Some(_) })
  self.besides_at.clear()
  self.besides_at.append(live)
  // (1 being placed, 2 placed beside its anchor, 3 refused: where it is laid out)
  let state : Map[Int, Int] = {}
  fn refused(at : Int) -> Unit {
    state[at] = 3
    // (on no side of anything)
    self.nodes[at].went = None
    // (where it is laid out, as if it went beside nothing: never where it went last)
    let n = self.nodes[at]
    let (lx, ly) = (n.lx, n.ly)
    self.place(at)
    if n.lx != lx || n.ly != ly {
      self.work.composed = self.work.composed + 1
      self.composed.push({ at, gen: n.gen })
      self.places_rev = self.places_rev + 1
      self.hits = self.hits + 1
    }
  }

  fn place_one(at : Int) -> Bool {
    match state.get(at) {
      Some(1) => return false
      Some(2) => return true
      Some(_) => return false
      None => ()
    }
    state[at] = 1
    let n = self.nodes[at]
    // (where it was last beside its anchor, kept: placed again by what changed of its own (its fading, its size), it
    // stays there, never where it is laid out)
    let stay = fn() {
      match n.beside_last {
        Some((lx, ly, px, py)) =>
          if lx != n.lx || ly != n.ly || px != n.lpx || py != n.lpy {
            n.lx = lx
            n.ly = ly
            n.lpx = px
            n.lpy = py
            self.work.composed = self.work.composed + 1
            self.composed.push({ at, gen: n.gen })
            self.places_rev = self.places_rev + 1
            self.hits = self.hits + 1
          }
        None => ()
      }
      state[at] = 2
      true
    }
    guard n.beside is Some(b) && self.alive_id(b.anchor) else {
      // (beside nothing now, its anchor gone: on no side of it, where it last was beside it)
      if n.went is Some(_) {
        self.sizes_due = true
      }
      n.went = None
      return stay()
    }
    // (leaving, or its anchor drawn nowhere (left out of its row, leaving): where it last was beside it, following
    // nothing on its way out)
    if self.leaving_at(at) || self.out_at(b.anchor.at) || self.leaving_at(b.anchor.at) {
      return stay()
    }
    // (beside itself or what it holds: refused)
    let mut i = b.anchor.at
    while i >= 0 {
      if i == at {
        refused(at)
        return false
      }
      i = self.nodes[i].parent
    }
    // (what goes beside another among its anchor and what holds it, and what holds it itself, placed first: where they
    // are placed is what it is placed by; one that comes round to it again, or is refused, refuses it)
    for start in [b.anchor.at, n.parent] {
      let mut i = start
      while i >= 0 {
        if self.nodes[i].beside is Some(_) && !place_one(i) {
          refused(at)
          return false
        }
        i = self.nodes[i].parent
      }
    }
    self.work.besides = self.work.besides + 1
    // (where its anchor is drawn and how big, where what holds it is: in the window's terms as the scene is composed,
    // Tree::projected; it goes there as big as what holds it draws it, its own scale about where it went after)
    guard self.window_place(b.anchor.at) is Some((ax, ay, ascale)) else { return stay() }
    let a = self.nodes[b.anchor.at]
    let (hx, hy, hs) = match self.window_place(n.parent) {
      Some(p) => p
      None => (0.0, 0.0, 1.0)
    }
    // (where it is beside: all of its anchor as drawn now; by the pointer, the point it is at, while it is on it)
    let (aw, ah) = (a.lw * ascale, a.lh * ascale)
    let (px, py) = self.pointer_xy
    // (the pointer gone off it: by the point of it the pointer was last at, as the anchor is now, never jumping to all of
    // it; never on it (shown by the keyboard's focus), beside all of it)
    let rect = if b.at_pointer && px >= ax && py >= ay && px < ax + aw && py < ay + ah {
      n.beside_point = Some(((px - ax) / ascale, (py - ay) / ascale))
      (px, py, 0.0, 0.0)
    } else {
      match (b.at_pointer, n.beside_point) {
        (true, Some((ox, oy))) => (ax + ox * ascale, ay + oy * ascale, 0.0, 0.0)
        _ => (ax, ay, aw, ah)
      }
    }
    let (x, y, went) = place_beside(
      rect,
      n.lw * hs,
      n.lh * hs,
      self.last_w,
      self.last_h,
      side=b.side,
      along=b.along,
      offset=b.offset,
      padding=b.padding,
    )
    // (where it grows from, where it is drawn bigger or smaller about the side it went on: View::scale's FromBeside)
    if n.went != Some(went) {
      self.sizes_due = true
    }
    n.went = Some(went)
    let (px, py) = self.pivot_of(at, n.lw, n.lh)
    let (lx, ly) = ((x - hx) / hs, (y - hy) / hs)
    n.beside_last = Some((lx, ly, px, py))
    if lx != n.lx || ly != n.ly || px != n.lpx || py != n.lpy {
      n.lx = lx
      n.ly = ly
      n.lpx = px
      n.lpy = py
      self.work.composed = self.work.composed + 1
      self.composed.push({ at, gen: n.gen })
      self.places_rev = self.places_rev + 1
      self.hits = self.hits + 1
    }
    state[at] = 2
    true
  }

  for at in self.besides_at {
    place_one(at) |> ignore
  }
}

///|
/// Where node `at` is drawn in the window as the tree is placed now and how big (Tree::projected), none where it is no
/// live node.
fn Tree::window_place(self : Tree, at : Int) -> (Double, Double, Double)? {
  if at < 0 || at >= self.nodes.length() || !self.nodes[at].live {
    return None
  }
  let (x, y, _, s) = self.projected(at)
  Some((x, y, s))
}

///|
/// It let go as `owner` is, wherever it is held (what is drawn elsewhere for another, a tip in a layer over all of the
/// window for the control it tells of: its scope the other's, nothing of it left once that one goes). It.
pub fn View::lives_with(self : View, owner : View) -> View {
  owner.owns(fn() {
    guard self.live() is Some(_) else { return }
    match self.parent() {
      Some(p) => p.drop(self)
      None => self.let_go()
    }
  })
  |> ignore
  self
}

///|
/// About which point of it a node is drawn bigger or smaller (View::scale): `At` shares of its width and height (0.5,
/// 0.5: its middle); `FromBeside` the edge of it toward what it goes beside (View::beside), on the side it went on as
/// it was last placed (the side it was said to go on before), where along it it is lined up: grown out of its anchor,
/// as a popover grows from what opened it (kit's grown_from). Not beside anything: its middle. `Drawn` the middle of what
/// it and what it holds draw, as they are laid out (the boxes of those with a ground, words, shapes, lines, a picture or
/// an old view of their own): what is grown and shrunk where it is, not about a page's width (a room opening on a line
/// to one side: reveal's, an old view's Ctx::held_look).
pub(all) enum Pivot {
  At(Double, Double)
  FromBeside
  Drawn
} derive(Eq, Show, Debug)

///|
/// Where node `self` is drawn bigger or smaller about, in points where it is its own, laid out `w` by `h`.
fn Node::pivot_at(self : Node, w : Double, h : Double) -> (Double, Double) {
  // (matched one after the other, no pair made: asked of every node drawn turned or scaled, each frame)
  match self.look.pivot {
    At(x, y) => (x * w, y * h)
    Drawn => (0.5 * w, 0.5 * h)
    FromBeside =>
      match self.beside {
        None => (0.5 * w, 0.5 * h)
        Some(b) => {
          let across = match b.along {
            Start => 0.0
            Middle => 0.5
            End => 1.0
          }
          let side = match self.went {
            Some(s) => s
            None => b.side
          }
          match side {
            Bottom => (across * w, 0.0)
            Top => (across * w, h)
            Right => (0.0, across * h)
            Left => (w, across * h)
          }
        }
      }
  }
}

///|
/// How big node `id` is drawn, its scale and its holders' (View::scale; 1: as laid out, or no live node): what its own
/// terms are worth in the window's (Tree::projected).
pub fn Tree::drawn_scale(self : Tree, id : NodeId) -> Double {
  if self.alive_id(id) {
    self.projected(id.at).3
  } else {
    1.0
  }
}

///|
/// How big it is drawn (Tree::drawn_scale's).
pub fn View::drawn_scale(self : View) -> Double {
  self.tree.drawn_scale(self.id())
}

///|
/// A finger or a button went down in the window at `at`, wherever it lands (the host's, before it goes to
/// what takes it): one change at that moment, told to what follows the window's presses (View::window_downs).
pub fn Tree::went_down(self : Tree, at : Double, x? : Double = -1.0, y? : Double = -1.0) -> Unit {
  self.event(at, fn() {
    let (count, _, _) = @signals.untracked(fn() { self.pressed_anywhere.get() })
    self.pressed_anywhere.set((count + 1, x, y))
    self.held_anywhere.set(true)
  })
}

///|
/// What went down in the window let go (or called off) at `at`, wherever it is: nothing held anywhere from then, told to
/// what follows it (View::window_held).
pub fn Tree::went_up(self : Tree, at : Double) -> Unit {
  self.event(at, fn() { self.held_anywhere.set(false) })
}

///|
/// Whether a finger or a button is down anywhere in the window now (an old view's `c.press().down`), followed: what
/// waits for the hand to carry no press (a hover card opens only on a pointer carrying none, from when it was let go).
pub fn View::window_held(self : View) -> Bool {
  self.tree.held_anywhere.get()
}

///|
/// How many times a finger or a button has gone down anywhere in the window (Tree::went_down), followed: what closes at
/// the next press, wherever it lands (a tip a finger held open, once let go).
pub fn View::window_downs(self : View) -> Int {
  self.tree.pressed_anywhere.get().0
}

///|
/// Where the most recent window press went down, in window coordinates, as the host told it.
pub fn View::window_down_point(self : View) -> (Double, Double) {
  let (_, x, y) = self.tree.pressed_anywhere.get()
  (x, y)
}

///|
/// A tap in the window at `at`, wherever it landed (the host's, as the old frame's Ctx::tapped_anywhere has one: a
/// press let go without dragging, not taken by what it went down on), told after what it landed on took it: one change
/// at that moment, told to what follows the window's taps (View::window_taps).
pub fn Tree::tapped(self : Tree, at : Double) -> Unit {
  self.event(at, fn() { self.tapped_anywhere.set(@signals.untracked(fn() { self.tapped_anywhere.get() }) + 1) })
}

///|
/// Whether a gesture's finger let go since this was last asked was its tap (View::gesture's: not moved past its slop,
/// not held, not called off), as what took it said it; asked, none since: the host's, to tell the window's taps by
/// (Tree::tapped).
pub fn Tree::gesture_tap_taken(self : Tree) -> Bool {
  let was = self.gesture_tapped
  self.gesture_tapped = false
  was
}

///|
/// How many taps there have been anywhere in the window (Tree::tapped), followed: what a tap anywhere lets go of (a tip
/// a finger tapped open).
pub fn View::window_taps(self : View) -> Int {
  self.tree.tapped_anywhere.get()
}


///|
/// Whether what a finger or a button at (`x`, `y`) of the window is for, as the tree is now, is this node (Tree::target_at:
/// the topmost drawn there that takes it, by the one projection): where a press let go lands, its own or another's.
pub fn View::finger_target(self : View, x : Double, y : Double) -> Bool {
  match self.tree.target_at(x, y) {
    Pressed(id) | Dragged(id) => id == self.id()
    _ => false
  }
}

///|
/// What its words measure and how they are drawn changed for all of them (the system's size of words, how the theme
/// shapes them): every node with words laid out and drawn again.
pub fn Tree::words_again(self : Tree) -> Unit {
  // (what shows words, and what is measured as what it hosts is: View::measured)
  for at, n in self.nodes {
    if n.live && (n.look.words != "" || n.flex.measure is Some(_)) {
      self.layout_marked_at(at)
      self.look_marked_at(at)
    }
  }
  self.words_redone.set(@signals.untracked(fn() { self.words_redone.get() }) + 1)
}

///|
/// How many times all its words were measured anew (Tree::words_again), followed: what is laid out by how wide its words
/// are and keeps something of it (a bar never narrower once open) says it again as they change.
pub fn View::words_redone(self : View) -> Int {
  self.tree.words_redone.get()
}

///|
/// What it draws called by name, as it changes (an icon's: "/icon/copy/", as an old view's icon is called), for what
/// finds things on screen by what they show (a test's, a scripted run's: Tester::locate's icon:NAME); drawn and read
/// out as ever.
#callsite(autofill(loc))
pub fn View::drawn_as(self : View, name : Live[String], loc~ : SourceLoc) -> View {
  self.bind(loc~, DrawnAs, name, Said, fn(s) { self.tree.nodes[self.at].look.drawn_as = s })
  self
}

///|
/// What node `id` draws called by name (View::drawn_as; "" none, or no live node).
pub fn Tree::drawn_name(self : Tree, id : NodeId) -> String {
  if self.alive_id(id) {
    self.nodes[id.at].look.drawn_as
  } else {
    ""
  }
}


///|
/// It laid out never narrower than it has been (a bar never narrower once open, as what it holds gives way or goes):
/// at each change of what `by` reads (what sets how wide it is laid out: its words, what it holds, the room, the
/// theme, the size of words), how wide it is laid out as of that change's own moment (View::laid_size), kept as its
/// least width, no more than `most` says it may be as that changes. Whatever frames are drawn between two changes, the
/// same: what is kept is what each change laid it out at, never what a frame happened to see.
#callsite(autofill(loc))
pub fn[T : Eq] View::keeps_width(
  self : View,
  by : () -> T,
  most? : () -> Double = fn() { @double.infinity },
  loc~ : SourceLoc,
) -> View {
  let widest : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  self.min_width(loc~,
    By(fn() {
      let w = widest.get()
      let m = most()
      if w <= 0.0 {
        None
      } else if w < m {
        Some(w)
      } else {
        Some(m)
      }
    }),
  )
  |> ignore
  // (the window's size among them: its first frame's too, the first it is laid out in)
  // (measured once for each change, once it is told whole: what else it tells made and set first (a node shown in it,
  // its words said again, told after this), whether a frame is drawn after it or not)
  let asked = Ref(false)
  self.reacts(fn() { (by(), self.window()) }, fn(_) {
    if asked.val {
      return
    }
    asked.val = true
    @signals.after_flush(fn() {
      asked.val = false
      // (laid out as of the change's moment, all it told counted: the layout's own, read and not placed by,
      // Tree::measured_now)
      guard self.live() is Some(n) else { return }
      self.tree.measured_now()
      let w = n.flex.width
      if w > @signals.untracked(fn() { widest.get() }) {
        widest.set(w)
      }
    })
  })
  self
}
