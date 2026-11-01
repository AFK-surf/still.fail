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
  scrolled : @signals.Signal[Double]
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
    scrolled: @signals.signal(-1.0e9, same=fn(a, b) { a == b }),
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
    dmax(dmax(self.scrolled.get(), (self.fling_end)()), dmax(self.near_left.get(), self.let_go.get())) + b.hold_ms
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
/// Come out at `now` (what it is for scrolled then, `scrolled`; the pointer come to it, its thumb held), from how far it
/// shows then unless it is out already, as one change; at rest, said on the timeline, once it has gone (or come, while
/// it stays).
fn BarState::woke(self : BarState, b : ScrollBar, v : View, now : Double, scrolled? : Bool = false) -> Unit {
  @signals.untracked(fn() {
    if now >= self.hides_at(b) {
      self.in_from.set(self.shown(b, now))
      self.in_at.set(now)
    }
    if scrolled {
      self.scrolled.set(now)
    }
    self.rested_at(b, v)
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
    let now = v.logic_at()
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
/// The bar of column `v` (View::scrolls'), scrolled by `s`, as `b` says: a thumb along its right, its edge's strip
/// bringing it out where the pointer is along it.
fn View::scroll_bar(self : View, s : Scroll, b : ScrollBar, bar : BarState) -> Unit {
  // (where its thumb runs and how long, how far the column goes for a point it moves: ui's bar_track over all of its
  // right, nothing over it kept clear)
  let track = fn(x : Double) {
    let vh = match self.laid_size_told() {
      Some((_, h)) => h
      None => 0.0
    }
    let content = vh + s.most_now()
    let long = dmin(vh, dmax(b.least, vh * vh / dmax(content, 1.0))) - b.inset * 2.0
    let room = vh - b.inset * 2.0 - long
    let p = if content > vh { dclamp(x / (content - vh), 0.0, 1.0) } else { 0.0 }
    (b.inset + p * room, long, (content - vh) / dmax(room, 1.0))
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
      1 | 3 => bar.shown(b, self.drawn_at())
      // (out: as it stands, unless what is drawn is drawn past where it starts to go, the logic not come to it yet:
      // from there by the time as drawn)
      2 => {
        let hide = bar.hides_at(b)
        if hide < 1.0e299 && self.drawn_past(hide) {
          bar.shown(b, self.drawn_at())
        } else {
          bar.shown(b, @signals.untracked(fn() { self.logic_at() }))
        }
      }
      _ => 0.0
    }
  }
  self.box(fn(over) {
    // (over what it holds, none of the column's own fading what it holds: its own showing alone; what holds the
    // column fading it as it fades the column)
    over.over(Is(true)).fades_clear_of(self) |> ignore
    // (the pointer along its right brings it out: the innermost column at the pointer's, View::bar_near)
    over.reacts(fn() { (b.drawn)() && self.bar_near(if has_bar() { b.near } else { 0.0 }) }, fn(on) {
      let t = self.logic_at()
      // (come out first, then along it: as ui's bar_near does, its coming in from how far it showed then)
      if on {
        bar.woke(b, self, t)
        bar.near.set(true)
        bar.rested_at(b, self)
      } else if @signals.untracked(fn() { bar.near.get() }) {
        bar.near.set(false)
        bar.near_left.set(t)
        bar.rested_at(b, self)
      }
    })
    // (its thumb, and as far round it as a press takes it: held, it moves the column as far as it goes for a point)
    over.box(fn(thumb) {
      let held_y = Ref(0.0)
      thumb
      .width(Is(Some(b.size + b.grab * 2.0)))
      .height(By(fn() { Some(track(s.where_at(0.0)).1 + b.grab * 2.0) }))
      .offset(By(fn() {
        let w = self.laid_size_told().map(fn(z) { z.0 }).unwrap_or(0.0)
        let x = s.where_at(if s.fling.get() is Some(_) { thumb.drawn_at() } else { 0.0 })
        (w - b.inset - b.size - b.grab, track(x).0 - b.grab)
      }))
      // (a target while it shows: coming, out or going, or out at rest along its edge or held; said by its state,
      // never by the time, as a structure's change is said)
      .presses(By(fn() {
        (b.drawn)() && has_bar() && bar.phase.get() != 0
      }))
      .on_drag(fn(d) {
        match d.kind {
          Down => {
            bar.woke(b, self, d.at)
            bar.held.set(true)
            bar.rested_at(b, self)
            held_y.val = d.wy
            s.stopped(d.at) |> ignore
          }
          Moved => {
            let (_, _, sc) = self.tree.placed(self.at)
            let (_, _, ratio) = track(s.at(self.tree))
            s.moved(d.at, (d.wy - held_y.val) / (if sc > 0.0 { sc } else { 1.0 }) * ratio) |> ignore
            held_y.val = d.wy
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
        ink
        .width(Is(Some(b.size)))
        .height(By(fn() { Some(track(s.where_at(0.0)).1) }))
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

