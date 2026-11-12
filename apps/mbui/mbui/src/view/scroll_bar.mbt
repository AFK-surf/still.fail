// The bar along a column that scrolls (View::scrolls' `bar`), as an old view's (ui's scroll_bar.mbt): a thumb along its
// right, round, in from it, at least so long, where its view is in what it holds; drawn only as what hosts the tree
// says (a mouse's: a finger has none), over what it holds, taking no room from it. It shows while the column scrolls
// (the wheel, a finger, a fling, a part brought into sight: not where it is first put) and a while after, then fades
// out, as it comes in; also while the pointer is along its edge or holds its thumb, and as long after. Its thumb, and a
// little round it, is pressed and dragged to scroll the column, nothing under it pressed. How far it shows is a
// function of the time, said once at each cause; at rest, nothing reads the time for it.

///|
/// How a column's bar looks and shows (ui's scroll_bar.mbt's, given by what hosts the tree): whether bars are drawn
/// now, its ink and its ink pointed at or held, how it comes in and goes (an ease of 0 … 1), how wide its thumb is,
/// how far in from the edge and its track's ends, how long at least, how far in from the edge the pointer brings it
/// out, how far round the thumb a press takes it, how long it shows after, how long it takes to come or go.
pub(all) struct ScrollBar {
  drawn : () -> Bool
  ink : () -> Int64
  ink_held : () -> Int64
  ease : (Double) -> Double
  size : Double
  inset : Double
  least : Double
  near : Double
  grab : Double
  hold_ms : Double
  fade_ms : Double
}

///|
/// The bar's state (its own: the column's Scroll): when it last came in and from how far it showed then, when what it
/// is for last scrolled, when a fling under way of it stops (as it is now: none once it is stopped or at rest), the
/// pointer along its edge and when it last left it, its thumb held and when it was last let go, and how it stands (0
/// gone, 1 coming in, 2 out, 3 going: what reads the time for it reads it while it comes or goes alone, told as each
/// begins, said on the timeline).
priv struct BarState {
  in_at : @signals.Signal[Double]
  in_from : @signals.Signal[Double]
  /// (not followed: read as what it says comes, its going said for when it was, BarState::woke)
  mut scrolled : Double
  near : @signals.Signal[Bool]
  near_left : @signals.Signal[Double]
  held : @signals.Signal[Bool]
  let_go : @signals.Signal[Double]
  phase : @signals.Signal[Int]
  mut rest_off : () -> Unit
  fling_end : () -> Double
}

///|
fn BarState::new(fling_end : () -> Double) -> BarState {
  {
    fling_end,
    in_at: @signals.signal(-1.0e9, same=fn(a, b) { a == b }),
    in_from: @signals.signal(0.0, same=fn(a, b) { a == b }),
    scrolled: -1.0e9,
    near: @signals.signal(false, same=fn(a, b) { a == b }),
    near_left: @signals.signal(-1.0e9, same=fn(a, b) { a == b }),
    held: @signals.signal(false, same=fn(a, b) { a == b }),
    let_go: @signals.signal(-1.0e9, same=fn(a, b) { a == b }),
    phase: @signals.signal(0, same=fn(a, b) { a == b }),
    rest_off: fn() {  },
  }
}

///|
/// When it starts to fade out: never while the pointer is along it or holds it (ui's Bar::hides_at).
fn BarState::hides_at(self : BarState, b : ScrollBar) -> Double {
  if self.near.get() || self.held.get() {
    1.0e300
  } else {
    dmax(dmax(self.scrolled, (self.fling_end)()), dmax(self.near_left.get(), self.let_go.get())) + b.hold_ms
  }
}

///|
/// How far it shows at `now` (0 … 1), coming in from when it came in, going from when it hides (ui's Bar::shown).
fn BarState::shown(self : BarState, b : ScrollBar, now : Double) -> Double {
  let hide = self.hides_at(b)
  let (in_at, in_from) = (self.in_at.get(), self.in_from.get())
  let come = fn(t : Double) { in_from + (1.0 - in_from) * (b.ease)(dclamp((t - in_at) / b.fade_ms, 0.0, 1.0)) }
  if now < hide {
    come(now)
  } else {
    come(hide) * (1.0 - (b.ease)(dclamp((now - hide) / b.fade_ms, 0.0, 1.0)))
  }
}

///|
/// Come out at `now` (what it is for scrolled then, `scrolled`, by the hand, `by_hand`; the pointer come to it, its
/// thumb held), from how far it shows then unless it is out already, as one change; at rest, said on the timeline, once
/// it has gone (or come, while it stays).
fn BarState::woke(
  self : BarState,
  b : ScrollBar,
  v : View,
  now : Double,
  scrolled? : Bool = false,
  by_hand? : Bool = false,
) -> Unit {
  @signals.untracked(fn() {
    // (coming in or out, and scrolled again by the hand before it goes: nothing told now, its coming in's end or its
    // going said for when it was and read anew as that comes, BarState::rested_at, so what scrolls it each moment the
    // hand moves it sets nothing that shows it; scrolled by what it is on by itself (a fling set going, come to its
    // end), its going said anew, once each)
    let phase = self.phase.get()
    let out = scrolled && by_hand && (phase == 1 || phase == 2) && now < self.hides_at(b)
    if now >= self.hides_at(b) {
      self.in_from.set(self.shown(b, now))
      self.in_at.set(now)
    }
    if scrolled {
      self.scrolled = now
    }
    if !out {
      self.rested_at(b, v)
    }
  })
}

