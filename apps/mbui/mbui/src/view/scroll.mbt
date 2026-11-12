// A column that scrolls up and down in a node (View::scrolls), as an old view's box kept to a height does (ui's
// Ctx::capped): what it holds laid out as tall as it is, drawn off by how far it is scrolled and cut to the node, found
// by a finger or the pointer within the node alone; the wheel over any of it moves it while it can go that way (at its
// end the wheel goes on to what holds it: View::on_wheel_moves), a finger or the pointer held on any of it and moved up
// or down past the slop drags it (View::claims: what it went down on called off; across, or at its end, what holds it
// is asked) and, let go, flings it on, slowing; the focus come to what it holds brings that into sight once laid out
// (View::shows). As tall as what it holds
// where there is the room, it gives way (to nothing) where what holds it is short of room (a dialog no taller than the
// window), how far it can go worked out as it is laid out, in that layout (what it holds measured there: its fill, a
// page's list's blocks made and measured first). Where it is, a function of the time while
// flung, is the column's own (Scroll), let go with the node. One made as a page's list (Scroll::list) moves as an old
// view's list does on the platform it is on instead (scroll_list.mbt). One made to scroll across (Scroll::across) is a
// row that scrolls sideways the same way (an old view's Ctx::sideways): along its width, the wheel and a hold across,
// its bar along its foot, what holds it asked what goes up or down.

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
/// as `bound` (how far it could go, or its top, as last laid out); at `end_t` there, after which `parked` (at `x0`,
/// still said: what holds it laid out further, on again from there then).
priv struct Edge {
  x0 : Double
  v : Double
  t0 : Double
  bound : Double
  end_t : Double
  parked : Bool
}

