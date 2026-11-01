// A column that scrolls up and down in a node (View::scrolls), as an old view's box kept to a height does (ui's
// Ctx::capped): what it holds laid out as tall as it is, drawn off by how far it is scrolled and cut to the node, found
// by a finger or the pointer within the node alone; the wheel over any of it moves it while it can go that way (at its
// end the wheel goes on to what holds it: View::on_wheel_moves), a finger or the pointer held on any of it and moved up
// or down past the slop drags it (View::claims: what it went down on called off; across, or at its end, what holds it
// is asked) and, let go, flings it on, slowing; the focus come to what it holds brings that into sight once laid out
// (View::shows). As tall as what it holds
// where there is the room, it gives way (to nothing) where what holds it is short of room (a dialog no taller than the
// window), how far it can go told as it is laid out (View::laid_size_told). Where it is, a function of the time while
// flung, is the column's own (Scroll), let go with the node.

///|
/// A fling under way: set out from `x0` at `v0` (points a ms, down the column) at `t0`, at rest at `end_x` at `end_t`.
priv struct Fling {
  x0 : Double
  v0 : Double
  t0 : Double
  end_t : Double
  end_x : Double
} derive(Eq)

///|
/// How far a column that scrolls (View::scrolls) is scrolled: where it is at rest (or where a fling set out from), the
/// fling under way, how far it can go as last laid out, and the hand on it.
pub struct Scroll {
  priv x : @signals.Signal[Double]
  priv fling : @signals.Signal[Fling?]
  /// how far it can go, as laid out (told as all of the layout is done: the node's and what it holds' heights; none
  /// before they are first laid out)
  priv mut room : () -> Double?
  /// what ends the fling's settling at its end (View::at_moment's), as it is called off
  priv mut settle_off : () -> Unit
  /// where the hand held on it was last (the window's, down) and when, and how fast it went (points a ms, down the
  /// column)
  priv mut hand_y : Double
  priv mut hand_wy : Double
  priv mut hand_t : Double
  priv mut hand_v : Double
  /// taken over from what it went down on (View::claims): its first move from where it went down counted past the slop
  priv mut claimed : Bool
  /// what is told as it scrolls (its bar), at the moment
  priv mut on_scrolled : (Double) -> Unit
}

///|
/// A column's scroll, at its top.
pub fn Scroll::new() -> Scroll {
  {
    x: @signals.signal(0.0, same=fn(a, b) { a == b }),
    fling: @signals.signal(None, same=fn(a, b) { a == b }),
    room: fn() { None },
    settle_off: fn() {  },
    hand_y: 0.0,
    hand_wy: 0.0,
    hand_t: 0.0,
    hand_v: 0.0,
    claimed: false,
    on_scrolled: fn(_) {  },
  }
}

///|
/// How a fling slows: as an old view's box kept to a height does (ui's sideways_friction, a ms).
let scroll_friction : Double = 0.996

///|
/// The fastest fling (the window's points a ms): as an old view's list's (ui's max_fling, Android's 8000 dp/s).
let scroll_most_v : Double = 8.0

///|
/// How far before its top and its foot what it holds fades out, at most, where it goes on past them: as an old view's
/// box kept to a height's (ui's cut_soft_most).
let scroll_soft_most : Double = 24.0

///|
/// Below this (points a ms) a fling has stopped.
let scroll_stop_v : Double = 0.02

///|
/// How far a fling from `x0` at `v0` has gone `t` ms on, slowing by scroll_friction a ms: solved for the time, the same
/// at any frame rate.
fn scroll_fling_at(x0 : Double, v0 : Double, t : Double) -> Double {
  x0 + v0 * (@dmath.pow(scroll_friction, t) - 1.0) / @dmath.ln(scroll_friction)
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  dmax(lo, dmin(v, hi))
}

///|
/// Where it is at moment `t` (0 at its top, as far as it can go at most), as what is said of it now has it: followed
/// (where flung, the time: what reads it read again as it goes, till it is at rest).
fn Scroll::where_at(self : Scroll, t : Double) -> Double {
  let most = self.most_now()
  match self.fling.get() {
    Some(f) =>
      if t >= f.end_t {
        dclamp(f.end_x, 0.0, most)
      } else {
        dclamp(scroll_fling_at(f.x0, f.v0, t - f.t0), 0.0, most)
      }
    None => dclamp(self.x.get(), 0.0, most)
  }
}

///|
/// How far it is scrolled at the logic's moment of `tree` (the one it is in: what an event, a step or a test reads).
pub fn Scroll::at(self : Scroll, tree : Tree) -> Double {
  @signals.untracked(fn() { self.where_at(tree.logic_at()) })
}

///|
/// How far it can go, as it was last laid out (0 before it first is).
pub fn Scroll::most(self : Scroll) -> Double {
  @signals.untracked(fn() { self.most_now() })
}

///|
/// Whether what it holds is taller than it, as last laid out, followed (asked once it scrolls: View::scrolls): what is
/// painted by that alone reads it (cut at its box only while it scrolls, as @kit.in_room's held list), never what lays
/// it out.
pub fn Scroll::goes(self : Scroll) -> Bool {
  self.most_now() > 0.0
}

