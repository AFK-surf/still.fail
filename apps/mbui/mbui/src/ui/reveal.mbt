// A change of theme shown spreading from where it was asked (Telegram's): the window as it was drawn (reveal_from:
// its last frame's instances, kept as they were painted) drawn again under; the window as it is now comes over it in a
// circle growing from that point till it covers it all (reveal_ms, easing out). Asked by what changes the theme (a
// person's pick of it, at the point they picked it), it sets out in the first frame whose view is drawn in another
// theme (the pick goes through the app's settings first): told by the view's build itself, so that frame is already in
// the circle; let go when none is in reveal_wait_most. The old frame is drawn again as any part kept is (kept_part.mbt
// insts_replay): no picture read back, encoded or decoded, so it is there at once, at any size, on every host. While
// it spreads the window's presses go to what shows in the circle; what lies over the page (overlay.mbt's layers) is
// over both, as it is. Where the window is the tree's (view_host.mbt), the tree and its old views are drawn over the
// window as it was, cut to the circle, as the old frame's layer is (Ctx::view_paint, reveal_layers).

///|
/// The reveal asked: whether one is, the window as it was (its instances, the first `floats` numbers, and the pieces of
/// their shapes), where it spreads from, the theme it was drawn in and how to tell the one it is drawn in now, when it
/// was asked and when it set out (-1: not yet), what moves it; while it spreads, the frame's two layers (the window as
/// it was, as it is: -1 none) and the window's size, the circle's reach worked out from it as it is painted
/// (reveal_reach).
priv struct Reveal {
  mut on : Bool
  mut insts : FixedArray[Double]
  mut floats : Int
  segs : Array[Double]
  mut x : Double
  mut y : Double
  mut dark : Bool
  mut dark_now : () -> Bool
  mut asked : Double
  mut start : Double
  mover : Mover
  mut was_at : Int
  mut now_at : Int
  mut w : Double
  mut h : Double
}

///|
// kept across runs: said by the app asking it and the frames drawing it; reveal_reset puts it back
let reveal : Reveal = {
  on: false,
  insts: FixedArray::make(1, 0.0),
  floats: 0,
  segs: [],
  x: 0.0,
  y: 0.0,
  dark: false,
  dark_now: fn() { false },
  asked: 0.0,
  start: -1.0,
  mover: Mover::new(),
  was_at: -1,
  now_at: -1,
  w: 0.0,
  h: 0.0,
}

///|
fn reveal_reset() -> Unit {
  reveal_drop()
}

///|
fn reveal_drop() -> Unit {
  reveal.on = false
  reveal.insts = FixedArray::make(1, 0.0)
  reveal.floats = 0
  reveal.segs.clear()
  reveal.start = -1.0
  reveal.dark_now = fn() { false }
  reveal.was_at = -1
  reveal.now_at = -1
}

///|
/// The boxes of the window as it was and as it is: the window's.
// kept across runs: a value (no field of it changes)
let reveal_view : Style = css("w=Full h=Full")

///|
/// How long the circle takes to cover the window, and how long a reveal asked waits for the theme to change.
pub let reveal_ms : Double = 620.0

///|
let reveal_wait_most : Double = 3000.0

///|
/// The circle's way: its end, for the frames to go on till then (Ctx::moving).
priv struct RevealRun {
  end : Double
}

///|
impl Moving for RevealRun with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.end
}

///|
/// The theme is about to change (a person picked another), shown spreading from (`x`, `y`) in the window: the window as
/// it is drawn now kept as a picture, the next one coming over it from there once the theme it is drawn in changes.
/// `dark` says whether the view is drawn dark, read as its build ends (the window's theme's by default; an app that
/// themes its view itself, `with_theme` in it, says its own). Asked as a person picks (a press's handler, a node's or
/// an old view's told), the window's last frame as it was painted.
pub fn reveal_from(x : Double, y : Double, dark? : () -> Bool) -> Unit {
  let self = g()
  let dark_now = match dark {
    Some(f) => f
    None => fn() { self.theme.dark }
  }
  let n = self.ninst
  if n == 0 {
    return
  }
  reveal_drop()
  self.flat_from(0)
  // (the last frame's instances and their shapes' pieces, as it was painted: this frame is not painted yet)
  reveal.floats = n * inst_size
  reveal.insts = FixedArray::make(reveal.floats, 0.0)
  self.inst.blit_to(reveal.insts, len=reveal.floats)
  reveal.segs.append(self.segs)
  reveal.on = true
  reveal.x = x
  reveal.y = y
  reveal.dark = dark_now()
  reveal.dark_now = dark_now
  reveal.asked = self.clock
}

