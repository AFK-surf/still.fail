// A stack of pages, as still.fail's Android app moves between them
// (app/App.kt Pages): a page pushed comes in whole from the right as the one
// under it goes out whole to the left, side by side, 300 ms on the standard
// curve (.4, 0, .2, 1), nothing fading; back, the other way. Swiped back
// (from the left edge with a finger or a mouse here, or the system's back
// gesture where there is one, Android's predictive back), the page follows
// the finger and the one under it comes along beside it, edge to edge; let
// go past a third of the way (or flung) it goes on from there, easing out
// (.25, .46, .45, .94) over what is left of 280 ms (120 at least), else it
// comes back in 200 ms.
//
// Only the top page is built while nothing moves; the pages under it keep
// what their widgets hold (a list's scroll, a field's words), each page's
// ids in a scope of its own, until the page leaves the stack: then it is
// forgotten (and `on_leave` told, for what the app keeps for it), so the
// same page pushed again starts afresh.

///|
struct NavPage[P] {
  serial : Int
  mut page : P
  // it rose from the bottom (Nav::rise): it goes back down the same way
  mut rise : Bool
}

///|
/// Pages' serials, unique across every Nav: a page's scope and its state's
/// owner.
// kept across runs: it goes on counting: a Nav made before its Tester holds pages numbered already
let nav_serial : Ref[Int] = { val: 0 }

///|
fn[P] nav_page(page : P) -> NavPage[P] {
  nav_serial.val = nav_serial.val + 1
  { serial: nav_serial.val, page, rise: false }
}

///|
struct Nav[P] {
  pages : Array[NavPage[P]]
  // 0 at rest; 1 a page coming in; 2 the top going (popped); 3 following
  // a finger (or the system's back gesture); 4 coming back to rest from it
  mut mode : Int
  // the page popped, drawn until it has gone
  mut leaving : NavPage[P]?
  // pages gone, to forget at the next frame
  gone : Array[NavPage[P]]
  // how far the top page is off to the right, in its widths (0 in place);
  // the one under it is edge to edge with it, at p - 1
  mut p : Double
  mut p0 : Double
  mut p1 : Double
  // when the motion started (-1: at its first frame), how long, how
  mut t0 : Double
  mut dur : Double
  mut curve : Curve
  // a finger's: where it started, how fast it went (px per ms), its track
  // (for how fast, scroll.mbt)
  mut x0 : Double
  mut vel : Double
  track : Tracker
  on_leave : (P) -> Unit
  /// what its motion is said to move by (Ctx::moving), and the frame it was told to move in
  mover : Mover
  mut asked : Int
}

///|
/// A stack of pages, `root` at the bottom. `on_leave` is told of each page
/// that leaves it for good (popped, once it has slid away).
pub fn[P] Nav::new(root : P, on_leave? : (P) -> Unit = fn(_) {  }) -> Nav[P] {
  {
    pages: [nav_page(root)],
    mode: 0,
    leaving: None,
    gone: [],
    p: 0.0,
    p0: 0.0,
    p1: 0.0,
    t0: -1.0,
    dur: 0.0,
    curve: Standard,
    x0: 0.0,
    vel: 0.0,
    track: Tracker::new(),
    on_leave,
    mover: Mover::new(),
    asked: -1,
  }
}

///|
/// The page on top.
pub fn[P] Nav::top(self : Nav[P]) -> P {
  self.pages[self.pages.length() - 1].page
}

///|
/// How many pages are in the stack.
pub fn[P] Nav::depth(self : Nav[P]) -> Int {
  self.pages.length()
}

///|
/// The pages, bottom to top.
pub fn[P] Nav::pages(self : Nav[P]) -> Array[P] {
  self.pages.map(fn(e) { e.page })
}

///|
/// Whether a page is moving (pushed, popped, followed by a finger).
pub fn[P] Nav::moving(self : Nav[P]) -> Bool {
  self.mode != 0
}

///|
/// How far the top page is off to the side now, in its widths.
pub fn[P] Nav::offset(self : Nav[P]) -> Double {
  self.p
}

