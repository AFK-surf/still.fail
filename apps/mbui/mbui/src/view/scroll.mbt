// A column that scrolls up and down in a node (View::scrolls), as an old view's box kept to a height does (ui's
// Ctx::capped): what it holds laid out as tall as it is, drawn off by how far it is scrolled and cut to the node, found
// by a finger or the pointer within the node alone; the wheel over any of it moves it while it can go that way (at its
// end the wheel goes on to what holds it: View::on_wheel_moves), a finger or the pointer held on any of it and moved up
// or down past the slop drags it (View::claims: what it went down on called off; across, or at its end, what holds it
// is asked) and, let go, flings it on, slowing; the focus come to what it holds brings that into sight once laid out
// (View::shows). As tall as what it holds
// where there is the room, it gives way (to nothing) where what holds it is short of room (a dialog no taller than the
// window). Where it is is the column's own (Scroll), let go with the node: a function of the time while it goes by
// itself, and of how far it can go as it is laid out then, read plainly as the tree is placed (what it holds drawn off
// by it, Live's Placed) and as an event comes, never told back as a change of its own (docs/retained.md rule 10). One
// made as a page's list (Scroll::list) moves as an old view's list does on the platform it is on instead
// (scroll_list.mbt). One made to scroll across (Scroll::across) is a row that scrolls sideways the same way (an old
// view's Ctx::sideways): along its width, the wheel and a hold across, its bar along its foot, what holds it asked what
// goes up or down.

///|
/// A fling under way: set out from `x0` at `v0` (points a ms, down the column) at `t0`, at rest at `end_x` at `end_t`;
/// a page's list's its platform's way (none: a box kept to a height's).
priv struct Fling {
  x0 : Double
  v0 : Double
  t0 : Double
  end_t : Double
  end_x : Double
  /// the end it went toward as it set out: its top, or its foot as far as it could go then
  till : Double
  way : ListWay?
}

///|
/// Brought on by the hand held past its edge (Scroll::edge_toward): from `x0` at `t0`, `v` points a ms, steady, as far
/// as it can go that way (its top, or its foot as it is laid out: Edge::at), after which `parked` there (at `x0`, still
/// said: on from there as the hand is moved again).
priv struct Edge {
  x0 : Double
  v : Double
  t0 : Double
  parked : Bool
}

///|
/// How far a column that scrolls (View::scrolls) is scrolled: where it is at rest (or where a fling set out from), the
/// fling under way, how far it can go as last laid out, and the hand on it.
pub struct Scroll {
  priv x : @signals.Signal[Double]
  priv fling : @signals.Signal[Fling?]
  /// how far it can go, as laid out last (the node's and what it holds' heights, read plainly; none before they are
  /// first laid out)
  priv mut room : () -> Double?
  /// a page's list's fling down toward its foot as it meets that foot where it is laid out now (Scroll::fling_now): the
  /// fling said, the foot it was worked out for, and how it goes then; kept for the same of both
  priv mut met : (Fling, Double, Fling)?
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
  /// The hand's requested distance, before it moves or any new layout measures what it brings into sight.
  priv mut on_hand : (Double) -> Unit
  /// which column it is, of all made (what hosts the tree tells its glides by: Tree::on_glides)
  priv serial : Int
  /// it moves as a page's list does on the platform it is on (Scroll::list): what shows past its ends, pulled there or
  /// going back (none: nothing)
  priv as_list : Bool
  priv past : @signals.Signal[Past?]
  /// a page's list's wheel's notches easing in (none: none)
  priv notch : @signals.Signal[Notch?]
  /// how tall it is as laid out (its own points), as it is asked
  priv mut tall : () -> Double
  /// the node it scrolls in, while it is (View::scrolls): what it is on by itself said on its timeline
  priv mut host : View?
  /// it scrolls across, along its width (Scroll::across: a row that scrolls sideways), not up and down: what is said
  /// down the column above said along the row, its start for its top
  priv across : Bool
  /// brought on by the hand held past its edge (Scroll::edge_toward), while it is said
  priv edge : @signals.Signal[Edge?]
  /// The editor these choices belong to, whose input method stays while they are scrolled.
  priv mut for_field : NodeId?
  /// a page's list's blocks (View::scrolls_window): the first and last of them in sight, by their places, it put with
  /// one of them at its top, by its place, and how far past the first in sight's top it is (what a test reads and asks
  /// of an old view's list)
  priv mut rows : ((() -> (Int, Int)), (Int) -> Unit, () -> Double, (Int) -> (Double, Double, Double, Double)?)?
}