///|
/// How it stands at the logic's moment of `v` (coming in, out, going, gone), told now, and its next change of that said
/// on the timeline (its coming in's end, its going's start, its going's end), what was said before of it called off:
/// as each comes, told then and the next said.
fn BarState::rested_at(self : BarState, b : ScrollBar, v : View) -> Unit {
  (self.rest_off)()
  self.rest_off = fn() {  }
  @signals.untracked(fn() {
    let now = v.tree.logic_said()
    let come_end = self.in_at.get() + b.fade_ms
    let hide = self.hides_at(b)
    let go_end = hide + b.fade_ms
    let (phase, next) = if now < come_end {
      (1, Some(come_end))
    } else if now < hide {
      (2, if hide < 1.0e299 { Some(hide) } else { None })
    } else if now < go_end {
      (3, Some(go_end))
    } else {
      (0, None)
    }
    // (gone from the first: never come in)
    let phase = if phase == 1 && self.in_at.get() < -1.0e8 { 0 } else { phase }
    self.phase.set(phase)
    match next {
      Some(at) => self.rest_off = v.at_moment(at, fn() { self.rested_at(b, v) })
      None => ()
    }
  })
}

///|
/// Where a thumb runs along an edge `len` long from `at`, what scrolls `size` long, what it holds `content`, scrolled
/// `off` into it, `start` and `end` of the edge kept clear (where it has less than twice `least` between them, none
/// kept), `inset` in from the track's ends, `least` long at least: where the thumb starts, how long it is (never less
/// than nothing), how far what scrolls goes for a point it moves. Pulled past an end, it stays at that end of its
/// track. The one way an old view's bar (ui's bar_track) and a node's (View::scroll_bar) work it out.
pub fn bar_track_of(
  at : Double,
  len : Double,
  size : Double,
  content : Double,
  off : Double,
  start : Double,
  end : Double,
  least : Double,
  inset : Double,
) -> (Double, Double, Double) {
  let (s, track) = if len - start - end < least * 2.0 { (0.0, len) } else { (start, len - start - end) }
  let long = dmax(0.0, dmin(track, dmax(least, track * size / dmax(content, 1.0))) - inset * 2.0)
  let room = track - inset * 2.0 - long
  let p = if content > size { dclamp(off / (content - size), 0.0, 1.0) } else { 0.0 }
  (at + s + inset + p * room, long, (content - size) / dmax(room, 1.0))
}