///|
fn[P] Nav::go(self : Nav[P], mode : Int, p1 : Double, dur : Double, curve : Curve) -> Unit {
  wake()
  self.mode = mode
  self.p0 = self.p
  self.p1 = p1
  self.dur = dur
  self.curve = curve
  self.t0 = -1.0
  // said once, as it sets out: frames until it is there (it starts at the next frame)
  self.asked = g().frame_no
  g().moving(self.mover, self as &Moving, what="a stack's slide")
}

///|
/// When its slide is over, asked at each frame's end while it slides: read only, the same whoever asks first. Told to
/// go, it starts at the first frame after that builds it (Ctx::nav sets its start): until then +inf; not built in
/// that frame, at rest, said to move again as Ctx::nav starts it.
impl[P] Moving for Nav[P] with rest_at(self, now, frame) {
  ignore(now)
  if self.mode != 1 && self.mode != 2 && self.mode != 4 {
    -1.0
  } else if self.t0 >= 0.0 {
    self.t0 + self.dur
  } else if frame <= self.asked {
    1.0 / 0.0
  } else {
    -1.0
  }
}

///|
/// When the stacks built in the last frame (Ctx::nav) are all at rest: the latest of their slides' ends (the frames'
/// clock; -1: none slides; +inf: told to slide, not started yet). What a test runs to after a page pushed, popped or
/// let go, when it holds no stack itself (an app's own).
pub fn nav_rest() -> Double {
  g().nav_rest
}

///|
/// When this stack's slide is over (the frames' clock; +inf: told to go, not started yet; -1: it is not sliding): what
/// a test runs to.
pub fn[P] Nav::rest(self : Nav[P]) -> Double {
  self.rest_at(g().now, g().frame_no)
}

///|
/// Ends what moves at once, where it was going.
fn[P] Nav::settle(self : Nav[P]) -> Unit {
  match self.leaving {
    Some(e) => {
      // forgotten at the next frame
      self.gone.push(e)
      wake()
    }
    None => ()
  }
  self.leaving = None
  self.mode = 0
  self.p = 0.0
}

///|
/// How long a page takes to slide in over the one on top, and back off it (popped).
pub let nav_push_ms : Double = 300.0

///|
/// How long a page takes to rise from the bottom (Nav::rise), and to sink back.
pub let nav_rise_ms : Double = 380.0

///|
/// How long a page let go short of going back takes to come back to its place.
pub let nav_return_ms : Double = 200.0

///|
/// A page let go to go back goes on for this much of the way it had left (at most, from where the finger had it),
/// and never for less than `nav_let_go_min_ms`.
pub let nav_let_go_ms : Double = 280.0

///|
pub let nav_let_go_min_ms : Double = 120.0

///|
/// Pushes `page`: it slides in over the one on top.
pub fn[P] Nav::push(self : Nav[P], page : P) -> Unit {
  self.settle()
  self.pages.push(nav_page(page))
  self.p = 1.0
  self.go(1, 0.0, nav_push_ms, Standard)
}

///|
/// Pushes `page` rising from the bottom over the one on top, which stays where it is (App.kt: a new chat, 380 ms on
/// (.2, .8, .2, 1)); back, it sinks down the same way (swiped back, it goes down with the finger).
pub fn[P] Nav::rise(self : Nav[P], page : P) -> Unit {
  self.settle()
  let e = nav_page(page)
  e.rise = true
  self.pages.push(e)
  self.p = 1.0
  self.go(1, 0.0, nav_rise_ms, Arrive)
}

///|
/// The top page becomes `page` in place, keeping what its widgets hold (a new chat becoming the chat it made, its
/// composer's words and focus kept); back from it, it goes sideways as a pushed page does.
pub fn[P] Nav::become(self : Nav[P], page : P) -> Unit {
  let e = self.pages[self.pages.length() - 1]
  e.page = page
  e.rise = false
  wake()
}

///|
/// Whether the top page rose from the bottom (Nav::rise) and has not become another.
pub fn[P] Nav::risen(self : Nav[P]) -> Bool {
  self.pages[self.pages.length() - 1].rise
}