///|
/// Columns' scrolls made: each one's own number (Scroll's `serial`).
// kept across runs: it goes on counting
let scrolls_made : Ref[Int] = Ref(0)

///|
/// A column's scroll, at its top: as an old view's box kept to a height scrolls (ui's Ctx::capped).
pub fn Scroll::new() -> Scroll {
  Scroll::made(false)
}

///|
/// A row's scroll, at its start: across, as an old view's box scrolled sideways does (ui's Ctx::sideways).
pub fn Scroll::across() -> Scroll {
  Scroll::made(false, across=true)
}

///|
/// The editor node whose choices scroll in `id`, if it still exists. A host keeps that editor's keyboard when a
/// finger scrolls its choices; another editor's keyboard is dismissed as for any other scrolling column.
pub fn Tree::scrolls_for(self : Tree, id : NodeId) -> NodeId? {
  guard self.alive_id(id) else { return None }
  match self.scrolls_at.get(id.at).bind(fn(s) { s.for_field }) {
    Some(f) if self.alive_id(f) => Some(f)
    _ => None
  }
}

///|
/// A column's scroll, at its top: as a page's list on the platform it is on (scroll_list.mbt).
pub fn Scroll::list() -> Scroll {
  Scroll::made(true)
}

///|
fn Scroll::made(as_list : Bool, across? : Bool = false) -> Scroll {
  {
    across,
    x: @signals.signal(0.0, same=fn(a, b) { a == b }),
    fling: @signals.signal(None, same=fn(a, b) { same_ref(a, b) }),
    room: fn() { None },
    met: None,
    settle_off: fn() {  },
    hand_y: 0.0,
    hand_wy: 0.0,
    hand_t: 0.0,
    hand_v: 0.0,
    claimed: false,
    on_scrolled: fn(_) {  },
    on_hand: fn(_) { },
    serial: {
      scrolls_made.val += 1
      scrolls_made.val
    },
    as_list,
    past: @signals.signal(None, same=fn(a, b) { same_ref(a, b) }),
    notch: @signals.signal(None, same=fn(a, b) { same_ref(a, b) }),
    tall: fn() { 0.0 },
    host: None,
    edge: @signals.signal(None, same=fn(a, b) { same_ref(a, b) }),
    for_field: None,
    rows: None,
  }
}

