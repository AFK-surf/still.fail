// A stack of pages, as still.fail's Android app moves between them
// (app/App.kt Pages): a page pushed comes in whole from the right as the one
// under it goes out whole to the left, side by side, 300 ms on the standard
// curve (.4, 0, .2, 1), nothing fading; back, the other way. A page the
// stack says comes from the left (`from_left`: still.fail's settings, its
// gear at the top left) comes in from there, the one under it going out to
// the right, and goes back that way. Swiped back
// (from the left edge with a finger or a mouse here; on Android, the system's
// back gesture, its predictive back, and no edge of mbui's), the page follows
// the finger and the one under it comes along beside it, edge to edge; let
// go past a third of the way (or flung) it goes on from there, easing out
// (.25, .46, .45, .94) over what is left of 280 ms (120 at least), else it
// comes back in 200 ms.
//
// A page brought in (pushed, risen, gone back to) is built whole in the frame its slide starts in, which may take longer
// than the display's frame (its words shaped, its rows laid out for the first time): its slide's clock does not run
// while that frame is late to the screen (the host says how late: @hostapi.frame_late), up to nav_late_most, so it
// moves from where that frame drew it at the display's pace, no step skipped, the wait before it moves instead
// (UIKit's and Android's transitions build the page before they start too).
//
// While a page slides in, the one it covers takes no press (drawn only, as UIKit's and Android's transitions keep
// touches from the page underneath): a press where its button still shows goes to the page coming, or to nothing;
// going back, the page leaving takes none.
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
  // the page under it as it was put on the stack (none: the root); only the top changes, so it stays so while it is
  // there
  under : P?
  // it rose from the bottom (Nav::rise): it goes back down the same way
  mut rise : Bool
  // its time on top: a number of its own each time it is put there (pushed, or come back to as the one over it went),
  // what is built on it reads (Ctx::page_stint)
  mut stint : Int
}

///|
/// Pages' serials, unique across every Nav: a page's scope and its state's
/// owner.
// kept across runs: it goes on counting: a Nav made before its Tester holds pages numbered already
let nav_serial : Ref[Int] = { val: 0 }

///|
fn[P] nav_page(page : P, under : P?) -> NavPage[P] {
  nav_serial.val = nav_serial.val + 1
  { serial: nav_serial.val, page, under, rise: false, stint: next_stint() }
}

///|
/// Pages' times on top, unique across every Nav.
// kept across runs: it goes on counting, as nav_serial does
let nav_stint : Ref[Int] = { val: 0 }

///|
fn next_stint() -> Int {
  nav_stint.val = nav_stint.val + 1
  nav_stint.val
}

///|
/// The page now on top (the one under a page that went) put there anew.
fn[P] Nav::topped(self : Nav[P]) -> Unit {
  if self.pages.length() > 0 {
    self.pages[self.pages.length() - 1].stint = next_stint()
  }
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
  // how far the top page is off to its side, in its widths (0 in place):
  // the right, or the left for one from the left (from_left); the one under
  // it is edge to edge with it, at p - 1 (1 - p)
  mut p : Double
  mut p0 : Double
  mut p1 : Double
  // when the motion started (-1: at its first frame), how long, how
  mut t0 : Double
  mut dur : Double
  mut curve : Ease
  // a finger's: where it started, how fast it went (px per ms), its track
  // (for how fast, scroll.mbt)
  mut x0 : Double
  mut vel : Double
  track : Tracker
  on_leave : (P) -> Unit
  // the pages that come in from the left and go back that way
  from_left : (P) -> Bool
  /// what its motion is said to move by (Ctx::moving), and the frame it was told to move in
  mover : Mover
  mut asked : Int
  // a page pushed waiting for what it shows (Nav::comes_when): since when (-1: not asked of this push), and whether
  // its wait is over; while it waits its slide is held (t0 -2)
  mut wait_from : Double
  mut waited : Bool
  mut held_most : Double
  // a slide bringing a page in, its start moved on by how late its first frame reached the screen: whether it is still
  // to be, and that frame's time (-1: not drawn yet)
  mut waits_late : Bool
  mut late_at : Double
  // drawn flat (Ctx::nav_flat): the page drawn there last (in frame `flat_frame`), and the page put on top since,
  // waited for (Nav::shows_when, asked in frame `flat_asked`) from `flat_from`, `flat_most` ms at most
  mut flat_shown : NavPage[P]?
  mut flat_frame : Int
  mut flat_ready : () -> Bool
  mut flat_most : Double
  mut flat_asked : Int
  mut flat_for : Int
  mut flat_from : Double
  // the page being built (Ctx::nav, Ctx::nav_flat), what Nav::under answers for
  mut built : NavPage[P]?
}