///|
/// Back a page: the top slides away; false when there is none under it.
pub fn[P] Nav::pop(self : Nav[P]) -> Bool {
  if self.pages.length() < 2 {
    return false
  }
  if self.mode != 0 && self.mode != 3 {
    self.settle()
    if self.pages.length() < 2 {
      return false
    }
  }
  self.leaving = self.pages.pop()
  match self.leaving {
    Some(e) if e.rise => self.go(2, 1.0, nav_rise_ms, Arrive)
    _ => self.go(2, 1.0, nav_push_ms, Standard)
  }
  true
}

///|
/// The top page replaced by `page`, in place (nothing slides).
pub fn[P] Nav::replace(self : Nav[P], page : P) -> Unit {
  self.settle()
  match self.pages.pop() {
    Some(e) => self.gone.push(e)
    None => ()
  }
  self.pages.push(nav_page(page))
  wake()
}

///|
/// A frame, for what changed outside of one (or within one, after it).
fn wake() -> Unit {
  g().request_frame()
  h_request_frame()
}

///|
/// Back as a back gesture asks: kind 0 started at x (in a view `w` wide), 1
/// moved to x, 2 let go there (back if past a third or flung), 3 called
/// off, 4 back (the system decided: from where a gesture had it, or a back
/// with none); `t` the time.
fn[P] Nav::gesture(self : Nav[P], kind : Int, x : Double, w : Double, t : Double) -> Unit {
  let w = dmax(w, 1.0)
  match kind {
    0 =>
      if self.mode == 0 && self.pages.length() > 1 {
        self.mode = 3
        self.p = 0.0
        self.x0 = x
        self.vel = 0.0
        self.track.reset()
        self.track.add(t, x)
      }
    1 =>
      if self.mode == 3 {
        self.p = dclamp((x - self.x0) / w, 0.0, 1.0)
        self.track.add(t, x)
      }
    2 =>
      if self.mode == 3 {
        let dx = self.p * w
        // where it was let go counts too: held still first, it was not flung
        self.track.add(t, x)
        self.vel = self.track.velocity()
        let flung = dx > 40.0 && self.vel > 0.6
        if self.p > 1.0 / 3.0 || flung {
          self.let_go()
        } else {
          self.go(4, 0.0, nav_return_ms, Standard)
        }
      }
    3 => if self.mode == 3 { self.go(4, 0.0, nav_return_ms, Standard) }
    _ => if self.mode == 3 { self.let_go() } else { self.pop() |> ignore }
  }
}

///|
/// Gone back from where a finger left the page: on from there, easing out.
fn[P] Nav::let_go(self : Nav[P]) -> Unit {
  self.leaving = self.pages.pop()
  self.go(2, 1.0, dmax(nav_let_go_ms * (1.0 - self.p), nav_let_go_min_ms), LetGo)
}

///|
/// The stack drawn, filling what it is given: the top page (and, while one
/// moves, the page beside it), each built by `page` on a ground of `bg`.
/// Back (Ctx::back, the left edge's swipe within `edge` of its side, the
/// system's) comes here while it has a page to go back to.
pub fn[P] Ctx::nav(
  self : Ctx,
  nav : Nav[P],
  page : (P) -> Unit,
  bg? : Int64 = 0L,
  edge? : Double = 20.0,
) -> Int {
  for e in nav.gone {
    self.forget(e.serial)
    (nav.on_leave)(e.page)
  }
  nav.gone.clear()
  if nav.mode == 1 || nav.mode == 2 || nav.mode == 4 {
    if nav.t0 < 0.0 {
      // it starts now: said to move again (not built in the frame it was to start in, it had been let be)
      nav.t0 = self.now
      self.moving(nav.mover, nav as &Moving, what="a stack's slide")
    }
    let t = if nav.dur <= 0.0 { 1.0 } else { (self.now - nav.t0) / nav.dur }
    nav.p = nav.p0 + (nav.p1 - nav.p0) * nav.curve.at(dmin(t, 1.0))
    if t >= 1.0 {
      nav.settle()
    }
    let r = nav.rest_at(self.now, self.frame_no)
    if r > self.nav_rest {
      self.nav_rest = r
    }
  }
  let n = nav.pages.length()
  let top = match nav.leaving {
    Some(e) => e
    None => nav.pages[n - 1]
  }
  let under = match nav.leaving {
    Some(_) => Some(nav.pages[n - 1])
    None => if nav.mode != 0 && n > 1 { Some(nav.pages[n - 2]) } else { None }
  }
  let p = nav.p
  // a page that rose goes up and down over the one under it, which stays
  let rising = top.rise
  let i = self.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
    match under {
      Some(e) => self.nav_layer(e, if rising { 0.0 } else { p - 1.0 }, 0.0, bg, page)
      None => ()
    }
    self.nav_layer(top, if rising { 0.0 } else { p }, if rising { p * self.height } else { 0.0 }, bg, page)
  })
  if n > 1 || nav.mode != 0 {
    self.back_next = Some(fn(kind, x, w, t) { nav.gesture(kind, x, w, t) })
    self.back_node_next = i
    self.back_edge_next = edge
  }
  i
}

