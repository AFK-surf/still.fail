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
    // (where its anchor is drawn and how big, where what holds it is: in the window's terms as the scene is composed,
    // Tree::projected; it goes there as big as what holds it draws it, its own scale about where it went after)
    guard self.window_place(b.anchor.at) is Some((ax, ay, ascale)) else {
      state[at] = 2
      return true
    }
    let a = self.nodes[b.anchor.at]
    let (hx, hy, hs) = match self.window_place(n.parent) {
      Some(p) => p
      None => (0.0, 0.0, 1.0)
    }
    let (x, y, went) = place_beside(
      (ax, ay, a.lw * ascale, a.lh * ascale),
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
    n.went = Some(went)
    let (px, py) = n.pivot_at(n.lw, n.lh)
    let (lx, ly) = ((x - hx) / hs, (y - hy) / hs)
    if lx != n.lx || ly != n.ly || px != n.lpx || py != n.lpy {
      n.lx = lx
      n.ly = ly
      n.lpx = px
      n.lpy = py
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
/// as a popover grows from what opened it (kit's grown_from). Not beside anything: its middle.
pub(all) enum Pivot {
  At(Double, Double)
  FromBeside
} derive(Eq, Show, Debug)

///|
/// Where node `self` is drawn bigger or smaller about, in points where it is its own, laid out `w` by `h`.
fn Node::pivot_at(self : Node, w : Double, h : Double) -> (Double, Double) {
  let (sx, sy) = match (self.look.pivot, self.beside) {
    (At(x, y), _) => (x, y)
    (FromBeside, Some(b)) => {
      let across = match b.along {
        Start => 0.0
        Middle => 0.5
        End => 1.0
      }
      match self.went.unwrap_or(b.side) {
        Bottom => (across, 0.0)
        Top => (across, 1.0)
        Right => (0.0, across)
        Left => (1.0, across)
      }
    }
    (FromBeside, None) => (0.5, 0.5)
  }
  (sx * w, sy * h)
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
/// An old view hosted (View::hosted) drawn bigger or smaller (`s`, its holders' scale and its own: View::scale) is not
/// done: what it draws, where it takes a finger, where its words are selected and where a host is told it covers are
/// its own, as big as it is laid out, none of them told of a scale yet. Refused where the scene is composed or a node's
/// place asked, whichever came first (a scale said and an old view put in it after, or the other way round), not drawn
/// otherwise than it says.
fn hosted_unscaled(n : Node, s : Double) -> Unit {
  if n.hosted && s != 1.0 {
    hosted_refused(s)
  }
}

///|
/// An old view hosted in what is drawn `s` as big: refused (hosted_unscaled). Said where it comes about: as an old view
/// is put in what is said to be drawn scaled (View::hosted), as what holds one is said to be (View::scale), however
/// either came (made, shown, its scale changed); where the scene is gone through, as what holds besides.
fn hosted_refused(s : Double) -> Unit {
  (refused_so.val)("an old view hosted in what is drawn \{s} as big: View::scale holds no old view")
}

///|
/// What a refusal does (hosted_refused): stops the program, saying why; a test told of each in its place, to say which
/// were refused and when.
pub let refused_so : Ref[(String) -> Unit] = Ref(fn(why) { abort(why) })

///|
/// The scale of what holds node `at` (it too) that is drawn other than as big as laid out, the first of them up from
/// it, as it is said now (View::scale); none where all are whole.
fn Tree::scale_over(self : Tree, at : Int) -> Double? {
  let mut i = at
  while i >= 0 {
    let s = self.nodes[i].look.scale
    if s != 1.0 {
      return Some(s)
    }
    i = self.nodes[i].parent
  }
  None
}

///|
/// Whether node `at` or what it holds is an old view hosted (View::hosted).
fn Tree::hosts_within(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  n.live && (n.hosted || n.kids.iter().any(fn(k) { self.hosts_within(k) }))
}