///|
/// The bar of column `v` (View::scrolls'), scrolled by `s`, as `b` says: a thumb along its right, its edge's strip
/// bringing it out where the pointer is along it. Across (Scroll::across): along its foot, `bar_in` in from either end,
/// the pointer along its foot bringing it out.
fn View::scroll_bar(
  self : View,
  s : Scroll,
  b : ScrollBar,
  bar : BarState,
  bar_in? : Double = 0.0,
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
) -> Unit {
  let across = s.across
  // (where its thumb runs and how long, how far the column goes for a point it moves: ui's bar_track over all of its
  // right, nothing over it kept clear; across, along its foot from `bar_in` to as far from its end)
  // (across, as an old view's foot_bar along the view it is for: `bar_in` in from either side, no more than leaves it
  // its least twice, what scrolls and what it holds as wide less that)
  // (what it runs along as its thumb was last placed and sized by it, as what those read changed: how far it is
  // scrolled at each moment it is drawn (its scroll_off) read along that, not worked out again each time)
  let along = Ref((0.0, 0.0, 0.0, 0.0, 0.0))
  let track_along = fn(x : Double) {
    let (vh, ends, content, start, end) = along.val
    bar_track_of(ends, vh - 2.0 * ends, vh - 2.0 * ends, content - 2.0 * ends, x, start, end, b.least, b.inset)
  }
  let track = fn(x : Double) {
    let (vh, ends) = match s.seen.get() {
      Some((w, h)) => if across { (w, dclamp(bar_in, 0.0, dmax(0.0, w / 2.0 - b.least))) } else { (h, 0.0) }
      None => (0.0, 0.0)
    }
    let content = vh + s.most_now()
    // (down a column, what lies over its top and its foot kept clear: `bar_clear`, as ui's bar_track's start and end)
    let (start, end) = if across { (0.0, 0.0) } else { bar_clear() }
    along.val = (vh, ends, content, start, end)
    track_along(x)
  }
  // (whether it has a bar at all: what it holds more than a point past what shows, as ui's bar_drawn has it; drawn,
  // come out along its edge and pressed by that alone)
  let has_bar = fn() { s.most_now() > 1.0 }
  // (how far it shows as it is drawn: by the time while it is not at rest)
  let level = fn() {
    if !(b.drawn)() || !has_bar() {
      return 0.0
    }
    // (coming in or going: by the time as it is drawn; out or gone: as it stands, no time read)
    match bar.phase.get() {
      1 | 3 => bar.shown(b, self.tree.drawn_said())
      // (out: as it stands, unless what is drawn is drawn past where it starts to go, the logic not come to it yet:
      // from there by the time as drawn)
      2 => {
        let hide = bar.hides_at(b)
        if hide < 1.0e299 && self.drawn_past(hide) {
          bar.shown(b, self.tree.drawn_said())
        } else {
          // (out all of it till it starts to go: as at its coming in's end, the time not read)
          bar.shown(b, bar.in_at.untracked() + b.fade_ms)
        }
      }
      _ => 0.0
    }
  }
  self.box(fn(over) {
    // (over what it holds, none of the column's own fading or stretching what it holds: its own showing alone, on its
    // own track; what holds the column drawing it as it draws the column)
    over.over(Is(true)).drawn_clear_of(self) |> ignore
    // (the pointer along its right brings it out: the innermost column at the pointer's, View::bar_near)
    over.reacts(fn() { (b.drawn)() && self.bar_near(if has_bar() { b.near } else { 0.0 }, across~) }, fn(on) {
      let t = self.tree.logic_said()
      // (come out first, then along it: as ui's bar_near does, its coming in from how far it showed then)
      if on {
        bar.woke(b, self, t)
        bar.near.set(true)
        bar.rested_at(b, self)
      } else if bar.near.untracked() {
        bar.near.set(false)
        bar.near_left.set(t)
        bar.rested_at(b, self)
      }
    })
    // (its thumb, and as far round it as a press takes it: held, it moves the column as far as it goes for a point)
    over.box(fn(thumb) {
      // (a thumb, for what over it yields to one: Tree::is_thumb)
      let me = thumb.id()
      self.tree.thumbs[me.at] = me
      // (along its track as far as the column is scrolled at the moment drawn, by its offset alone (Node's scroll_off):
      // nothing of it placed again as it scrolls)
      let tn = self.tree.nodes[me.at]
      tn.scroll_by = self.at
      tn.scroll_off = Some(fn(t) {
        let by = track_along(s.where_at(if s.goes_on() { t } else { 0.0 })).0 - track_along(0.0).0
        if across {
          (by, 0.0)
        } else {
          (0.0, by)
        }
      })
      thumb.owns(fn() { if self.tree.thumbs.get(me.at) == Some(me) { self.tree.thumbs.remove(me.at) } }) |> ignore
      let held_y = Ref(0.0)
      let long = fn() { Some(track(0.0).1 + b.grab * 2.0) }
      let thick = Is(Some(b.size + b.grab * 2.0))
      // (along its right; across, along its foot)
      (if across { thumb.height(thick).width(By(long)) } else { thumb.width(thick).height(By(long)) })
      .offset(By(fn() {
        let (w, h) = s.seen.get().unwrap_or((0.0, 0.0))
        if across {
          (track(0.0).0 - b.grab, h - b.inset - b.size - b.grab)
        } else {
          (w - b.inset - b.size - b.grab, track(0.0).0 - b.grab)
        }
      }))
      // (a target while it shows: coming, out or going, or out at rest along its edge or held; said by its state,
      // never by the time, as a structure's change is said)
      .presses(By(fn() {
        (b.drawn)() && has_bar() && bar.phase.get() != 0
      }))
      .on_drag(fn(d) {
        match d.kind {
          Down => {
            // (the hand on its thumb: what the column kept in sight for the focus kept no more, Tree::holds_now)
            self.tree.focus_holds.remove(self.at) |> ignore
            bar.woke(b, self, d.at)
            bar.held.set(true)
            bar.rested_at(b, self)
            held_y.val = if across { d.wx } else { d.wy }
            s.stopped(d.at) |> ignore
          }
          Moved => {
            let (_, _, sc) = self.tree.placed(self.at)
            let (_, _, ratio) = track(s.at(self.tree))
            let w = if across { d.wx } else { d.wy }
            s.moved(d.at, (w - held_y.val) / (if sc > 0.0 { sc } else { 1.0 }) * ratio) |> ignore
            held_y.val = w
          }
          Up | Off => {
            bar.held.set(false)
            bar.let_go.set(d.at)
            bar.rested_at(b, self)
          }
        }
      })
      |> ignore
      thumb.box(fn(ink) {
        let long = fn() { Some(track(0.0).1) }
        (if across { ink.height(Is(Some(b.size))).width(By(long)) } else { ink.width(Is(Some(b.size))).height(By(long)) })
        .offset(Is((b.grab, b.grab)))
        .radius(Is(b.size / 2.0))
        .ground(By(fn() { if bar.held.get() || thumb.pointed() { (b.ink_held)() } else { (b.ink)() } }))
        .alpha(By(level))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

