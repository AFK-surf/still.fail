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
/// inside the window.
pub(all) struct Beside {
  anchor : NodeId
  side : Side
  along : Along
  offset : Double
  padding : Double
} derive(Eq, Debug)

///|
/// Placed beside node `anchor` (place_beside: on `side`, `offset` away, lined up `along` it, kept `padding` inside the
/// window, to the other side where it has not the room on its own), by where the anchor is and how big both are as the
/// tree is placed, each time it is: what it holds with it. Out of its holder's flow, as big as what it holds says (its
/// width, its words). Where the anchor is gone, where it is laid out.
pub fn View::beside(
  self : View,
  anchor : NodeId,
  side? : Side = Bottom,
  along? : Along = Middle,
  offset? : Double = 4.0,
  padding? : Double = 8.0,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.beside = Some({ anchor, side, along, offset, padding })
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
    // (where it is laid out, as if it went beside nothing: never where it went last)
    let n = self.nodes[at]
    let (lx, ly) = (n.lx, n.ly)
    self.place(at)
    if n.lx != lx || n.ly != ly {
      self.work.composed = self.work.composed + 1
      self.composed.push({ at, gen: n.gen })
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
    guard n.beside is Some(b) && self.alive_id(b.anchor) else {
      state[at] = 2
      return true
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
    guard self.window_place(b.anchor.at) is Some((ax, ay)) else {
      state[at] = 2
      return true
    }
    let a = self.nodes[b.anchor.at]
    let (hx, hy) = match self.window_place(n.parent) {
      Some(p) => p
      None => (0.0, 0.0)
    }
    let (x, y, _) = place_beside(
      (ax, ay, a.lw, a.lh),
      n.lw,
      n.lh,
      self.last_w,
      self.last_h,
      side=b.side,
      along=b.along,
      offset=b.offset,
      padding=b.padding,
    )
    let (lx, ly) = (x - hx, y - hy)
    if lx != n.lx || ly != n.ly {
      n.lx = lx
      n.ly = ly
      self.work.composed = self.work.composed + 1
      self.composed.push({ at, gen: n.gen })
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
/// Where node `at` is in the window as the tree is placed now (its own place and its holders'), none where it is no
/// live node.
fn Tree::window_place(self : Tree, at : Int) -> (Double, Double)? {
  if at < 0 || at >= self.nodes.length() || !self.nodes[at].live {
    return None
  }
  let mut x = 0.0
  let mut y = 0.0
  let mut i = at
  while i >= 0 {
    let m = self.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
    }
    i = m.parent
  }
  Some((x, y))
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