///|
/// How far it can go as last laid out, followed (0 before it first is).
fn Scroll::most_now(self : Scroll) -> Double {
  match (self.room)() {
    Some(r) => dmax(r, 0.0)
    None => 0.0
  }
}

///|
/// Stopped where it is at `t` (a fling under way stopped there): where that is.
fn Scroll::stopped(self : Scroll, t : Double) -> Double {
  let x = @signals.untracked(fn() { self.where_at(t) })
  if @signals.untracked(fn() { self.fling.get() }) is Some(f) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.fling.set(None)
    self.x.set(x)
    // (stopped on its way: it scrolled till now, no further: its bar's showing from here)
    if t < f.end_t {
      (self.on_scrolled)(t)
    }
  }
  self.x.set(x)
  x
}

///|
/// Moved by `d` (down the column) at `t`, as far as it can go: whether it moved.
fn Scroll::moved(self : Scroll, t : Double, d : Double) -> Bool {
  let was = self.stopped(t)
  let to = dclamp(was + d, 0.0, self.most())
  self.x.set(to)
  if to != was {
    (self.on_scrolled)(t)
  }
  to != was
}

///|
/// Brought to `to` at `t`, as far as it can go (a part of it brought into sight).
fn Scroll::sent(self : Scroll, t : Double, to : Double) -> Unit {
  let was = self.stopped(t)
  let to = dclamp(to, 0.0, self.most())
  self.x.set(to)
  if to != was {
    (self.on_scrolled)(t)
  }
}

///|
/// Let go of at `t` at the hand's speed: flung on (held by `v`, at rest at its end: then where it is, at rest), or at
/// rest where it is.
fn Scroll::flung(self : Scroll, v : View, t : Double) -> Unit {
  let x0 = self.stopped(t)
  let v0 = self.hand_v
  let speed = v0.abs()
  if speed <= scroll_stop_v {
    return
  }
  let most = self.most()
  let lf = @dmath.ln(scroll_friction)
  let t_stop = @dmath.ln(scroll_stop_v / speed) / lf
  // (the end it goes to, if it gets there first: f^t = 1 + d ln f / v0)
  let bound = if v0 > 0.0 { most } else { 0.0 }
  let arg = 1.0 + (bound - x0) * lf / v0
  let t_hit = if arg > 0.0 { @dmath.ln(arg) / lf } else { 1.0e300 }
  let (t_end, end_x) = if t_hit < t_stop {
    (t_hit, bound)
  } else {
    (t_stop, dclamp(scroll_fling_at(x0, v0, t_stop), 0.0, most))
  }
  if t_end <= 0.0 {
    return
  }
  let end_t = t + t_end.ceil()
  self.fling.set(Some({ x0, v0, t0: t, end_t, end_x }))
  (self.on_scrolled)(t)
  // (at rest at its end, said on the timeline: then nothing reads the time for it)
  self.settle_off = v.at_moment(end_t, fn() {
    self.settle_off = fn() {  }
    // (scrolled till its end: told so while it still counts as under way, its bar's showing from there)
    (self.on_scrolled)(end_t)
    self.fling.set(None)
    // (within how far it can go as of then: what holds it may have come to be shorter meanwhile)
    self.x.set(dclamp(end_x, 0.0, self.most()))
  })
}