///|
/// A stack of pages, `root` at the bottom. `on_leave` is told of each page
/// that leaves it for good (popped, once it has slid away); a page
/// `from_left` says yes to slides in from the left and back out that way
/// (App.kt transition: Settings), swiped back too.
pub fn[P] Nav::new(
  root : P,
  on_leave? : (P) -> Unit = fn(_) {  },
  from_left? : (P) -> Bool = fn(_) { false },
) -> Nav[P] {
  {
    pages: [nav_page(root, None)],
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
    from_left,
    mover: Mover::new(),
    asked: -1,
    wait_from: -1.0,
    waited: false,
    held_most: 0.0,
    waits_late: false,
    late_at: -1.0,
    flat_shown: None,
    flat_frame: -1,
    flat_ready: fn() { true },
    flat_most: 0.0,
    flat_asked: -1,
    flat_for: -1,
    flat_from: -1.0,
    built: None,
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
/// The page under the one being built (Ctx::nav, Ctx::nav_flat: the top, the one under it as a page slides over it
/// or away, one leaving, one kept shown while the next is waited for), none under the root; outside them, the top's.
/// What a page asks of where it stands (whether it is the root, where its back goes), never the stack's depth or the
/// page under its top: those are the top's, and a root under a page coming in is still the root.
pub fn[P] Nav::under(self : Nav[P]) -> P? {
  match self.built {
    Some(e) => e.under
    None => self.pages[self.pages.length() - 1].under
  }
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
fn[P] Nav::go(
  self : Nav[P],
  mode : Int,
  p1 : Double,
  dur : Double,
  curve : Ease,
  brings? : Bool = false,
) -> Unit {
  wake()
  self.mode = mode
  self.p0 = self.p
  self.p1 = p1
  self.dur = dur
  self.curve = curve
  // told in a frame, it starts there, at its time (its end known as it is told); told between frames, at the next
  // frame that builds it (Ctx::nav)
  self.t0 = if in_frame.val { g().now } else { -1.0 }
  self.wait_from = -1.0
  self.waited = false
  // (a page brought in: its start moved on by how late its first frame is to the screen)
  self.waits_late = brings
  self.late_at = -1.0
  // said once, as it sets out: frames until it is there
  self.asked = g().frame_no
  g().moving(self.mover, self as &Moving, what="a stack's slide")
}

///|
/// When its slide is over, asked at each frame's end while it slides: read only, the same whoever asks first. Told to
/// go between frames, it starts at the first frame after that builds it (Ctx::nav sets its start): until then +inf;
/// not built in that frame, at rest, said to move again as Ctx::nav starts it.
impl[P] Moving for Nav[P] with rest_at(self, now, frame) {
  ignore(now)
  if self.mode != 1 && self.mode != 2 && self.mode != 4 {
    -1.0
  } else if self.t0 == nav_held {
    // held for what its page shows (its coming, or the most it waits, a wake, starts it): at rest by the latest its
    // slide could end, said again as it starts
    self.wait_from + self.held_most + self.dur
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
/// A slide held (Nav::comes_when): its start, until it goes.
let nav_held : Double = -2.0

///|
/// The most a slide bringing a page in waits for its first frame to reach the screen (still.fail's LOCAL_MS, as long
/// as a page opening waits for what it shows): later than that, it moves on from its time.
pub let nav_late_most : Double = 100.0

///|
/// The page just pushed slides in once it has what it shows (`ready`, asked while it waits: the core has answered for it), `most` ms at most
/// after it was pushed (still.fail's App.kt: a page opening waits LOCAL_MS for what the core has on the device, never
/// for a station), not first as its loading look swapped for it a frame or two later: till then nothing moves, the
/// page under it as it was. Asked each frame its stack is built, before Ctx::nav; its slide starts at the moment it
/// goes (its readiness come, or the most it waits), its wait from when it was pushed. A push already sliding (asked
/// later than the frame after it) is not held.
pub fn[P] Nav::comes_when(self : Nav[P], ready : () -> Bool, most : Double) -> Unit {
  if self.mode != 1 || self.p0 != 1.0 || self.waited {
    return
  }
  let c = g()
  if self.wait_from < 0.0 {
    // (pushed as the frame before was built, after this was asked in it: drawn there where it starts, nothing moved
    // yet; asked later than that, it slides on)
    if self.t0 >= 0.0 && c.frame_no > self.asked + 1 {
      self.waited = true
      return
    }
    self.wait_from = if self.t0 >= 0.0 { self.t0 } else { c.now }
  }
  if c.now >= self.wait_from + most || ready() {
    self.waited = true
    if self.t0 == nav_held {
      self.t0 = c.now
      // (its first frame this one, the page built with what it shows)
      self.late_at = -1.0
      c.moving(self.mover, self as &Moving, what="a stack's slide")
    }
    return
  }
  self.t0 = nav_held
  self.held_most = most
  c.wake_at_time(self.wait_from + most)
}

///|
/// Drawn flat (Ctx::nav_flat), the page put on top shows once it has what it shows (`ready`), `most` ms at most after
/// it was put there (pushed, or in place of the one on top): till then the page that showed before stays, as it was,
/// not the new one's loading look swapped for it a frame or two later (still.fail's LOCAL_MS, as Nav::comes_when holds
/// a slide). Asked each frame its stack is drawn, before Ctx::nav_flat.
pub fn[P] Nav::shows_when(self : Nav[P], ready : () -> Bool, most : Double) -> Unit {
  self.flat_ready = ready
  self.flat_most = most
  self.flat_asked = g().frame_no
}

///|
/// Pushes `page`: it slides in over the one on top.
pub fn[P] Nav::push(self : Nav[P], page : P) -> Unit {
  self.settle()
  self.pages.push(nav_page(page, Some(self.top())))
  self.p = 1.0
  self.go(1, 0.0, nav_push_ms, Standard, brings=true)
}

///|
/// Pushes `page` rising from the bottom over the one on top, which stays where it is (App.kt: a new chat, 380 ms on
/// (.2, .8, .2, 1)); back, it sinks down the same way (swiped back, it goes down with the finger).
pub fn[P] Nav::rise(self : Nav[P], page : P) -> Unit {
  self.settle()
  let e = nav_page(page, Some(self.top()))
  e.rise = true
  self.pages.push(e)
  self.p = 1.0
  self.go(1, 0.0, nav_rise_ms, Arrive, brings=true)
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
  self.topped()
  match self.leaving {
    Some(e) if e.rise => self.go(2, 1.0, nav_rise_ms, Arrive, brings=true)
    _ => self.go(2, 1.0, nav_push_ms, Standard, brings=true)
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
  self.pages.push(nav_page(page, self.pages.last().map(fn(e) { e.page })))
  wake()
}

///|
/// A stack changed: changed as the frame is built, built again from it in the frame (no frame shows the page it left
/// as it was); between frames, the next frame (Ctx::read_changed).
fn wake() -> Unit {
  g().read_changed("a stack changed")
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
  self.topped()
  self.go(2, 1.0, dmax(nav_let_go_ms * (1.0 - self.p), nav_let_go_min_ms), LetGo)
}

///|
/// The stack drawn, filling what it is given: the top page (and, while one
/// moves, the page beside it), each built by `page` on a ground of `bg`.
/// Back (Ctx::back, the left edge's swipe within `edge` of its side, the
/// system's) comes here while it has a page to go back to, unless the top
/// page takes it itself (what is open in it closed first).
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
  if nav.t0 == nav_held {
    // held for what the page pushed shows (Nav::comes_when): where it was, not moving yet; at rest by the latest its
    // slide could end (nav_rest)
    let r = nav.rest_at(self.now, self.frame_no)
    if r > self.nav_rest {
      self.nav_rest = r
    }
  } else if nav.mode == 1 || nav.mode == 2 || nav.mode == 4 {
    if nav.t0 < 0.0 {
      // it starts now: said to move again (not built in the frame it was to start in, it had been let be)
      nav.t0 = self.now
      self.moving(nav.mover, nav as &Moving, what="a stack's slide")
    }
    // (over at the end it says, t0 + dur, to the bit: (t0 + dur - t0) / dur can fall short of 1 by a rounding, and a
    // frame drawn at the very end it declared would leave it a hair short of it, still sliding)
    // a page brought in: its first frame drawn from where it starts (any built again at its moment with it); the next
    // told how late that one was to the screen
    if nav.waits_late {
      if nav.late_at < 0.0 {
        nav.late_at = self.now
      } else if self.now > nav.late_at {
        nav.waits_late = false
        let late = dmin(h_frame_late(), nav_late_most)
        if late > 0.0 {
          nav.t0 = nav.t0 + late
          self.moving(nav.mover, nav as &Moving, what="a stack's slide")
        }
      }
    }
    // (from where it starts until its start: a start moved on by how late its first frame was)
    let t = if nav.dur <= 0.0 || self.now >= nav.t0 + nav.dur {
      1.0
    } else {
      dmax((self.now - nav.t0) / nav.dur, 0.0)
    }
    nav.p = nav.p0 + (nav.p1 - nav.p0) * nav.curve.at(dmin(t, 1.0))
    if t >= 1.0 {
      nav.settle()
      // the page that slid away forgotten in the frame its slide ends (`on_leave` told), not the next
      for e in nav.gone {
        self.forget(e.serial)
        (nav.on_leave)(e.page)
      }
      nav.gone.clear()
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
  // the side the top page is off to (one from the left goes back left, the page under it coming from the right)
  let way = if (nav.from_left)(top.page) { -1.0 } else { 1.0 }
  // back as it was before the stack, for when neither its top page nor it takes it
  let before = self.back_next
  let before_node = self.back_node_next
  let before_edge = self.back_edge_next
  let leaving = nav.leaving is Some(_)
  let i = self.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
    // (pushed: the page it covers takes nothing from the moment it is pushed)
    match under {
      Some(e) => self.nav_layer(nav, e, if rising { 0.0 } else { way * (p - 1.0) }, 0.0, bg, page, inert=nav.mode == 1)
      None => ()
    }
    // what the top page takes back for (a sheet, a menu, a step of its own, a stack in it) goes back before the stack
    // does, as Android's BackHandler in a page is asked before the pages' own; the page under it, one leaving, take none
    self.back_next = None
    self.back_node_next = -1
    // (going back: the page leaving takes nothing)
    self.nav_layer(nav, top, if rising { 0.0 } else { way * p }, if rising { p * self.height } else { 0.0 }, bg, page, inert=leaving)
  })
  if self.back_next is Some(_) && !leaving {
    ()
  } else if n > 1 || nav.mode != 0 {
    self.back_next = Some(fn(kind, x, w, t) { nav.gesture(kind, x, w, t) })
    self.back_node_next = i
    self.back_edge_next = edge
  } else {
    self.back_next = before
    self.back_node_next = before_node
    self.back_edge_next = before_edge
  }
  i
}

///|
/// Builds `body`, back taken in it (Ctx::on_back, Ctx::take_back, an overlay, a stack: Ctx::nav) kept over what took
/// it before: true when it took it; when not, back is as it was. For what goes back only when nothing within it does
/// (a stack drawn flat, whose pop is taken after it: Ctx::nav_flat).
pub fn Ctx::took_back(self : Ctx, body : () -> Unit) -> Bool {
  let before = self.back_next
  let before_node = self.back_node_next
  let before_edge = self.back_edge_next
  self.back_next = None
  self.back_node_next = -1
  body()
  if self.back_next is Some(_) {
    true
  } else {
    self.back_next = before
    self.back_node_next = before_node
    self.back_edge_next = before_edge
    false
  }
}

///|
fn[P] Ctx::nav_layer(
  self : Ctx,
  nav : Nav[P],
  e : NavPage[P],
  slide : Double,
  drop : Double,
  bg : Int64,
  page : (P) -> Unit,
  inert? : Bool = false,
) -> Unit {
  let i = self.box(w=Fill(1.0), h=Fill(1.0), bg~, ty=drop, fn() {
    let saved = self.owner
    let saved_stint = self.stint
    self.owner = e.serial
    self.stint = e.stint
    nav.built_by(e, fn() { self.scope(e.serial, fn() { page(e.page) }) })
    self.owner = saved
    self.stint = saved_stint
  })
  self.nodes[i].layer = true
  self.nodes[i].slide = slide
  if inert {
    self.draw_only(i)
  }
}

///|
/// `body` building page `e` of the stack (what Nav::under answers for), within whatever page of another is being built.
fn[P] Nav::built_by(self : Nav[P], e : NavPage[P], body : () -> Unit) -> Unit {
  let saved = self.built
  self.built = Some(e)
  body()
  self.built = saved
}

///|
/// The time on top of the page being built (a stack's: a number of its own each time the page is put on top, pushed
/// or come back to; 0 outside any): what is put up anew when its page is (a picture that could not be had asked for
/// again, as Compose's produceState runs again as its page comes back), whatever frames were drawn between.
pub fn Ctx::page_stint(self : Ctx) -> Int {
  self.stint
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
      self.read_changed("gone back")
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
/// A step of back as a gesture goes (Ctx::follow_back): begun at x (from the edge it came from, its time), moved to x,
/// let go at x (back if it went far enough or fast enough: whose back it is decides, as a stack does), called off; or
/// back now (the system decided, from where the gesture had it, or a back with no gesture: a back key, ⌘[).
pub(all) enum BackStep {
  Began(Double, Double)
  Moved(Double, Double)
  LetGo(Double, Double)
  CalledOff
  Back
} derive(Eq, Show, Debug)

///|
/// Back taken by what is drawn over the stack, on the frames it calls this, after the stack is drawn, followed as it
/// goes (Ctx::take_back's, step by step): the system's back gesture (Android's predictive back, from either edge: x
/// from the edge it came from, as a stack's page follows it) and a back with no gesture come to `f` as their steps;
/// for what moves back with the finger as a stack's page does without being one (a tape's panels). No edge swipe of
/// its own.
pub fn Ctx::follow_back(self : Ctx, f : (BackStep) -> Unit) -> Unit {
  self.back_next = Some(fn(kind, x, _w, t) {
    match kind {
      0 => f(Began(x, t))
      1 => f(Moved(x, t))
      2 => f(LetGo(x, t))
      3 => f(CalledOff)
      _ => f(Back)
    }
  })
  self.back_node_next = -1
}

///|
/// The top page of `nav` alone, in place, nothing sliding and nothing swiped back: a desktop's pane beside a sidebar,
/// whose pages are the same stack as a phone's (Ctx::nav draws it so on a narrow window). A page gone is forgotten
/// (its widgets' state, `on_leave` told) as Ctx::nav forgets it; one moving is put where it was going.
pub fn[P] Ctx::nav_flat(self : Ctx, nav : Nav[P], page : (P) -> Unit, bg? : Int64 = 0L) -> Int {
  if nav.mode != 0 || nav.leaving is Some(_) {
    nav.settle()
  }
  let top = nav.pages[nav.pages.length() - 1]
  // the page put on top since the last frame drawn, waited for while that one stays (Nav::shows_when)
  // (shown here as the last frame was drawn, or in this frame's build before: else no page shows to stay)
  let held = match nav.flat_shown {
    Some(shown) if shown.serial != top.serial &&
      nav.flat_asked == self.frame_no &&
      nav.flat_frame >= self.frame_no - 1 => {
      if nav.flat_for != top.serial {
        nav.flat_for = top.serial
        nav.flat_from = self.now
      }
      if self.now < nav.flat_from + nav.flat_most && !(nav.flat_ready)() {
        self.wake_at_time(nav.flat_from + nav.flat_most)
        Some(shown)
      } else {
        None
      }
    }
    _ => None
  }
  // what left the stack forgotten (and told), but the page that stays shown while the new one is waited for
  let kept : Array[NavPage[P]] = []
  for e in nav.gone {
    match held {
      Some(h) if h.serial == e.serial => kept.push(e)
      _ => {
        self.forget(e.serial)
        (nav.on_leave)(e.page)
      }
    }
  }
  nav.gone.clear()
  nav.gone.append(kept)
  let drawn = held.unwrap_or(top)
  nav.flat_frame = self.frame_no
  if held is None {
    nav.flat_shown = Some(top)
    nav.flat_for = -1
  }
  self.box(w=Fill(1.0), h=Fill(1.0), clip=true, bg~, fn() {
    let saved = self.owner
    let saved_stint = self.stint
    self.owner = drawn.serial
    self.stint = drawn.stint
    nav.built_by(drawn, fn() { self.scope(drawn.serial, fn() { page(drawn.page) }) })
    self.owner = saved
    self.stint = saved_stint
  })
}