///|
fn[P] Ctx::nav_layer(
  self : Ctx,
  e : NavPage[P],
  slide : Double,
  drop : Double,
  bg : Int64,
  page : (P) -> Unit,
) -> Unit {
  let i = self.box(w=Fill(1.0), h=Fill(1.0), bg~, ty=drop, fn() {
    let saved = self.owner
    self.owner = e.serial
    self.scope(e.serial, fn() { page(e.page) })
    self.owner = saved
  })
  self.nodes[i].layer = true
  self.nodes[i].slide = slide
}

///|
/// Notes widget state `id` as the current page's (forgotten with it).
fn Ctx::own(self : Ctx, id : Int) -> Unit {
  if self.owner != 0 {
    match self.owned.get(self.owner) {
      Some(a) => a.push(id)
      None => self.owned[self.owner] = [id]
    }
  }
}

///|
/// Forgets what page `serial`'s widgets held.
fn Ctx::forget(self : Ctx, serial : Int) -> Unit {
  match self.owned.get(serial) {
    Some(ids) => {
      for id in ids {
        self.lists.remove(id)
        self.editors.remove(id)
        self.springs.remove(id)
        pagers.remove(id)
        drags.remove(id)
        code_fields.remove(id)
        if self.focus == id {
          self.focus = 0
        }
      }
      self.owned.remove(serial)
    }
    None => ()
  }
}

///|
/// Back, as a back button asks: the stack drawn last (the innermost that
/// can) goes back a page. False when nothing could.
pub fn Ctx::back(self : Ctx) -> Bool {
  match self.back {
    Some(f) => {
      f(4, 0.0, 1.0, self.now)
      self.request_frame()
      h_request_frame()
      true
    }
    None => false
  }
}

///|
/// Back taken by what is drawn over the stack (a viewer, a sheet), on the frames it calls this, after the stack is
/// drawn: the system's back, a back button (Ctx::back) call `f` once let go; no edge swipe of its own.
pub fn Ctx::take_back(self : Ctx, f : () -> Unit) -> Unit {
  self.back_next = Some(fn(kind, _x, _w, _t) {
    if kind == 2 || kind == 4 {
      f()
    }
  })
  self.back_node_next = -1
}

///|
/// The top page of `nav` alone, in place, nothing sliding and nothing swiped back: a desktop's pane beside a sidebar,
/// whose pages are the same stack as a phone's (Ctx::nav draws it so on a narrow window). A page gone is forgotten
/// (its widgets' state, `on_leave` told) as Ctx::nav forgets it; one moving is put where it was going.
pub fn[P] Ctx::nav_flat(self : Ctx, nav : Nav[P], page : (P) -> Unit, bg? : Int64 = 0L) -> Int {
  for e in nav.gone {
    self.forget(e.serial)
    (nav.on_leave)(e.page)
  }
  nav.gone.clear()
  if nav.mode != 0 || nav.leaving is Some(_) {
    nav.settle()
  }
  let top = nav.pages[nav.pages.length() - 1]
  self.box(w=Fill(1.0), h=Fill(1.0), clip=true, bg~, fn() {
    let saved = self.owner
    self.owner = top.serial
    self.scope(top.serial, fn() { page(top.page) })
    self.owner = saved
  })
}