///|
/// The same one, or both none.
fn[T] same_ref(a : T?, b : T?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
/// When the glide it is on now ends, on the tree's timeline (let go at a speed: View::scrolls' fling), as it is now:
/// none at rest, held, or stopped (pressed again, the wheel, what it holds shorter, let go of).
pub fn Scroll::glides_till(self : Scroll) -> Double? {
  @signals.untracked(fn() { self.rest_now() })
}

///|
/// The same end, followed as a glide starts, changes or ends. For an observation of the page's reading position;
/// a layout deciding where to put its contents uses glides_till without following its own scroll changes.
pub fn Scroll::glides_till_told(self : Scroll) -> Double? {
  self.rest_now()
}

///|
/// When what it is on by itself now ends (a fling, what it meets its end with going back; what shows past an end going
/// back), followed: none at rest or held.
fn Scroll::rest_now(self : Scroll) -> Double? {
  // (the hand past its edge: at its end as said now; at rest there, parked)
  match self.edge.get() {
    Some(e) => return if e.parked { None } else { Some(e.end_at(self.most_now())) }
    None => ()
  }
  match self.flung_now() {
    Some(f) =>
      match f.way {
        Some({ hit: Some({ back: Some(p), .. }), .. }) => Some(p.rest)
        _ => Some(f.end_t)
      }
    // (a page's list's notches easing in and what shows past an end going back, each its own: at rest as the later is)
    None => {
      let eased = self.notch.get().map(fn(n) { n.t0 + ease_end(n.total, n.v0) })
      let back = match self.past.get() {
        Some({ back: Some(p), .. }) => Some(p.rest)
        _ => None
      }
      match (eased, back) {
        (Some(a), Some(b)) => Some(dmax(a, b))
        (a, None) => a
        (None, b) => b
      }
    }
  }
}

///|
/// The fling under way as it goes now, followed (what is said of it; how far it can go read plainly, as it is laid out
/// now): Scroll::fling_met.
fn Scroll::flung_now(self : Scroll) -> Fling? {
  match self.fling.get() {
    Some(f) => Some(self.fling_met(f, self.most_now()))
    None => None
  }
}

///|
/// Fling `f` as it goes where it can go as far as `most`: a page's list's down toward its foot meets that foot where it
/// is (worked out again from where it set out, as that comes out otherwise than it went toward it: rows under what shows
/// measured anew, come or gone; past it already, met as it set out), what it brings past it going back from then; kept
/// for the same fling and foot (Scroll's `met`). Any other as it was said.
fn Scroll::fling_met(self : Scroll, f : Fling, most : Double) -> Fling {
  guard f.way is Some(w) && f.v0 > 0.0 && f.till != most else { return f }
  match self.met {
    Some((from, foot, g)) if physical_equal(from, f) && foot == most => return g
    _ => ()
  }
  let density = w.px / dmax(w.h, 1.0)
  let g = if most <= f.x0 {
    met_now(f, w, f.t0, most, density)
  } else {
    match list_planned(f.t0, f.x0, f.v0, w, w.same, density, most) {
      Some(g) => g
      // (going nowhere toward it: at rest where it set out)
      None => { ..f, end_t: f.t0, end_x: f.x0, till: most, way: Some({ ..w, hit: None }) }
    }
  }
  self.met = Some((f, most, g))
  g
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
  match self.edge.get() {
    Some(e) => return dclamp(e.at(t, most), 0.0, most)
    None => ()
  }
  match self.flung_now() {
    Some(f) =>
      if t >= f.end_t {
        dclamp(f.end_x, 0.0, most)
      } else {
        match f.way {
          Some(w) => dclamp(w.at(f, t), 0.0, most)
          None => dclamp(scroll_fling_at(f.x0, f.v0, t - f.t0), 0.0, most)
        }
      }
    None =>
      match self.notch.get() {
        // (set out from under its top, what it holds shown lower than it lies (Scroll::glide_under): from there)
        Some(n) => dclamp(n.x0 + ease_come(n.total, n.v0, t - n.t0), dmin(0.0, n.x0), most)
        None => dclamp(self.x.get(), 0.0, most)
      }
  }
}

///|
/// How far it is scrolled at the logic's moment of `tree` (the one it is in: what an event, a step or a test reads).
pub fn Scroll::at(self : Scroll, tree : Tree) -> Double {
  @signals.untracked(fn() { self.where_at(tree.logic_at()) })
}

///|
/// How far it is scrolled as what is drawn is drawn, followed: where it is on by itself (a fling, a page's list's wheel's
/// notches easing in), read again as the time goes till it is at rest; else as it stands. What works out what of what
/// it holds to make as it scrolls (a page's list built by the rows in sight) reads it so, never its own copy of how it
/// moves. Not what shows past an end (iOS's rubber band, Android's stretch: Scroll::past).
pub fn Scroll::drawn(self : Scroll, tree : Tree) -> Double {
  self.where_at(if self.goes_on() { tree.drawn_at() } else { 0.0 })
}

///|
/// What it holds above where it is grew by `d` (less, where less than 0: rows above those in sight measured anew, come
/// or gone), as of the logic's moment, a page's list's alone (Scroll::list): where it is and what it is on by itself
/// moved by as much, so what is in sight stays where it is drawn; a wheel's notches easing in go on as they were; a
/// fling goes on as it was from where it set out moved as much, its foot moved as much, its top where it is: where it
/// meets the end it goes to worked out again (later, sooner, or not at all, its top moved away from it or toward it),
/// what it brings past that end from then, at rest then. No scroll of the hand's: nothing told as scrolled (its bar).
/// What shows past an end stays as it is.
pub fn Scroll::grew_above(self : Scroll, d : Double) -> Unit {
  guard self.as_list else { abort("Scroll::grew_above: a page's list's (Scroll::list) alone") }
  if d == 0.0 {
    return
  }
  @signals.untracked(fn() {
    let t = match self.host {
      Some(v) => v.logic_at()
      None => 0.0
    }
    self.x.set(self.x.get() + d)
    // (the hand past its edge: where it has it now as much further, on from there by its own way as far as it can go as
    // it is laid out: at its foot it is at its foot still; at its top, on to it again)
    match (self.edge.get(), self.host) {
      (Some(e), Some(v)) => self.edge_planned(v, e, e.at(t, self.most_now()) + d, t)
      _ => ()
    }
    match self.fling.get() {
      Some({ way: Some(w), .. } as f) => self.fling_grew(f, w, t, d)
      _ => ()
    }
    match self.notch.get() {
      Some(n) => self.notch.set(Some({ ..n, x0: n.x0 + d }))
      None => ()
    }
    // (at rest when it now is: said again on its timeline)
    match self.host {
      // (the hand past its edge: said on by its own way, above)
      Some(_) if self.edge.get() is Some(_) => ()
      // (a fling down toward its foot meets it where it is laid out as this change leaves it, as it is read:
      // Scroll::fling_met)
      Some(v) => self.list_settles(v, t)
      None => ()
    }
  })
}

///|
/// How far it can go, as it was last laid out (0 before it first is): read plainly, at an event, as it is placed or
/// painted (Live's Placed), never followed.
pub fn Scroll::most(self : Scroll) -> Double {
  @signals.untracked(fn() { self.most_now() })
}

///|
/// Whether what it holds is taller than it (wider, across), as last laid out (asked once it scrolls: View::scrolls),
/// read plainly: what is placed or painted by that alone reads it, as it is placed (Live's Placed: cut at its box only
/// while it scrolls, as @kit.in_room's held list), never what lays it out.
pub fn Scroll::goes(self : Scroll) -> Bool {
  self.most() > 0.0
}

///|
/// Whether it has a bar to show (View::scrolls' `bar`): what it holds more than a point past what shows, as last laid
/// out, as ui's bar_drawn has it; read plainly.
fn Scroll::has_bar(self : Scroll) -> Bool {
  self.most() > 1.0
}

///|
/// How far it can go as last laid out, read plainly (0 before it first is).
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
  // (brought on past its edge: as far as it came)
  if @signals.untracked(fn() { self.edge.get() }) is Some(e) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.edge.set(None)
    self.x.set(x)
    if !e.parked {
      (self.on_scrolled)(t)
    }
  }
  // (a page's list's notches easing in: as far as they came)
  if @signals.untracked(fn() { self.notch.get() }) is Some(_) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.notch.set(None)
  }
  if @signals.untracked(fn() { self.flung_now() }) is Some(f) {
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
/// Put at `to` (down the column) at the logic's moment of the tree it scrolls in, read as far as it can go as it is
/// laid out (a list's first place, past what is tucked over its rows; its top again): what it was on by itself stopped
/// there, no scroll of the hand's (nothing told as scrolled: its bar). Not scrolling in a node yet, there as it comes to.
pub fn Scroll::put(self : Scroll, to : Double) -> Unit {
  match self.host {
    Some(v) if v.alive() => self.stopped(v.tree.logic_at()) |> ignore
    _ => ()
  }
  self.x.set(dmax(to, 0.0))
}

///|
/// Moved by `d` (down the column) at `t`, as far as it can go: whether it moved.
fn Scroll::moved(self : Scroll, t : Double, d : Double) -> Bool {
  let was = self.stopped(t)
  let to = dclamp(was + d, 0.0, self.most())
  if to != was { (self.on_hand)(to - was) }
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
  self.fling.set(Some({ x0, v0, t0: t, end_t, end_x, till: bound, way: None }))
  (self.on_scrolled)(t)
  // (what hosts the tree told it glides, which column it is and how to ask it when it ends now: Tree::on_glides)
  (v.tree.glides)(self.serial, fn() { self.glides_till() })
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
/// Gone on by itself at `speed` (points a ms, down the column or along the row; less than 0 toward its top or its
/// start) from where it is at the logic's moment, steady, till its end, as the hand held past its edge takes it (a
/// selection dragged out of it: an old view's select_edge); 0 stopped where it is. Said anew as the hand moves, it goes
/// on from where it is then at the new speed: where it is a function of the time, nothing stepped by frames. Not where
/// it scrolls in nothing (View::scrolls not said, or let go).
pub fn Scroll::edge_toward(self : Scroll, speed : Double) -> Unit {
  guard self.host is Some(v) else { return }
  @signals.untracked(fn() {
    let t = v.logic_at()
    let x0 = self.stopped(t)
    if speed == 0.0 {
      return
    }
    // (from where it is, as far as it can go that way: its end said)
    self.edge_planned(v, { x0, v: speed, t0: t, parked: false }, x0, t)
  })
}

///|
/// Where the hand past its edge has it at `t`, as far as it can go that way where it can go as far as `most`.
fn Edge::at(self : Edge, t : Double, most : Double) -> Double {
  if self.parked {
    return self.x0
  }
  let x = self.x0 + self.v * (dmax(t, self.t0) - self.t0)
  if self.v > 0.0 {
    dmin(x, most)
  } else {
    dmax(x, 0.0)
  }
}

///|
/// When the hand past its edge has it as far as it can go that way where it can go as far as `most` (steady from where
/// it set out, at a whole ms).
fn Edge::end_at(self : Edge, most : Double) -> Double {
  let bound = if self.v > 0.0 { most } else { 0.0 }
  self.t0 + dmax(0.0, (bound - self.x0) / self.v).ceil()
}

///|
/// The hand past its edge (`e`, as it was) said on from `x0` at `t` as far as it can go that way: its end said on the
/// timeline, told what hosts the tree (Tree::on_glides), parked there; there already, parked now.
fn Scroll::edge_planned(self : Scroll, v : View, e : Edge, x0 : Double, t : Double) -> Unit {
  (self.settle_off)()
  self.settle_off = fn() {  }
  let g = { x0, v: e.v, t0: t, parked: false }
  let most = self.most_now()
  let end_t = g.end_at(most)
  if end_t <= t {
    // (at its end: nothing moving, nothing reading the time; told so as it is there no more since now)
    self.edge.set(Some({ ..g, x0: g.at(t, most), parked: true }))
    if !e.parked {
      (self.on_scrolled)(t)
    }
    return
  }
  self.edge.set(Some(g))
  (self.on_scrolled)(t)
  // (what hosts the tree told it goes on by itself, till when as it is asked: Tree::on_glides)
  (v.tree.glides)(self.serial, fn() { self.glides_till() })
  self.edge_settles(v, end_t)
}

///|
/// The hand past its edge at its end, said on the timeline at `end_t`: as far as it can go then as it is laid out then,
/// parked there (told so); laid out further meanwhile, said again at its end then.
fn Scroll::edge_settles(self : Scroll, v : View, end_t : Double) -> Unit {
  self.settle_off = v.at_moment(end_t, fn() {
    self.settle_off = fn() {  }
    guard @signals.untracked(fn() { self.edge.get() }) is Some(g) && !g.parked else { return }
    let most = self.most_now()
    let end = g.end_at(most)
    if end > end_t {
      self.edge_settles(v, end)
      return
    }
    (self.on_scrolled)(end_t)
    self.edge.set(Some({ ..g, x0: g.at(end_t, most), t0: end_t, parked: true }))
  })
}

///|
/// What scrolls it or holds it nearest, up and down (`across` false) or across (Scroll::across): the column or the row
/// a hand held past its edge brings on (Scroll::edge_toward); none where nothing round it does.
pub fn View::scroll_holding(self : View, across? : Bool = false) -> Scroll? {
  // (a node let go of: nothing, whatever is in its place now)
  guard self.alive() else { return None }
  let mut at = self.at
  while at >= 0 {
    match self.tree.scrolls_at.get(at) {
      Some(s) if s.across == across && (s.host is Some(h) && h.alive()) => return Some(s)
      _ => ()
    }
    at = self.tree.nodes[at].parent
  }
  None
}

///|
/// A column that scrolls up and down in it (see the file's head), `s` saying how far it is scrolled, `build` making
/// what it holds in the node that holds it all (laid out as tall as it is, drawn off by how far it is scrolled). It
/// gives way to nothing where what holds it is short of room (View::shrink, View::min_height). A hold that began on
/// what it holds is its own once it has moved `slop` (the window's points) up or down (View::claims; none: 8, a page's
/// list's its platform's, list_slop). `bar`: its bar
/// along its right, as that says (scroll_bar.mbt; none: none). Scrolling across (Scroll::across): a row, what it holds
/// laid out as wide as it is, given way to nothing across where what holds it is narrower; a hold its own once it moves
/// across past the slop; its bar along its foot, `bar_in` in from either end (under what it is for, where what it holds
/// reaches past that: Ctx::sideways's), room under what it holds for it while it can go (its bar never over what it
/// holds' last line), none while it cannot. `for_field`: the editor these choices belong to; scrolling keeps
/// that editor's keyboard, as an old view's capped column does. `content_extent`: a virtual list's counted content
/// height (width across), available when its heights change, before those heights have been laid out in its holder.
/// `bar_clear`: the top and foot room kept clear by the scroll bar.
pub fn View::scrolls(
  self : View,
  s : Scroll,
  build : (View) -> Unit,
  slop? : Double,
  bar? : ScrollBar,
  bar_in? : Double = 0.0,
  for_field? : NodeId,
  content_extent? : () -> Double,
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
) -> View {
  guard self.live() is Some(_) else { return self }
  // (a page's list's as its platform's is as it is held: what hosts the tree may say it after it is made)
  let slop = fn() {
    match slop {
      Some(v) => v
      None => if s.as_list { list_slop((self.tree.list_feel)().0) } else { 8.0 }
    }
  }
  s.host = Some(self)
  s.for_field = for_field
  // (found by what it holds: View::scroll_holding)
  self.tree.scrolls_at[self.at] = s
  let across = s.across
  // (how tall it is, as it is asked: what shows past its ends is in its heights; across, how wide)
  s.tall = fn() { if self.live() is Some(n) { if across { n.flex.width } else { n.flex.height } } else { 0.0 } }
  let inner : Ref[View?] = Ref(None)
  self.clips(Is(true)).bounds_input(Is(true)) |> ignore
  // (across: a row, what it holds laid out along it as wide as it is; narrower than that where what holds it is)
  if across {
    self.row(Is(true)).min_width(Is(Some(0.0))) |> ignore
  } else {
    self.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  }
  // (what it holds laid out as tall as it is, whatever room it has: its content's own height, as CSS's overflow scroll
  // has it)
  self.tree.nodes[self.at].flex.style.overflow = @flex.Overflow::Scroll
  // (across with a bar: room at its foot for it while what it holds runs past it, none while it does not, laid out with
  // what it holds in the one pass (Style's gutter: its padding there counted, the bar over that), never over what it
  // holds' last line: Ctx::sideways's bar_room)
  match bar {
    Some(b) if across => self.tree.nodes[self.at].flex.style.gutter = b.size + 2.0 * b.inset
    _ => ()
  }
  self.tree.layout_marked_at(self.at)
  // (how far it can go: as tall as what it holds is, less as tall as it shows, as they are laid out, read plainly; as it
  // was last laid out where it is laid out nowhere now (left out of its row, let go): none before it first is)
  let kept_room : Ref[Double?] = Ref(None)
  s.room = fn() {
    let now = match self.live() {
      Some(n) if n.placed && !self.tree.out_at(self.at) => {
        let own = if across { n.flex.width } else { n.flex.height }
        match content_extent {
          // (counted by what lays it out, in the same pass as it is laid out: as tall as it is counted now)
          Some(extent) => Some(extent() - own)
          None =>
            match inner.val.bind(fn(h) { h.live() }) {
              Some(h) if h.placed => Some((if across { h.flex.width } else { h.flex.height }) - own)
              _ => None
            }
        }
      }
      _ => None
    }
    match now {
      Some(_) => {
        kept_room.val = now
        now
      }
      None => kept_room.val
    }
  }
  self.box(fn(held) {
    inner.val = Some(held)
    self.tree.nodes[self.at].scroll_held = held.at
    self.tree.nodes[self.at].scroll_across = across
    // (a page's list's rows set on its host's pixels as an old view's list's are: Tree::set_rows_grid)
    if s.as_list && !across {
      self.tree.rows_list(held.at)
    }
    // (drawn off by where it is as the tree is placed, within how far it can go as it is laid out then: Live's Placed)
    held
    .shrink(Is(0.0))
    .offset(Placed(fn() {
      let t = if s.goes_on() { held.drawn_at() } else { 0.0 }
      // (a page's list's on iOS moved past its end as far as its rubber band shows it)
      if across {
        (-s.where_at(t), 0.0)
      } else {
        (0.0, -s.where_at(t) + s.past_moved(t))
      }
    }))
    |> ignore
    build(held)
  })
  |> ignore
  // (its bar, over what it holds, told as it scrolls)
  match bar {
    Some(b) => {
      // (a fling under way: till its end, as it goes now, none once stopped)
      let state = BarState::new(fn() {
        match (s.flung_now(), s.edge.get()) {
          (Some(f), _) => f.end_t
          // (the hand past its edge: till its end as it goes now; parked, since it came there)
          (None, Some(e)) => if e.parked { e.t0 } else { e.end_at(s.most_now()) }
          (None, None) => -1.0e9
        }
      })
      self.scroll_bar(s, b, state, bar_in~, bar_clear~)
      s.on_scrolled = fn(t) { state.woke(b, self, t, scrolled=true) }
    }
    None => ()
  }
  // (what it holds faded out towards its top and its foot where it goes on past them, as far as it does, at most
  // scroll_soft_most: an old view's capped's fade_to; by the time while flung, as it is drawn)
  // (a page's list's not, as an old view's list's is not; stretched instead where Android's is past an end, as it is
  // drawn: View::stretches)
  if s.as_list {
    self.stretches(Placed(fn() { s.stretch_drawn(if s.goes_on() { self.drawn_at() } else { 0.0 }) })) |> ignore
  } else {
    self.fades(Placed(fn() {
      // (where it is as drawn, the time read while what it is on by itself has an end said: Scroll::rest_now)
      let x = s.where_at(if s.rest_now() is Some(_) { self.drawn_at() } else { 0.0 })
      let most = s.most_now()
      let (a, b) = (dclamp(x, 0.0, scroll_soft_most), dclamp(most - x, 0.0, scroll_soft_most))
      // (across: towards its start and its end)
      if across {
        (a, 0.0, b, 0.0)
      } else {
        (0.0, a, 0.0, b)
      }
    }))
    |> ignore
  }
  // (how far it can go laid out otherwise: where it is shown within that as it is placed (Scroll::where_at), what it is
  // on by itself meeting its end where that is now (Scroll::fling_met), at rest within it as it comes to rest; where it
  // was put kept as it was said, as far as it can go as the hand next moves it: nothing told back of how it is laid out)
  // (let go with it: no fling of it settles after)
  self.owns(fn() {
    // (what it was on by itself (the hand past its edge, a fling, a page's list's notches easing in) at rest where it had
    // it then, as far as it could go as it was last laid out: nothing reads the time for it after)
    @signals.untracked(fn() {
      if s.edge.get() is Some(_) || s.fling.get() is Some(_) || s.notch.get() is Some(_) {
        let at = s.where_at(self.tree.logic_at())
        s.edge.set(None)
        s.fling.set(None)
        s.notch.set(None)
        s.x.set(at)
      }
    })
    s.met = None
    // (what shows past an end of a page's list gone with it, going back or not: nothing of it at rest after)
    s.past.set(None)
    (s.settle_off)()
    s.settle_off = fn() {  }
    s.room = fn() { None }
    s.tall = fn() { 0.0 }
    s.host = None
    s.for_field = None
    match self.tree.scrolls_at.get(self.at) {
      Some(o) if physical_equal(o, s) => self.tree.scrolls_at.remove(self.at)
      _ => ()
    }
    s.on_scrolled = fn(_) {  }
    // (no glide of it told any more: Tree::on_glides)
    (self.tree.glides_gone)(s.serial)
  })
  |> ignore
  self
  // (the wheel up or down more than across, as an old view's box kept to a height takes it: sideways_wheel_moves)
  .on_wheel_moves(fn(w) {
    // (across: the wheel across more than up or down, as an old view's box scrolled sideways takes it, as far as it
    // goes that way: sideways_wheel_moves)
    if across {
      guard w.dx != 0.0 && w.dx.abs() >= w.dy.abs() else { return false }
      return s.moved(w.at, w.dx)
    }
    guard w.dy != 0.0 && w.dy.abs() >= w.dx.abs() else { return false }
    // (a page's list's fling stopped as the wheel comes, what shows past an end going on back as it was)
    // (a wheel's notch eased in, as an old view's list's is: Ctx::ease_list)
    if s.as_list {
      s.wheel_stops(self, w.at)
      if (w.mods & wheel_notch) != 0 {
        return s.notched(self, w.at, w.dy)
      }
    }
    s.moved(w.at, w.dy)
  })
  // (a hold that began on what it holds (a button, a field of an old view's, nothing that takes a press) its own once
  // it moves up or down past the slop, more than across, the way it can still go: else what holds it is asked)
  .claims(fn(dx, dy) {
    let x = s.at(self.tree)
    // (across: along the row, what holds it asked what goes up or down)
    let (along, other) = if across { (dx, dy) } else { (dy, dx) }
    // (a page's list's pulled past its end, where its platform's is)
    let can = (if along < 0.0 { x < s.most() } else { x > 0.0 }) ||
      (s.as_list && (self.tree.list_feel)().0 != Desktop)
    let takes = along.abs() > slop() && along.abs() >= other.abs() && can
    s.claimed = takes
    takes
  }, scrolls=true)
  // (held, its own terms: what it holds moved as far as the hand, as big as it is drawn)
  .on_drag(fn(d) {
    // (where the hand is along it, in its own terms and the window's, and how fast: across, along the row)
    let (hy, hwy, hvy) = if across { (d.x, d.wx, d.vx) } else { (d.y, d.wy, d.vy) }
    match d.kind {
      Down => {
        // (what shows past an end of a page's list caught where it shows: held by the finger from there)
        if s.as_list {
          s.past_held(d.at)
        }
        s.stopped(d.at) |> ignore
        s.hand_y = hy
        s.hand_wy = hwy
        s.hand_t = d.at
        s.hand_v = 0.0
      }
      Moved => {
        // (taken over: the first move from where it went down past the slop alone, in the window's points, as big
        // in its own terms as it is drawn)
        let mut dy = hy - s.hand_y
        let dw = hwy - s.hand_wy
        if s.claimed && dw != 0.0 {
          s.claimed = false
          let past = if dw > 0.0 { dmax(dw - slop(), 0.0) } else { dmin(dw + slop(), 0.0) }
          dy = dy * past / dw
        }
        if s.as_list {
          s.dragged(self, d.at, -dy)
        } else {
          s.moved(d.at, -dy) |> ignore
        }
        s.hand_y = hy
        s.hand_wy = hwy
        s.hand_t = d.at
      }
      // (let go: flung at the finger's speed as of then, by its own events (Drag's `vy`: a pause before it let go, none),
      // no faster than a fling goes in the window's points, then in its own terms)
      Up => {
        let (_, _, sc) = self.tree.placed(self.at)
        s.hand_v = dclamp(-hvy, -scroll_most_v, scroll_most_v) / (if sc > 0.0 { sc } else { 1.0 })
        if s.as_list {
          s.let_go(self, d.at)
        } else {
          s.flung(self, d.at)
        }
      }
      // (called off: a page's list's let go of still)
      Off =>
        if s.as_list {
          s.hand_v = 0.0
          s.let_go(self, d.at)
        } else {
          s.stopped(d.at) |> ignore
        }
    }
  })
  // (a part of what it holds brought into sight: its top or its foot to its own, as little as that takes)
  .shows(fn(top, foot) {
    let t = self.logic_at()
    // (across: its start and its end, as wide as it is)
    let vh = if across { self.tree.nodes[self.at].flex.width } else { self.tree.nodes[self.at].flex.height }
    let x = s.stopped(t)
    if top < 0.0 {
      s.sent(t, x + top)
    } else if foot > vh {
      s.sent(t, x + dmin(top, foot - vh))
    }
    s.at(self.tree) - x
  }, across~)
}

///|
/// Whether node `id` scrolls what it holds up and down or across (View::scrolls) and it can go that way, as last laid
/// out (Scroll::goes: what it holds taller than it, or wider where it scrolls across, by more than half a point, as an old box kept to a height is, ui's scroll_still):
/// what lies in it moves under its top and foot as it scrolls, never in its container's corners for good (ui's corner
/// rule: a row of a list's as it scrolls).
pub fn Tree::scrolls_now(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  // (what it holds as tall as it is laid out, less its own: how far it can go, as its Scroll's room says it)
  let n = self.nodes[id.at]
  n.scroll_held >= 0 &&
  n.scroll_held < self.nodes.length() &&
  self.nodes[n.scroll_held].live &&
  // (the way it scrolls alone: up and down, or across, Scroll::across)
  (if n.scroll_across {
    self.nodes[n.scroll_held].flex.width - n.flex.width
  } else {
    self.nodes[n.scroll_held].flex.height - n.flex.height
  }) >
  0.5
}

///|
/// Whether node `id` scrolls what it holds up and down (View::scrolls) and that is shorter than it, as last laid out:
/// what it holds ends above its foot, where its words end, so where its last part is from its container's foot corners
/// is what it holds, not a place it stands (ui's corner rule: compared with them only as it scrolls to its end; the
/// user, 2026-11-04: 滚到底才查底角).
pub fn Tree::scroll_short(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let n = self.nodes[id.at]
  n.scroll_held >= 0 &&
  n.scroll_held < self.nodes.length() &&
  self.nodes[n.scroll_held].live &&
  !n.scroll_across &&
  self.nodes[n.scroll_held].flex.height < n.flex.height - 0.5
}

///|
/// Whether node `id` is in what one that scrolls moves (View::scrolls: its held), however far that can go now: where it
/// is moves with that, as what an old view's box that scrolls (its capped, a sideways one) holds does. Not what stands
/// beside that in the one that scrolls (its bar, what is put over it), which stays.
pub fn Tree::in_scroller(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let mut child = id.at
  let mut i = self.nodes[id.at].parent
  while i >= 0 {
    if self.nodes[i].scroll_held == child {
      return true
    }
    child = i
    i = self.nodes[i].parent
  }
  false
}