///|
/// A column that scrolls up and down in it (see the file's head), `s` saying how far it is scrolled, `build` making
/// what it holds in the node that holds it all (laid out as tall as it is, drawn off by how far it is scrolled). It
/// gives way to nothing where what holds it is short of room (View::shrink, View::min_height). A hold that began on
/// what it holds is its own once it has moved `slop` (the window's points) up or down (View::claims). `bar`: its bar
/// along its right, as that says (scroll_bar.mbt; none: none).
pub fn View::scrolls(
  self : View,
  s : Scroll,
  build : (View) -> Unit,
  slop? : Double = 8.0,
  bar? : ScrollBar,
) -> View {
  guard self.live() is Some(_) else { return self }
  let inner : Ref[View?] = Ref(None)
  self.clips(Is(true)).bounds_input(Is(true)).shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (what it holds laid out as tall as it is, whatever room it has: its content's own height, as CSS's overflow scroll
  // has it)
  self.tree.nodes[self.at].flex.style.overflow = @flex.Overflow::Scroll
  self.tree.layout_marked_at(self.at)
  // (how far it can go: as tall as what it holds is, less as tall as it shows; told as laid out)
  s.room = fn() {
    match inner.val {
      Some(held) =>
        match (held.laid_size_told(), self.laid_size_told()) {
          (Some(h), Some(v)) => Some(h.1 - v.1)
          _ => None
        }
      None => None
    }
  }
  self.box(fn(held) {
    inner.val = Some(held)
    held
    .shrink(Is(0.0))
    .offset(By(fn() { (0.0, -s.where_at(if s.fling.get() is Some(_) { held.drawn_at() } else { 0.0 })) }))
    |> ignore
    build(held)
  })
  |> ignore
  // (its bar, over what it holds, told as it scrolls)
  match bar {
    Some(b) => {
      // (a fling under way: till its end, as it is now, none once stopped)
      let state = BarState::new(fn() {
        match s.fling.get() {
          Some(f) => f.end_t
          None => -1.0e9
        }
      })
      self.scroll_bar(s, b, state)
      s.on_scrolled = fn(t) { state.woke(b, self, t, scrolled=true) }
    }
    None => ()
  }
  // (what it holds faded out towards its top and its foot where it goes on past them, as far as it does, at most
  // scroll_soft_most: an old view's capped's fade_to; by the time while flung, as it is drawn)
  self.fades(By(fn() {
    let x = s.where_at(if s.fling.get() is Some(_) { self.drawn_at() } else { 0.0 })
    let most = s.most_now()
    (0.0, dclamp(x, 0.0, scroll_soft_most), 0.0, dclamp(most - x, 0.0, scroll_soft_most))
  }))
  |> ignore
  // (how far it can go told otherwise as it is laid out: where it is put within that, then and after, a fling under way
  // stopped where it is then; as an old view's box kept to a height is, sideways_after_layout)
  // (not laid out yet: how far it can go not known, nothing put)
  self.reacts(fn() { (s.room)().map(fn(r) { dmax(r, 0.0) }) }, fn(known) {
    guard known is Some(most) else { return }
    let t = self.tree.logic_at()
    if @signals.untracked(fn() { s.fling.get() }) is Some(_) && @signals.untracked(fn() { s.where_at(t) }) >= most {
      s.stopped(t) |> ignore
    }
    if @signals.untracked(fn() { s.x.get() }) > most {
      s.x.set(most)
    }
  })
  // (let go with it: no fling of it settles after)
  self.owns(fn() {
    // (a fling under way at rest where it was then: nothing reads the time for it after)
    match @signals.untracked(fn() { s.fling.get() }) {
      Some(f) => {
        let t = self.tree.logic_at()
        let at = if t >= f.end_t { f.end_x } else { scroll_fling_at(f.x0, f.v0, t - f.t0) }
        s.fling.set(None)
        s.x.set(at)
      }
      None => ()
    }
    (s.settle_off)()
    s.settle_off = fn() {  }
    s.room = fn() { None }
    s.on_scrolled = fn(_) {  }
  })
  |> ignore
  self
  // (the wheel up or down more than across, as an old view's box kept to a height takes it: sideways_wheel_moves)
  .on_wheel_moves(fn(w) { w.dy != 0.0 && w.dy.abs() >= w.dx.abs() && s.moved(w.at, w.dy) })
  // (a hold that began on what it holds (a button, a field of an old view's, nothing that takes a press) its own once
  // it moves up or down past the slop, more than across, the way it can still go: else what holds it is asked)
  .claims(fn(dx, dy) {
    let x = s.at(self.tree)
    let can = if dy < 0.0 { x < s.most() } else { x > 0.0 }
    let takes = dy.abs() > slop && dy.abs() >= dx.abs() && can
    s.claimed = takes
    takes
  }, scrolls=true)
  // (held, its own terms: what it holds moved as far as the hand, as big as it is drawn)
  .on_drag(fn(d) {
    match d.kind {
      Down => {
        s.stopped(d.at) |> ignore
        s.hand_y = d.y
        s.hand_wy = d.wy
        s.hand_t = d.at
        s.hand_v = 0.0
      }
      Moved => {
        // (taken over: the first move from where it went down past the slop alone, in the window's points, as big
        // in its own terms as it is drawn)
        let mut dy = d.y - s.hand_y
        let dw = d.wy - s.hand_wy
        if s.claimed && dw != 0.0 {
          s.claimed = false
          let past = if dw > 0.0 { dmax(dw - slop, 0.0) } else { dmin(dw + slop, 0.0) }
          dy = dy * past / dw
        }
        let dt = d.at - s.hand_t
        s.moved(d.at, -dy) |> ignore
        ignore(dt)
        s.hand_y = d.y
        s.hand_wy = d.wy
        s.hand_t = d.at
      }
      // (let go: flung at the finger's speed as of then, by its own events (Drag's `vy`: a pause before it let go, none),
      // no faster than a fling goes in the window's points, then in its own terms)
      Up => {
        let (_, _, sc) = self.tree.placed(self.at)
        s.hand_v = dclamp(-d.vy, -scroll_most_v, scroll_most_v) / (if sc > 0.0 { sc } else { 1.0 })
        s.flung(self, d.at)
      }
      Off => s.stopped(d.at) |> ignore
    }
  })
  // (a part of what it holds brought into sight: its top or its foot to its own, as little as that takes)
  .shows(fn(top, foot) {
    let t = self.logic_at()
    let vh = self.tree.nodes[self.at].flex.height
    let x = s.stopped(t)
    if top < 0.0 {
      s.sent(t, x + top)
    } else if foot > vh {
      s.sent(t, x + dmin(top, foot - vh))
    }
    s.at(self.tree) - x
  })
}