///|
/// The view (`view`, the window `w` by `h`), under a reveal while one spreads (see the file's head): while one is asked,
/// the view built in a box over where the old frame is drawn again, drawn cut to the circle (a look worked out as it is
/// painted: pressed as laid out, the whole window) once it is built and has said its theme. Built again at the moment
/// it is over, or waited for its theme too long, to let it go: nothing built for the circle as it grows.
fn Ctx::revealed(self : Ctx, w : Double, h : Double, view : () -> Unit) -> Unit {
  // (said again by each build that spreads it)
  reveal.was_at = -1
  reveal.now_at = -1
  // (done, or waited for its theme too long: let go before it is built, so each build of the frame builds the same)
  let at = self.moment()
  if reveal.on &&
    (if reveal.start >= 0.0 {
      at >= reveal.start + reveal_ms
    } else {
      at > reveal.asked + reveal_wait_most
    }) {
    reveal_drop()
  }
  if !reveal.on {
    view()
    return
  }
  // the window as it was, under (drawn again once it sets out); the window as it is, over it
  let was = self.layer(fn() { self.box(style=reveal_view, fn() {  }) |> ignore })
  let now = self.layer(fn() { self.box(style=reveal_view, fn() { view() }) |> ignore })
  if reveal.start < 0.0 && (reveal.dark_now)() != reveal.dark {
    reveal.start = self.clock
    let run : RevealRun = { end: self.clock + reveal_ms }
    self.moving(reveal.mover, run as &Moving, what="the theme's reveal")
  }
  if reveal.start < 0.0 {
    // not set out: the view as it is, till its theme changes or it has waited too long (a frame then, to let it go)
    self.wake_at_time(reveal.asked + reveal_wait_most + 1.0)
    return
  }
  // (a frame as it is over, to let it go)
  self.wake_at_time(reveal.start + reveal_ms)
  let (insts, floats, segs) = (reveal.insts, reveal.floats, reveal.segs)
  self.nodes[was].paints = Some(fn(_n, _alpha) { self.insts_replay(insts, floats, segs) })
  reveal.w = w
  reveal.h = h
  let (ox, oy) = (reveal.x / w, reveal.y / h)
  self.look_by(now, fn() { look(ox~, oy~, circle=reveal_reach(self.now())) })
  reveal.was_at = was
  reveal.now_at = now
}

///|
/// How far the circle reaches at `now`, as it spreads: from where it is asked (half a point as it sets out) to the
/// window's furthest corner from there, reveal_ms on, easing out.
fn reveal_reach(now : Double) -> Double {
  let p = dmin(1.0, (now - reveal.start) / reveal_ms)
  let e = 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p)
  let fx = dmax(reveal.x, reveal.w - reveal.x)
  let fy = dmax(reveal.y, reveal.h - reveal.y)
  dmax(0.5, (fx * fx + fy * fy).sqrt() * e)
}

///|
/// While a reveal spreads in the frame built last: its layer of the window as it was, its layer of the window as it is,
/// and the circle (where it spreads from, how far it reaches as the frame is painted). For the window's tree painted
/// (Ctx::view_paint): the tree and its old views over the window as it was, cut to the circle, as that layer is.
fn reveal_layers(c : Ctx) -> (Int, Int, Double, Double, Double)? {
  if reveal.on && reveal.was_at >= 0 && reveal.now_at >= 0 {
    Some((reveal.was_at, reveal.now_at, reveal.x, reveal.y, reveal_reach(c.now())))
  } else {
    None
  }
}

///|
/// Whether a change of theme is spreading now (what a test of a page that asks one looks for).
pub fn reveal_spreading() -> Bool {
  reveal.on && reveal.start >= 0.0
}