///|
/// How far a column that scrolls (View::scrolls) is scrolled: where it is at rest (or where a fling set out from), the
/// fling under way, how far it can go as last laid out, and the hand on it.
pub struct Scroll {
  priv x : @signals.Signal[Double]
  priv fling : @signals.Signal[Fling?]
  /// how far it can go, as laid out (worked out as it is laid out, in that layout: View::scrolls; none before it first
  /// is)
  priv mut room : () -> Double?
  /// how big it shows what it holds (its own content box, as it is laid out: none before it first is), and what is done
  /// as it is laid out before what it holds is measured, given the room it shows it in (a page's list: its blocks made
  /// and measured for it, View::scrolls_window)
  priv seen : @signals.Signal[(Double, Double)?]
  priv mut fill : (Double?, (Double?, Double)?, Bool) -> Unit
  /// how tall what it holds comes to, where what fills it knows it as it fills it (a page's list: its blocks as they
  /// are counted, its foot's room), not measured again
  priv mut whole : (() -> Double)?
  /// what ends the fling's settling at its end (View::at_moment's), as it is called off
  priv mut settle_off : () -> Unit
  /// where the hand held on it was last (the window's, down), and how fast it went (points a ms, down the column)
  priv mut hand_y : Double
  priv mut hand_wy : Double
  priv mut hand_v : Double
  /// taken over from what it went down on (View::claims): its first move from where it went down counted past the slop
  priv mut claimed : Bool
  /// what is told as it scrolls (its bar), at the moment
  priv mut on_scrolled : (Double) -> Unit
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
  /// how far it was put to tuck a node over its top as that was first laid out (Scroll::tucks: none, never), whether it
  /// is to be put there still (the hand not on it since), and the room a page's list's foot keeps for it
  priv tuck_at : @signals.Signal[Double?]
  priv mut tuck_owed : Bool
  priv tuck_room : @signals.Signal[Double]
  /// the node it scrolls in that keeps that room, while it does
  priv mut tuck_in : View?
  /// how far it was put in all for what came in or out over what shows, or was measured anew there
  /// (Scroll::grew_above): no move of the column's, what shows held where it was
  priv mut corrected : Double
  /// its foot gone to at once at a moment (End: scroll_keys.mbt), where what fills it knows it better than how far it
  /// was last laid out to go (a page's list: ListPlace::to_end); false where it does not
  priv mut to_foot : (Double) -> Bool
  /// a page's list at the foot it follows, left where it is as what shows grows (Scroll::holds_here), till it is
  /// followed again (View::scrolls_window's fill says when); and what its list does as that is said (what it holds
  /// then kept: blocks come or gone since are told from it)
  priv mut held : Bool
  priv mut held_said : () -> Unit
  /// what it does as a node in it is pressed (what was pressed held where it is, press_stays.mbt: a page's list's
  /// View::scrolls_window's, a plain column's View::scrolls'): given the node before the press is done, what to do once
  /// it is
  priv mut pressed_said : (View) -> () -> Unit
  /// whether it is at its foot, followed, told only as that changes (Scroll::at_foot_now): a page's list's by its own
  /// blocks and anchor (View::scrolls_window), else by how far it goes as last laid out (View::scrolls)
  priv mut at_foot_said : (() -> Bool)?
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
    seen: @signals.signal(None, same=fn(a, b) { a == b }),
    fill: fn(_, _, _) {  },
    whole: None,
    settle_off: fn() {  },
    hand_y: 0.0,
    hand_wy: 0.0,
    hand_v: 0.0,
    claimed: false,
    on_scrolled: fn(_) {  },
    to_foot: fn(_) { false },
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
    tuck_at: @signals.signal(None, same=fn(a, b) { a == b }),
    tuck_owed: false,
    tuck_room: @signals.signal(0.0, same=fn(a, b) { a == b }),
    tuck_in: None,
    corrected: 0.0,
    held: false,
    held_said: fn() {  },
    pressed_said: fn(_) { fn() {  } },
    at_foot_said: None,
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
/// When what it is on by itself now ends (a fling, what it meets its end with going back; what shows past an end going
/// back), followed: none at rest or held.
fn Scroll::rest_now(self : Scroll) -> Double? {
  // (the hand past its edge: at its end as said now; at rest there, parked)
  match self.edge.get() {
    Some(e) => return if e.parked { None } else { Some(e.end_t) }
    None => ()
  }
  match self.fling.get() {
    Some(f) =>
      match f.way {
        Some({ hit: Some({ back: Some(p), .. }), .. }) => Some(p.rest)
        _ => Some(f.end_t)
      }
    // (a page's list's notches easing in and what shows past an end going back, each its own: at rest as the later is)
    None => {
      let eased = self.notch.get().map(fn(n) { n.t0 + n.end })
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
    Some(e) => return dclamp(e.at(t), 0.0, most)
    None => ()
  }
  match self.fling.get() {
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
        Some(n) =>
          dclamp(n.x0 + (if t - n.t0 >= n.end { n.total } else { ease_come(n.total, n.v0, t - n.t0) }), 0.0, most)
        None => dclamp(self.x.get(), 0.0, most)
      }
  }
}

///|
/// How far it is scrolled at the logic's moment of `tree` (the one it is in: what an event, a step or a test reads).
pub fn Scroll::at(self : Scroll, tree : Tree) -> Double {
  @signals.untracked(fn() { self.where_at(tree.logic_said()) })
}

///|
/// How far it is scrolled as what is drawn is drawn, followed: where it is on by itself (a fling, a page's list's wheel's
/// notches easing in), read again as the time goes till it is at rest; else as it stands. What works out what of what
/// it holds to make as it scrolls (a page's list built by the rows in sight) reads it so, never its own copy of how it
/// moves. Not what shows past an end (iOS's rubber band, Android's stretch: Scroll::past).
pub fn Scroll::drawn(self : Scroll, tree : Tree) -> Double {
  self.where_at(if self.goes_on() { tree.drawn_said() } else { 0.0 })
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
  guard self.as_list else { @halt.saying("Scroll::grew_above: a page's list's (Scroll::list) alone") }
  if d == 0.0 {
    return
  }
  @signals.untracked(fn() {
    let t = match self.host {
      Some(v) => v.tree.logic_said()
      None => 0.0
    }
    self.x.set(self.x.get() + d)
    self.corrected = self.corrected + d
    // (the hand past its edge: where it has it now as much further, its foot too where it goes down; on from there by
    // its own way, its end then: what is laid out after worked out again as that is)
    match (self.edge.get(), self.host) {
      (Some(e), Some(v)) => {
        let x0 = e.at(t) + d
        let bound = if e.v > 0.0 { e.bound + d } else { 0.0 }
        // (at its foot it is at its foot still; at its top, on to it again)
        self.edge_planned(v, e, x0, t, bound)
      }
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
    self.offset_said()
    // (at rest when it now is: said again on its timeline)
    match self.host {
      // (the hand past its edge: said on by its own way, above)
      Some(_) if self.edge.get() is Some(_) => ()
      Some(v) => {
        self.list_settles(v, t)
        // (a fling down toward its foot: its foot where all of it is laid out as this change leaves it, worked out
        // then, however far it can go came out, the same or not)
        if self.fling.get() is Some({ v0, way: Some(_), .. }) && v0 > 0.0 {
          v.tree.once_laid_out(fn() {
            // (still scrolling in it, as it was: not let go meanwhile, nor said to scroll in another)
            match self.host {
              Some(h) if physical_equal(h.tree, v.tree) && h.live() is Some(_) && h.at == v.at && h.gen == v.gen =>
                self.foot_moved(v, v.tree.logic_said(), self.most(), laid=true)
              _ => ()
            }
          })
        }
      }
      None => ()
    }
  })
}

///|
/// How far it can go, as it was last laid out (0 before it first is).
pub fn Scroll::most(self : Scroll) -> Double {
  @signals.untracked(fn() { self.most_now() })
}

///|
/// How far it can go, as it was last laid out, followed (0 before it first is): what keeps room at what it holds' foot
/// by it (a list's room for what is tucked over its rows) reads it so.
pub fn Scroll::reach(self : Scroll) -> Double {
  self.most_now()
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
  // (brought on past its edge: as far as it came)
  if self.edge.untracked() is Some(e) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.edge.set(None)
    self.x.set(x)
    if !e.parked {
      self.scrolled_at(t)
    }
  }
  // (a page's list's notches easing in: as far as they came)
  if self.notch.untracked() is Some(_) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.notch.set(None)
  }
  if self.fling.untracked() is Some(f) {
    (self.settle_off)()
    self.settle_off = fn() {  }
    self.fling.set(None)
    self.x.set(x)
    // (stopped on its way: it scrolled till now, no further: its bar's showing from here)
    if t < f.end_t {
      self.scrolled_at(t)
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
    Some(v) if v.alive() => self.stopped(v.tree.logic_said()) |> ignore
    _ => ()
  }
  self.x.set(dmax(to, 0.0))
  self.offset_said()
}

///|
/// Node `v`, made in what it scrolls, tucked out of sight over its top (a page's list's search, as iOS's are): put, as
/// `v` is first laid out in it, so far down that `v`'s foot is `cover()` under its top (what lies over its top: a bar),
/// once for it (made again with another node in its place, it is where it was put then, as far as the hand left it);
/// put there again while what it holds comes short of that as it is laid out, till the hand is on it; its foot keeping
/// the room it lacks to go there however few what it holds is (a page's list's: View::scrolls_window) while `kept()`
/// says so, whether `v` shows or not. Where `v` is laid out is its own reading, not its caller's. What of `v` lies under
/// what covers the top (all of it, tucked) is out of sight and takes no finger nor pointer there, nor is reached from
/// round it (Tree::input_bounds), wherever it is scrolled to.
pub fn Scroll::tucks(self : Scroll, v : View, cover : () -> Double, kept? : () -> Bool = fn() { true }) -> Unit {
  guard self.host is Some(host) && v.alive() else { return }
  // (what of it lies under what covers its top is out of sight: found by no finger nor pointer, Tree::tucked_bound)
  v.tree.nodes[v.at].tucked_under = Some((host.at, cover))
  v.tree.hits = v.tree.hits + 1
  v.reacts(fn() { v.laid_size_told() is Some(_) }, fn(laid) {
    guard laid && self.tuck_at.untracked() is None else { return }
    // (not scrolled yet: where it is in what it holds is where it is laid out in it)
    let (_, vy, _, vh) = v.placed_window_now()
    let (_, hy, _, _) = host.placed_window_now()
    let at = vy - hy + vh - @signals.untracked(cover)
    self.tuck_owed = true
    self.tuck_at.set(Some(at))
    self.put(at)
  })
  // (said once for the node it scrolls in, however many times what is tucked is made in it)
  match self.tuck_in {
    Some(h) if h.at == host.at && h.gen == host.gen => return
    _ => ()
  }
  self.tuck_in = Some(host)
  // (as far as it goes with less than it is tall: its foot keeps the room it lacks to go there; put there again where it
  // came short of it as it was laid out, till the hand is on it)
  host.reacts(fn() { (self.tuck_at.get(), self.reach(), kept()) }, fn(now) {
    let had = self.tuck_room.untracked()
    let want = match now {
      (Some(at), most, true) => dmax(0.0, at - (most - had))
      _ => 0.0
    }
    if (want - had).abs() >= 0.5 {
      self.tuck_room.set(want)
      return
    }
    match now.0 {
      Some(at) if self.tuck_owed && self.at(host.tree) < at - 0.5 && now.1 >= at - 0.5 => self.put(at)
      _ => ()
    }
  })
  // (the hand on it, or it gliding: put there no more)
  host.reacts(fn() { host.pointed_in() || self.glides_till() is Some(_) }, fn(on) {
    if on {
      self.tuck_owed = false
    }
  })
  host.owns(fn() {
    self.tuck_owed = false
    self.tuck_room.set(0.0)
    self.tuck_in = None
  })
  |> ignore
}

///|
/// Put at its foot however far that comes to be (where it is read, as far as it can go then; there still as that is
/// told otherwise, till it is moved: the hand, the wheel, a fling set out from there where it is then, Scroll::stopped),
/// what it was on by itself stopped (Scroll::put's).
fn Scroll::to_foot(self : Scroll) -> Unit {
  self.put(@double.infinity)
}

///|
/// What shows left where it is as what it holds grows, though it is a page's list at the foot it follows
/// (View::scrolls_window's `follows`): what the reader opens in a block there opens down from where the block is
/// (following its foot, the block went up as far as it opened, away from the hand that pressed it). Said at the press,
/// before what it opens. Followed again once the hand moves it, once it is back at its foot having left it, or as
/// blocks come or go while it has not left its foot (nothing opened after all). One that follows no foot, or is off
/// it: nothing.
pub fn Scroll::holds_here(self : Scroll) -> Unit {
  if self.at_foot() {
    self.held = true
    (self.held_said)()
  }
}

///|
/// Whether it is at its foot however far that comes to be (Scroll::to_foot), not moved off it since.
fn Scroll::at_foot(self : Scroll) -> Bool {
  self.x.untracked() == @double.infinity
}

///|
/// Whether it is at its foot, followed: told only as that comes to be so or stops (what follows the newest, a button
/// back to it, reads it), never as it scrolls on either side of that. A page's list's (View::scrolls_window) by its own
/// blocks as they are counted and its anchor, so in the same layout as a block measured anew or grown at its foot,
/// never a frame after it: at its foot where it follows it there, however far that comes to be, else where the top of
/// what shows is within half a point of where it would be at its foot. Else by how far it can go as last laid out.
pub fn Scroll::at_foot_now(self : Scroll) -> Bool {
  match self.at_foot_said {
    Some(f) => f()
    // (scrolling in nothing yet: where it is put)
    None => self.x.get() == @double.infinity
  }
}

///|
/// Scrolled by the hand at `t` (the wheel, a finger, a fling, a part brought into sight): what is told so told (its
/// bar), and what hosts the tree that it moved (Scroll::offset_said).
fn Scroll::scrolled_at(self : Scroll, t : Double) -> Unit {
  (self.on_scrolled)(t)
  self.offset_said()
}

///|
/// What it holds moved (or what it is on by itself set going or stopped), told the tree it scrolls in (Tree::offset_told):
/// what it moves by its offset alone (a page's list, its bar's thumb: Node's scroll_off) drawn moved by what hosts it,
/// nothing placed for it. Not scrolling in a node, nothing.
fn Scroll::offset_said(self : Scroll) -> Unit {
  match self.host {
    Some(v) if v.alive() => v.tree.offset_told(v.at)
    _ => ()
  }
}

///|
/// How far a page's list's held (node `at` of `tree`, up and down: Scroll::list) is drawn off where it is placed at `t`,
/// as far as it is scrolled and what shows past an end moves it (iOS's rubber band): by whole pixels, on its host's
/// grid where it sets the list's rows on it (the first row's top on a pixel wherever it is scrolled to, as it is placed:
/// Tree::rows_placed), else on the pixels the tree is drawn at (Tree::set_pixel_grid): what it holds drawn once, moved
/// so, its words stay on the pixels they were drawn on (an old view's list drew its boxes off by part of a pixel, its
/// words each set on a pixel as they came). Read as it is drawn, found or read out at a moment (Node's scroll_off),
/// nothing followed.
fn Scroll::held_dy(self : Scroll, tree : Tree, at : Int, t : Double) -> Double {
  self.drawn_off(tree, at, self.where_at(t), self.past_moved(t))
}

///|
/// Moved by `d` (down the column) at `t`, as far as it can go: whether it moved.
fn Scroll::moved(self : Scroll, t : Double, d : Double) -> Bool {
  let was = self.stopped(t)
  let to = dclamp(was + d, 0.0, self.most())
  self.x.set(to)
  if to != was {
    self.scrolled_at(t)
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
    self.scrolled_at(t)
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
  self.scrolled_at(t)
  // (what hosts the tree told it glides, which column it is and how to ask it when it ends now: Tree::on_glides)
  (v.tree.glides)(self.serial, fn() { self.glides_till() })
  // (at rest at its end, said on the timeline: then nothing reads the time for it)
  v.tree.hand_at_end(end_t)
  self.settle_off = v.at_moment(end_t, fn() {
    self.settle_off = fn() {  }
    // (scrolled till its end: told so while it still counts as under way, its bar's showing from there)
    self.scrolled_at(end_t)
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
    let t = v.tree.logic_said()
    let x0 = self.stopped(t)
    if speed == 0.0 {
      return
    }
    // (from where it is, as far as it can go that way now: worked out, its end said, by edge_due)
    let bound = if speed > 0.0 { self.most() } else { 0.0 }
    self.edge.set(Some({ x0, v: speed, t0: t, bound, end_t: t, parked: false }))
    self.edge_due(v, t)
  })
}

///|
/// Where the hand past its edge has it at `t`, as far as its bound (as it was laid out as it was said).
fn Edge::at(self : Edge, t : Double) -> Double {
  if self.parked {
    return self.x0
  }
  let x = self.x0 + self.v * (dmax(t, self.t0) - self.t0)
  if self.v > 0.0 {
    dmin(x, self.bound)
  } else {
    dmax(x, self.bound)
  }
}

///|
/// The hand past its edge said on from where it has it at `t`, as far as it can go as laid out now: its end then, said
/// on the timeline (parked there); there already, parked now.
fn Scroll::edge_due(self : Scroll, v : View, t : Double) -> Unit {
  guard self.edge.untracked() is Some(e) else { return }
  let most = self.most()
  let x0 = dclamp(e.at(t), 0.0, most)
  let bound = if e.v > 0.0 { most } else { 0.0 }
  self.edge_planned(v, e, x0, t, bound)
}

///|
/// The hand past its edge (`e`, as it was) said on from `x0` at `t` as far as `bound`: its end then said on the
/// timeline, told what hosts the tree (Tree::on_glides), parked there; there already, parked now.
fn Scroll::edge_planned(self : Scroll, v : View, e : Edge, x0 : Double, t : Double, bound : Double) -> Unit {
  (self.settle_off)()
  self.settle_off = fn() {  }
  let end_t = t + dmax(0.0, (bound - x0) / e.v).ceil()
  if end_t <= t {
    // (at its end: nothing moving, nothing reading the time; told so as it is there no more since now)
    self.edge.set(Some({ ..e, x0: bound, t0: t, bound, end_t: t, parked: true }))
    if !e.parked {
      self.scrolled_at(t)
    }
    return
  }
  self.edge.set(Some({ x0, v: e.v, t0: t, bound, end_t, parked: false }))
  self.scrolled_at(t)
  // (what hosts the tree told it goes on by itself, till when as it is asked: Tree::on_glides)
  (v.tree.glides)(self.serial, fn() { self.glides_till() })
  v.tree.hand_at_end(end_t)
  self.settle_off = v.at_moment(end_t, fn() {
    self.settle_off = fn() {  }
    self.scrolled_at(end_t)
    match self.edge.untracked() {
      Some(g) => self.edge.set(Some({ ..g, x0: g.bound, t0: end_t, end_t, parked: true }))
      None => ()
    }
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
/// holds' last line), none while it cannot. `bar_clear`: down a column, how much of its top and its foot its bar keeps
/// clear of, as it is now (what lies over them: a bar the list runs under), as an old view's list's bar does.
pub fn View::scrolls(
  self : View,
  s : Scroll,
  build : (View) -> Unit,
  slop? : Double,
  bar? : ScrollBar,
  bar_in? : Double = 0.0,
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
  // (at its foot, told only as that changes: a page's list says it by its blocks (View::scrolls_window); else by how
  // far it can go as last laid out, where it is drawn)
  if s.at_foot_said is None && !s.across {
    let at_foot = @signals.computed(fn(_) {
      let most = s.most_now()
      s.x.get() == @double.infinity || s.drawn(self.tree) >= most - 0.5
    }, same=fn(a, b) { a == b })
    s.at_foot_said = Some(fn() { at_foot.get() })
  }
  // (its keys, down a column: Home, End, the pages, the lines, as an old view's list's: scroll_keys.mbt)
  if !s.across {
    self.scroll_keys(s)
  }
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
  self.tree.layout_marked_at(self.at)
  // (how far it can go and how big it shows what it holds, worked out as it is laid out, in that same layout: what it
  // holds measured there (as tall as it comes to; across, as wide), the room it shows it in its own; what reads them
  // said again there, in it; never told back once all of it is laid out)
  let reach : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  s.room = fn() { reach.get() }
  let tree = self.tree
  let me = self.at
  // (what it holds measured as it is laid out, how far it can go and how big it shows it told: whether either came out
  // otherwise)
  // (how big what it holds came to as it was last measured, and, where what holds it measured it by what it holds, how
  // big that made it and the most it could be: made otherwise as it is laid out (what shows measured anew), what holds
  // it laid out again by it)
  let last_whole = Ref(0.0)
  let sized_by : Ref[(Double, Double)?] = Ref(None)
  // (how big what it holds comes to, and how big it shows it, given `w` by `h` so)
  let sizes = fn(held : View, w : Double, wm : @flex.MeasureMode, h : Double, hm : @flex.MeasureMode) -> (Double, Double) {
    let hs = tree.nodes[held.at].flex.style
    let pt = fn(k : Int, x : Double) { if k == @flex.LEN_PT { x } else { 0.0 } }
    if across {
      let along = pt(hs.margin_left_kind(), hs.margin_left_value()) +
        pt(hs.margin_right_kind(), hs.margin_right_value())
      let size = @flex.measured_width(tree.nodes[held.at].flex, 0.0 / 0.0) + along
      (size, if wm is Undefined { size } else if wm is AtMost { dmin(size, w) } else { w })
    } else {
      let side = pt(hs.margin_left_kind(), hs.margin_left_value()) +
        pt(hs.margin_right_kind(), hs.margin_right_value())
      let along = pt(hs.margin_top_kind(), hs.margin_top_value()) +
        pt(hs.margin_bottom_kind(), hs.margin_bottom_value())
      let held_h = match s.whole {
        Some(f) => f()
        None => @flex.measured_height(tree.nodes[held.at].flex, dmax(0.0, w - side))
      }
      let size = held_h + along
      (size, if hm is Undefined { size } else if hm is AtMost { dmin(size, h) } else { h })
    }
  }
  // (a press in what it holds, down a column that is no page's list (a page's list holds its own: View::scrolls_window),
  // press_stays.mbt: what lies over what was pressed (each node before it or before what holds it, down a column), how
  // tall that was then and where it was scrolled to; none once the hand moves it or all the press set off has ended.
  // Where it was put for that last, and the room kept under what it holds for it: as much as that asks while it is
  // held, then no more than still shows of it)
  let press_pin : Ref[(View, Array[View], Double, Double)?] = Ref(None)
  let press_put = Ref(0.0)
  let press_ends = Ref(false)
  let press_unpin : Ref[() -> Unit] = Ref(fn() {  })
  let press_room : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  let over_h = fn(over : Array[View]) {
    let mut h = 0.0
    for o in over {
      if o.alive() && tree.nodes[o.at].flex.style.display != @flex.Display::DisplayNone {
        h = h + @flex.measured_height(tree.nodes[o.at].flex, tree.nodes[o.at].flex.width)
      }
    }
    h
  }
  // (held by what was pressed, as it is laid out showing `shown` of `whole`: put where that is, the room under
  // it as that asks; held no more, that room no more than still shows)
  let press_held = fn(whole : Double, shown : Double) -> Bool {
    let room_was = press_room.untracked()
    let x = s.x.untracked()
    let base = whole - press_room.untracked()
    match press_pin.val {
      // (moved since by the hand, or put elsewhere, or what was pressed or what was over it let go: held no more)
      Some((v, over, _, _)) if x != press_put.val || !v.alive() || over.iter().any(fn(o) { !o.alive() }) => {
        press_pin.val = None
        (press_unpin.val)()
      }
      _ => ()
    }
    match press_pin.val {
      Some((_, over, was, x0)) => {
        let want = dmax(0.0, x0 + over_h(over) - was)
        press_room.set(dmax(0.0, want - (base - shown)))
        if want != x {
          s.x.set(want)
          s.offset_said()
        }
        press_put.val = want
        if press_ends.val {
          press_ends.val = false
          press_pin.val = None
        }
      }
      None => {
        let left = dmax(0.0, x + shown - base)
        if left < press_room.untracked() {
          press_room.set(left)
        }
      }
    }
    press_room.untracked() != room_was
  }
  if !across && s.whole is None {
    s.pressed_said = fn(v) {
      guard inner.val is Some(held) && held.alive() else { return fn() {  } }
      let over : Array[View] = []
      let mut i = v.at
      while i >= 0 && i != held.at {
        let up = tree.nodes[i].parent
        if up >= 0 && tree.nodes[up].flex.style.direction is Column {
          for c in tree.nodes[up].kids {
            if c == i {
              break
            }
            over.push(tree.handle(c))
          }
        }
        i = up
      }
      guard i == held.at else { return fn() {  } }
      let was = over_h(over)
      let x0 = s.x.untracked()
      fn() {
        (press_unpin.val)()
        press_pin.val = Some((v, over, was, x0))
        press_put.val = x0
        press_ends.val = false
        press_unpin.val = self.at_moment(tree.cause_now() + @flex.move_most_ms, fn() {
          press_ends.val = true
          tree.layout_marked_at(me)
        })
      }
    }
  }
  let measure_reach = fn(held : View, w : Double, wm : @flex.MeasureMode, h : Double, hm : @flex.MeasureMode) -> Bool {
    let (whole, shown) = {
      let (whole, shown) = sizes(held, w, wm, h, hm)
      // (the room under it for what was pressed changed: measured again with it)
      if !across && s.whole is None && press_held(whole, shown) {
        tree.room_bindings_run()
        sizes(held, w, wm, h, hm)
      } else {
        (whole, shown)
      }
    }
    last_whole.val = whole
    let seen_now = Some(if across { (shown, h) } else { (w, shown) })
    let reach_now = Some(whole - shown)
    let changed = @signals.untracked(fn() { s.seen.get() != seen_now || reach.get() != reach_now })
    // (told as one: what follows where it is scrolled to reads how big it shows with how far it can go, never the one
    // told and the other as it was (a list brought to an entry 969 down read at its top, how far it could go none yet,
    // and asked for the page before))
    @signals.start_batch()
    s.seen.set(seen_now)
    reach.set(reach_now)
    @signals.end_batch()
    tree.room_bindings_run()
    changed
  }
  match self.live() {
    Some(n) => {
      n.flex.room = true
      n.flex.measure = Some(fn(w, wm, h, hm) {
        guard inner.val is Some(held) && held.alive() else { return (0.0, 0.0) }
        let performing = @flex.performing()
        let marked = tree.in_room(me, fn() {
          // (the room it is laid out in, or one it is given exactly as it is measured first: not one it is only measured
          // within, which what is made by it would be made again by, and back)
          let given = fn(m : @flex.MeasureMode, v : Double) { if performing || m is Exactly { Some(v) } else { None } }
          // (how tall it shows: exactly as given, or within the most it may be, or bound by nothing; none told where it
          // is only measured within a room)
          let tall_given = if hm is Exactly {
            Some((Some(h), h))
          } else if performing {
            Some((None, if hm is AtMost { h } else { @double.infinity }))
          } else {
            None
          }
          (s.fill)(given(wm, w), tall_given, performing)
          // (laid out; or a row that scrolls across measured within a width (what holds it measuring first how tall it
          // comes to, its bar's room under it counted by how far it can go there): how far it can go and how big it
          // shows what it holds told. Down a column only measured within a room, neither is told: how big what it holds
          // comes to is kept for what holds it to be laid out again by, below, no more. The room it is measured within
          // is not the one it shows in (one taking what is left under a head is measured within all of its column
          // first), and what is told is acted on: where it is scrolled to put no further than it could go in that
          // room, a page's list then at its foot there taken to follow it (an agent's history beside its chat,
          // 2026-11-10: every move of the hand up from its foot undone as a row came to show))
          let told = performing || (across && !(wm is Undefined))
          if told || !(hm is Undefined) {
            if told {
              // (what reads them may change what it holds (room kept at its foot for its bar, or for what is tucked
              // over its top): measured again till it comes out as it was, in this same layout)
              let mut rounds = 0
              while measure_reach(held, w, wm, h, hm) {
                // (what shows of it made again by that: made and measured in turn)
                (s.fill)(None, None, true)
                rounds = rounds + 1
                if rounds > 8 {
                  @halt.saying("View::scrolls: how far it can go changes what it holds and that how far it can go, on and on")
                }
              }
            } else {
              last_whole.val = sizes(held, w, wm, h, hm).0
            }
            let (m, most) = if across { (wm, w) } else { (hm, h) }
            if !performing && !(m is Exactly) {
              // (measured by what it holds, within the most it may be: as big as that made it)
              let most = if m is AtMost { most } else { @double.infinity }
              sized_by.val = Some((dmin(last_whole.val, most), most))
            } else if performing {
              // (laid out as big as what it held made it as it was measured, what it holds now another size within the
              // most it may be: what holds it laid out again by that once all of it is (outside its room, Tree::in_room))
              match sized_by.val {
                Some((was, most)) if (dmin(last_whole.val, most) - was).abs() > 0.5 => {
                  sized_by.val = None
                  tree.room_spill.push(me)
                }
                _ => ()
              }
            }
          }
        })
        (if marked { 1.0 } else { 0.0 }, 0.0)
      })
    }
    None => ()
  }
  self.box(fn(held) {
    inner.val = Some(held)
    self.tree.nodes[self.at].scroll_held = held.at
    self.tree.nodes[self.at].scroll_across = across
    // (a page's list's rows set on its host's pixels as an old view's list's are: Tree::set_rows_grid)
    // (a page's list's, down a column, drawn off by how far it is scrolled by its offset alone, read as it is drawn
    // (Node's scroll_off): nothing of it placed again as it scrolls, what it holds drawn as it was, moved by what hosts
    // the tree; on iOS moved past its end as far as its rubber band shows it)
    if s.as_list && !across {
      self.tree.rows_list(held.at)
      let lists = self.tree.lists_scrolled
      let at = self.at
      lists[at] = s
      self.owns(fn() { lists.remove(at) }) |> ignore
      let hn = self.tree.nodes[held.at]
      hn.scroll_by = self.at
      let tree = self.tree
      let at = held.at
      hn.scroll_off = Some(fn(t) { (0.0, s.held_dy(tree, at, if s.goes_on() { t } else { 0.0 })) })
      held.shrink(Is(0.0)) |> ignore
    } else {
      held
      .shrink(Is(0.0))
      .offset(By(fn() {
        let t = if s.goes_on() { held.tree.drawn_said() } else { 0.0 }
        if across {
          (-s.where_at(t), 0.0)
        } else {
          (0.0, -s.where_at(t) + s.past_moved(t))
        }
      }))
      |> ignore
    }
    // (down a column that is no page's list: room under what it holds for what was pressed in it, press_stays.mbt)
    if !across && s.whole is None {
      held.margin(By(fn() { (0.0, 0.0, 0.0, press_room.get()) })) |> ignore
    }
    // (across with a bar: room at its foot for it while it can go, as laid out (none while it cannot), its bar never
    // over what it holds' last line: Ctx::sideways's bar_room, from this layout's told reach, not a frame's before)
    // (under what it holds, its own room at its foot counted, as Ctx::sideways' `foot` is the more of its padding there
    // and the bar's room: what of the bar's room its padding there has not, under it)
    match bar {
      Some(b) if across =>
        held.margin(By(fn() {
          let room = if s.most_now() > 0.5 { b.size + 2.0 * b.inset } else { 0.0 }
          let st = self.tree.nodes[held.at].flex.style
          let pad = if st.padding_bottom_kind() == @flex.LEN_PT { st.padding_bottom_value() } else { 0.0 }
          (0.0, 0.0, 0.0, if room > pad { room - pad } else { 0.0 })
        }))
        |> ignore
      _ => ()
    }
    build(held)
  })
  |> ignore
  // (its bar, over what it holds, told as it scrolls)
  match bar {
    Some(b) => {
      // (a fling under way: till its end, as it is now, none once stopped)
      let state = BarState::new(fn() {
        match (s.fling.get(), s.edge.get()) {
          (Some(f), _) => f.end_t
          // (the hand past its edge: till its end as said now)
          (None, Some(e)) => e.end_t
          (None, None) => -1.0e9
        }
      })
      self.scroll_bar(s, b, state, bar_in~, bar_clear~)
      // (by the hand where it is on nothing by itself: Scroll::goes_on)
      s.on_scrolled = fn(t) {
        state.woke(b, self, t, scrolled=true, by_hand=!@signals.untracked(fn() { s.goes_on() }))
      }
    }
    None => ()
  }
  // (what it holds faded out towards its top and its foot where it goes on past them, as far as it does, at most
  // scroll_soft_most: an old view's capped's fade_to; by the time while flung, as it is drawn)
  // (a page's list's not, as an old view's list's is not; stretched instead where Android's is past an end, as it is
  // drawn: View::stretches)
  if s.as_list {
    self.stretches(By(fn() { s.stretch_drawn(if s.goes_on() { self.tree.drawn_said() } else { 0.0 }) })) |> ignore
  } else {
    self.fades(By(fn() {
      // (where it is as drawn, the time read while what it is on by itself has an end said: Scroll::rest_now)
      let x = s.where_at(if s.rest_now() is Some(_) { self.tree.drawn_said() } else { 0.0 })
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
  // (how far it can go told otherwise as it is laid out: where it is put within that, then and after, a fling under way
  // stopped where it is then; as an old view's box kept to a height is, sideways_after_layout)
  // (not laid out yet: how far it can go not known, nothing put)
  self.reacts(fn() { (s.room)().map(fn(r) { dmax(r, 0.0) }) }, fn(known) {
    guard known is Some(most) else { return }
    let t = self.tree.logic_said()
    // (the hand past its edge: on from where it has it now as far as it can go now, its end then; parked at its end, on
    // again where it can go further)
    match s.edge.untracked() {
      Some(e) if e.bound != (if e.v > 0.0 { most } else { 0.0 }) || e.x0 > most => s.edge_due(self, t)
      _ => ()
    }
    // (a page's list's fling down toward its foot meets it where it is as laid out now: worked out again)
    if s.as_list {
      s.foot_moved(self, t, most)
    }
    // (a box kept to a height's fling past how far it can go now: stopped there; a page's list's meets its foot instead,
    // worked out just now)
    if !s.as_list &&
      s.fling.untracked() is Some(_) &&
      @signals.untracked(fn() { s.where_at(t) }) >= most {
      s.stopped(t) |> ignore
    }
    // (no further than it can go, but at its foot however far that comes to be: Scroll::to_foot)
    if s.x.untracked() > most && !s.at_foot() {
      s.x.set(most)
    }
  })
  // (let go with it: no fling of it settles after)
  self.owns(fn() {
    // (the hand past its edge: at rest where it had it then, as far as it could go as it was said: how far it can go is
    // gone with what it was laid out in, as a fling's below)
    match s.edge.untracked() {
      Some(e) => {
        s.edge.set(None)
        s.x.set(e.at(self.tree.logic_said()))
      }
      None => ()
    }
    // (a fling under way at rest where it was then: nothing reads the time for it after)
    match s.fling.untracked() {
      Some(f) => {
        let t = self.tree.logic_said()
        let at = if t >= f.end_t {
          f.end_x
        } else {
          match f.way {
            Some(w) => w.at(f, t)
            None => scroll_fling_at(f.x0, f.v0, t - f.t0)
          }
        }
        s.fling.set(None)
        s.x.set(at)
      }
      None => ()
    }
    // (what shows past an end of a page's list gone with it, going back or not: nothing of it at rest after)
    s.past.set(None)
    // (a page's list's notches easing in at rest where they had come to)
    if s.notch.untracked() is Some(_) {
      let at = @signals.untracked(fn() { s.where_at(self.tree.logic_said()) })
      s.notch.set(None)
      s.x.set(at)
    }
    (s.settle_off)()
    s.settle_off = fn() {  }
    s.room = fn() { None }
    s.held = false
    s.held_said = fn() {  }
    s.pressed_said = fn(_) { fn() {  } }
    s.fill = fn(_, _, _) {  }
    s.whole = None
    s.seen.set(None)
    s.tall = fn() { 0.0 }
    s.host = None
    match self.tree.scrolls_at.get(self.at) {
      Some(o) if physical_equal(o, s) => self.tree.scrolls_at.remove(self.at)
      _ => ()
    }
    s.on_scrolled = fn(_) {  }
    s.to_foot = fn(_) { false }
    // (no glide of it told any more: Tree::on_glides)
    (self.tree.glides_gone)(s.serial)
  })
  |> ignore
  self
  // (the wheel up or down more than across, as an old view's box kept to a height takes it: sideways_wheel_moves)
  .on_wheel_moves(fn(w) {
    // (a pinch zooms, never scrolls: an old view's list takes none of it either)
    guard (w.mods & wheel_pinch) == 0 else { return false }
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
    // (up or down, not by a pointer that drags no list: Tree::pointer_drags_scroll)
    if !across && !(self.tree.drags_scroll)() {
      s.claimed = false
      return false
    }
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
    let (hy, hwy) = if across { (d.x, d.wx) } else { (d.y, d.wy) }
    match d.kind {
      Down => {
        // (what shows past an end of a page's list caught where it shows: held by the finger from there)
        if s.as_list {
          s.past_held(d.at)
        }
        s.stopped(d.at) |> ignore
        s.hand_y = hy
        s.hand_wy = hwy
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
      }
      // (let go: flung at the finger's speed as of then, by its own events (Drag's `vy`: a pause before it let go, none),
      // no faster than a fling goes in the window's points, then in its own terms)
      Up => {
        let (_, _, sc) = self.tree.placed(self.at)
        // (how fast it went, worked out as it is let go: none of its moves asked it)
        let hvy = if across { d.vx() } else { d.vy() }
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
    let t = self.tree.logic_said()
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
/// Whether node `id` holds a page's list's rows (View::scrolls as a list, Scroll::list): each of what it holds is a row,
/// whose place is the list's, moved as the list moves it (what grows above kept where it is drawn: Scroll::grew_above).
pub fn Tree::holds_rows(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].list_rows
}

///|
/// Whether node `id` scrolls what it holds up and down or across (View::scrolls) and it can go that way, as last laid
/// out (Scroll::goes: what it holds taller than it, or wider where it scrolls across, by more than half a point, as an old box kept to a height is, ui's scroll_still):
/// what lies in it moves under its top and foot as it scrolls, never in its container's corners for good (ui's corner
/// rule: a row of a list's as it scrolls).
pub fn Tree::scroll_corrected(self : Tree, id : NodeId) -> Double {
  guard self.alive_id(id) else { return 0.0 }
  match self.lists_scrolled.get(id.at) {
    Some(s) => s.corrected
    None => 0.0
  }
}

///|
/// Each page's list live now (View::scrolls over a Scroll::list, up and down: View::scrolls_window's), in the order its
/// node was made: how tall what it holds is laid out (its blocks each as tall as it was measured, one never made as tall
/// as it was counted: the whole its bar shows the share of), how tall it is, where it is scrolled to, and how far its
/// scroll was put in all for what came out another height over what shows (Tree::scroll_corrected). What a test reads of
/// how its list was reckoned against what it came to.
pub fn Tree::lists_reckoned(self : Tree) -> Array[(Double, Double, Double, Double)] {
  let ats = self.lists_scrolled.keys().to_array()
  ats.sort()
  ats.filter_map(fn(at) {
    let n = self.nodes[at]
    guard n.live && n.scroll_held >= 0 && n.scroll_held < self.nodes.length() && self.lists_scrolled.get(at) is Some(s) else {
      return None
    }
    Some((self.nodes[n.scroll_held].flex.height, n.flex.height, s.at(self), s.corrected))
  })
}

///|
/// Whether node `id` scrolls what it holds (View::scrolls), whether or not what it holds is taller than it now
/// (Tree::scrolls_now): the same all the while it is one, as what it holds comes to fit in it or grows past it.
pub fn Tree::is_scroller(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].scroll_held >= 0
}

///|
/// Whether node `id` is the one node a scroller holds and moves (View::scrolls: its `scroll_held`), however far that
/// scroller can go now: not what stands beside it in the scroller (its bar, a page's list's pinned foot), which stays.
pub fn Tree::is_scroll_held(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let p = self.nodes[id.at].parent
  p >= 0 && self.nodes[p].scroll_held == id.at
}

///|
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

