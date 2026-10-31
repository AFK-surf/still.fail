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
  // pushed over the one under it as a phone's are where the stack is drawn flat (Nav::push_over): Ctx::nav_flat slides
  // it in and back off
  mut over : Bool
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
  { serial: nav_serial.val, page, under, rise: false, over: false, stint: next_stint() }
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
  // where a finger has it (`p` while it follows one, mode 3), as a signal: what reads where it is (Nav::at) is drawn
  // again as the finger moves, nothing taken as an input (on_back, edge_move)
  finger : @signals.Signal[Double]
  // (its pages as they change, as a signal: what reads them (top, depth, pages, under, a nav built) built again for it,
  // wherever and whenever they changed: a choice told after a frame, a test's step)
  said : @signals.Signal[Int]
  mut p0 : Double
  mut p1 : Double
  // when the motion started (-1: at its first frame), how long (a Move's over how far it goes: move_ms), and how fast
  // it set out (its widths per ms: a finger's let go, a slide under way)
  mut t0 : Double
  mut dur : Double
  // how far it goes, in widths or heights of its room, where that room was not known as it was told (never laid out):
  // how long it takes worked out once it is, from when it was told (Ctx::nav); none, known
  mut dur_way : Double?
  mut v0 : Double
  // the room it was last built in (Ctx::nav): how far a width or a height of its way is
  mut room_w : Double
  mut room_h : Double
  // a finger's: where it started, how fast it went (px per ms), its track
  // (for how fast, scroll.mbt)
  mut x0 : Double
  mut vel : Double
  track : Tracker
  // the system's gesture (Android's): where its finger last moved to, when, and the progress and the page's place
  // then; the system's progress said with it after that is its own going back as it calls the gesture off
  mut moved_x : Double
  mut moved_at : Double
  mut moved_progress : Double
  mut moved_p : Double
  on_leave : (P) -> Unit
  // told of a page back took off (its own back: the edge's swipe, the system's, Ctx::back): the page, whether it was
  // pushed over the one under it, whether it rose from the foot, and the pages left
  went_back : (P, Bool, Bool, Array[P]) -> Unit
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
  // drawn flat, what shows in place of the one on top as its owner says it at its causes (Nav::flat_keep): the stay
  // (an entry's serial and its time on top) kept shown while the one on top is waited for; whether an owner says it
  // (Nav::flat_owned): then that alone decides, Nav::shows_when's frames none of it
  mut flat_kept : (Int, Int)?
  mut flat_owner : Bool
  // the page being built (Ctx::nav, Ctx::nav_flat), what Nav::under answers for
  mut built : NavPage[P]?
  // the pages at and under this index are not the stack's to slide or go back from (Ctx::nav's `floor`: a pane's stack
  // over a list kept elsewhere, Ctx::nav_flat's `stacks`); 0, all of them
  mut floor : Int
  // where the window's tree holds it (nav_view.mbt): its moment, what it is told as a page sets out; and what shows of
  // it (which pages, and how they move) as a signal, told as that changes
  mut hosted : NavHosted?
  shown : @signals.Signal[Int]
}

///|
/// A stack of pages, `root` at the bottom. `on_leave` is told of each page
/// that leaves it for good (popped, once it has slid away); a page
/// `from_left` says yes to slides in from the left and back out that way
/// (App.kt transition: Settings), swiped back too. `went_back` is told of each page its own back takes off (the edge's
/// swipe, the system's back, Ctx::back), as it goes: what a forward puts back.
pub fn[P] Nav::new(
  root : P,
  on_leave? : (P) -> Unit = fn(_) {  },
  went_back? : (P, Bool, Bool, Array[P]) -> Unit = fn(_, _, _, _) {  },
  from_left? : (P) -> Bool = fn(_) { false },
) -> Nav[P] {
  {
    pages: [nav_page(root, None)],
    mode: 0,
    leaving: None,
    gone: [],
    p: 0.0,
    finger: @signals.signal(0.0),
    said: @signals.signal(0),
    p0: 0.0,
    p1: 0.0,
    t0: -1.0,
    dur: 0.0,
    dur_way: None,
    v0: 0.0,
    room_w: 0.0,
    room_h: 0.0,
    x0: 0.0,
    vel: 0.0,
    track: Tracker::new(),
    moved_x: 0.0,
    moved_at: 0.0,
    moved_progress: -1.0,
    moved_p: 0.0,
    on_leave,
    went_back,
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
    flat_kept: None,
    flat_owner: false,
    built: None,
    floor: 0,
    hosted: None,
    shown: @signals.signal(0),
  }
}

///|
/// Its pages changed: what reads them told.
fn[P] Nav::told(self : Nav[P]) -> Unit {
  self.said.set(@signals.untracked(fn() { self.said.get() }) + 1)
}

///|
/// The page on top.
pub fn[P] Nav::top(self : Nav[P]) -> P {
  self.said.get() |> ignore
  self.pages[self.pages.length() - 1].page
}

///|
/// How many pages are in the stack.
pub fn[P] Nav::depth(self : Nav[P]) -> Int {
  self.said.get() |> ignore
  self.pages.length()
}

///|
/// The pages, bottom to top.
pub fn[P] Nav::pages(self : Nav[P]) -> Array[P] {
  self.said.get() |> ignore
  self.pages.map(fn(e) { e.page })
}

///|
/// The page under the one being built (Ctx::nav, Ctx::nav_flat: the top, the one under it as a page slides over it
/// or away, one leaving, one kept shown while the next is waited for), none under the root; outside them, the top's.
/// What a page asks of where it stands (whether it is the root, where its back goes), never the stack's depth or the
/// page under its top: those are the top's, and a root under a page coming in is still the root.
pub fn[P] Nav::under(self : Nav[P]) -> P? {
  self.said.get() |> ignore
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
  if self.mode == 3 {
    self.finger.get() |> ignore
  }
  self.p
}

///|
/// Off to `p1` (mode 1 coming in, 2 going, 4 back to rest from a finger) from where it is, as fast as `v` (its widths
/// per ms: the finger's as it let go), on a Move as long as its way is far (move_ms of it, in points: across its room,
/// or up it for a page that rose).
fn[P] Nav::go(
  self : Nav[P],
  mode : Int,
  p1 : Double,
  brings? : Bool = false,
  v? : Double = 0.0,
) -> Unit {
  wake()
  // (held by the window's tree: from where it is at its cause's moment, not where a frame last drew it)
  match self.hosted {
    Some(h) => self.p = self.p_at((h.now)())
    None => ()
  }
  self.mode = mode
  self.p0 = self.p
  self.p1 = p1
  let rising = match self.leaving {
    Some(e) => e.rise
    None => self.pages[self.pages.length() - 1].rise
  }
  // (held by the window's tree: how big its node is laid out as of the cause's moment)
  let (room_w, room_h) = match self.hosted {
    Some(h) => (h.room)()
    None => (self.room_w, self.room_h)
  }
  let room = if rising { room_h } else { room_w }
  // (a room not known (no frame has laid it out): no way is no length; how long, once it is known, Ctx::nav)
  self.dur_way = if room > 0.0 { None } else { Some((p1 - self.p).abs()) }
  self.dur = move_ms((p1 - self.p).abs() * room)
  self.v0 = v
  // told in a frame, it starts there, at its time (its end known as it is told); told between frames, at the next
  // frame that builds it (Ctx::nav)
  // (held by the window's tree: at its cause's moment, the tree's now)
  self.t0 = match self.hosted {
    Some(h) => (h.now)()
    None => if in_frame.val { g().clock } else { -1.0 }
  }
  self.wait_from = -1.0
  self.waited = false
  // (a page brought in: its start moved on by how late its first frame is to the screen)
  // (not where the window's tree holds it: its slide a function of the time from its cause alone)
  self.waits_late = brings && self.hosted is None
  self.late_at = -1.0
  // said once, as it sets out: frames until it is there
  self.asked = g().frame_no
  match self.hosted {
    Some(h) => (h.went)()
    None => g().moving(self.mover, self as &Moving, what="a stack's slide")
  }
  self.shown_told()
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
  self.rest_at(g().clock, g().frame_no)
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
  self.shown_told()
}

///|
/// A slide held (Nav::comes_when): its start, until it goes.
let nav_held : Double = -2.0

///|
/// Whether what the stack shows was pushed over the page under it (Nav::push_over): its top, at rest, coming in or
/// swiped; or one going back off it.
fn[P] Nav::stacked(self : Nav[P]) -> Bool {
  match self.leaving {
    Some(e) => e.over
    None => self.top_over()
  }
}

///|
/// The page those pushed over it lie over (Nav::push_over): the topmost put in place, as Ctx::nav's `floor`.
fn[P] Nav::over_floor(self : Nav[P]) -> Int {
  let mut k = self.pages.length() - 1
  while k > 0 && self.pages[k].over {
    k = k - 1
  }
  k
}

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
    self.wait_from = if self.t0 >= 0.0 { self.t0 } else { c.clock }
  }
  if c.clock >= self.wait_from + most || ready() {
    self.waited = true
    if self.t0 == nav_held {
      self.t0 = c.clock
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
/// The stay of the page on top: its entry (a page put on the stack is an entry of its own, the same page twice two) and
/// its time on top (come back to, another), read as it changes. What a wait for what it shows is the wait of.
pub fn[P] Nav::top_stay(self : Nav[P]) -> (Int, Int) {
  self.said.get() |> ignore
  let top = self.pages[self.pages.length() - 1]
  (top.serial, top.stint)
}

///|
/// Drawn flat (Ctx::nav_flat), what shows is said by its owner at its causes, not by the frames (`owned`; let go, as
/// Nav::shows_when says it): what it keeps shown (Nav::flat_keep) and when the one on top shows.
pub fn[P] Nav::flat_owned(self : Nav[P], owned : Bool) -> Unit {
  if self.flat_owner != owned || (!owned && self.flat_kept is Some(_)) {
    self.flat_owner = owned
    self.flat_kept = None
    self.told()
  }
}

///|
/// Drawn flat by an owner (Nav::flat_owned), the stay shown in place of the one on top (Nav::top_stay's of a page shown
/// before it), kept so till its owner says otherwise (`None`: the one on top), whatever frames are drawn: its entry kept
/// while it shows, though it has left the stack, then let go (forgotten and told, Nav's `on_leave`) as any other. A
/// stay no longer there (its entry let go, or on top again as another stay) keeps nothing.
pub fn[P] Nav::flat_keep(self : Nav[P], stay : (Int, Int)?) -> Unit {
  if self.flat_kept != stay {
    self.flat_kept = stay
    self.told()
  }
}

///|
/// The entry kept shown in place of the one on top (Nav::flat_keep), where it is still the stay kept: in the stack
/// under the top, or gone from it and not let go yet.
fn[P] Nav::flat_kept_entry(self : Nav[P]) -> NavPage[P]? {
  guard self.flat_kept is Some((serial, stint)) else { return None }
  let top = self.pages[self.pages.length() - 1]
  if top.serial == serial {
    return None
  }
  let find = fn(es : Array[NavPage[P]]) -> NavPage[P]? {
    es.iter().find_first(fn(e) { e.serial == serial && e.stint == stint })
  }
  match find(self.pages) {
    Some(e) => Some(e)
    None => find(self.gone)
  }
}

///|
/// Drawn flat (Ctx::nav_flat), the page drawn in place of the one on top this frame while that one is waited for
/// (Nav::shows_when): the page drawn there last, until the one on top has what it shows or its wait is over; else none.
/// The same whoever asks in a frame.
fn[P] Nav::flat_held(self : Nav[P], c : Ctx) -> NavPage[P]? {
  let top = self.pages[self.pages.length() - 1]
  // (shown here as the last frame was drawn, or in this frame's build before: else no page shows to stay)
  match self.flat_shown {
    Some(shown) if shown.serial != top.serial && self.flat_asked == c.frame_no && self.flat_frame >= c.frame_no - 1 => {
      if self.flat_for != top.serial {
        self.flat_for = top.serial
        self.flat_from = c.clock
      }
      if c.clock < self.flat_from + self.flat_most && !(self.flat_ready)() {
        c.wake_at_time(self.flat_from + self.flat_most)
        Some(shown)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Drawn flat (Ctx::nav_flat), whether the page on top shows this frame: not waited for while the one before stays
/// (Nav::shows_when). What moves to show it (a pane brought over on a tape) sets out once it does, as a page pushed
/// slides in once it has what it shows (Nav::comes_when); one pushed over a stack drawn flat holds its own slide.
/// Asked as the frame builds, after Nav::shows_when.
pub fn[P] Nav::top_shows(self : Nav[P]) -> Bool {
  if self.flat_owner {
    return self.stacked() || self.flat_kept_entry() is None
  }
  self.stacked() || self.flat_held(g()) is None
}

///|
/// Pushes `page`: it slides in over the one on top.
pub fn[P] Nav::push(self : Nav[P], page : P) -> Unit {
  self.settle()
  self.pages.push(nav_page(page, Some(self.top())))
  self.told()
  self.p = 1.0
  self.go(1, 0.0, brings=true)
}

///|
/// Pushes `page` over the one on top as Nav::push does, and so too where the stack is drawn flat (Ctx::nav_flat with
/// `stacks`: a pane on a tape, a phone's screen beside a list): there it slides in over it, and back takes it off
/// sliding, following the system's gesture, as a phone's stack has it; a page pushed (Nav::push) or put in place there
/// is shown in place.
pub fn[P] Nav::push_over(self : Nav[P], page : P) -> Unit {
  self.push(page)
  self.pages[self.pages.length() - 1].over = true
}

///|
/// Whether the page on top was pushed over the one under it (Nav::push_over).
pub fn[P] Nav::top_over(self : Nav[P]) -> Bool {
  self.pages[self.pages.length() - 1].over
}

///|
/// Pushes `page` rising from the bottom over the one on top, which stays where it is (App.kt: a new chat, 380 ms on
/// (.2, .8, .2, 1)); back, it sinks down the same way (swiped back, it goes down with the finger).
pub fn[P] Nav::rise(self : Nav[P], page : P) -> Unit {
  self.settle()
  let e = nav_page(page, Some(self.top()))
  e.rise = true
  self.pages.push(e)
  self.told()
  self.p = 1.0
  self.go(1, 0.0, brings=true)
}

///|
/// The top page becomes `page` in place, keeping what its widgets hold (a new chat becoming the chat it made, its
/// composer's words and focus kept); back from it, it goes sideways as a pushed page does.
pub fn[P] Nav::become(self : Nav[P], page : P) -> Unit {
  let e = self.pages[self.pages.length() - 1]
  e.page = page
  e.rise = false
  // (what reads which page is on top told: the same page, its widgets' state kept, now another)
  self.told()
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
  self.told()
  self.topped()
  self.go(2, 1.0, brings=true)
  true
}

///|
/// The top page replaced by `page`, in place (nothing slides).
pub fn[P] Nav::replace(self : Nav[P], page : P) -> Unit {
  self.settle()
  // (told once, as the new one is on top: never with no page)
  let was = self.pages.pop()
  match was {
    Some(e) => self.gone.push(e)
    None => ()
  }
  let e = nav_page(page, self.pages.last().map(fn(e) { e.page }))
  // (in its place: over the one under it as it was, Nav::push_over)
  match was {
    Some(w) => e.over = w.over
    None => ()
  }
  self.pages.push(e)
  self.told()
  wake()
}

///|
/// A stack changed: changed as the frame is built, built again from it in the frame (no frame shows the page it left
/// as it was), all of it anew; between frames, the next frame (Ctx::read_changed), what builds a stack told
/// (stacks_said: a part kept as its nodes that holds one, built again).
fn wake() -> Unit {
  if !building.val {
    stacks_said.set(@signals.untracked(fn() { stacks_said.get() }) + 1)
  }
  g().read_changed("a stack changed")
}

///|
/// How many times a stack changed between frames (wake): what builds one reads it (Ctx::nav, Ctx::nav_flat).
// kept across runs: a count, read as it changes
let stacks_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// Back as a back gesture asks: kind 0 started at x (in a view `w` wide), 1
/// moved to x, 2 let go there (back if past a third or flung), 3 called
/// off, 4 back (the system decided: from where a gesture had it, or a back
/// with none); `t` the time; `progress` the system's (-1 none: mbui's own
/// edge). Never past its floor (Ctx::nav's `floor`).
fn[P] Nav::gesture(
  self : Nav[P],
  kind : Int,
  x : Double,
  w : Double,
  t : Double,
  progress? : Double = -1.0,
) -> Unit {
  let w = dmax(w, 1.0)
  match kind {
    0 =>
      if self.mode == 0 && self.pages.length() > self.floor + 1 {
        self.mode = 3
        self.p = 0.0
        self.finger.set(0.0)
        self.shown_told()
        self.x0 = x
        self.vel = 0.0
        self.track.reset()
        self.track.add(t, x)
        self.moved_x = x
        self.moved_at = t
        self.moved_progress = progress
        self.moved_p = 0.0
      }
    1 =>
      if self.mode == 3 {
        if progress >= 0.0 && x == self.moved_x {
          // the system's step with its finger where it was, longer than a moving finger's steps are apart: lifted,
          // the system going back on its own before it says it is called off (Android's BackProgressAnimator takes
          // its progress to 0 first, on its spring, the finger's place kept); the page goes back with that progress,
          // not standing where the finger left it. (A finger held still: its progress comes to where the finger is,
          // by no more than it lagged.)
          if t - self.moved_at > tracker_gap_ms && self.moved_progress > 0.0 && progress < self.moved_progress {
            self.p = self.moved_p * progress / self.moved_progress
            self.finger.set(self.p)
            self.track.add(t, self.x0 + self.p * w)
          }
        } else {
          self.p = dclamp((x - self.x0) / w, 0.0, 1.0)
          self.finger.set(self.p)
          self.track.add(t, x)
          self.moved_x = x
          self.moved_at = t
          self.moved_progress = progress
          self.moved_p = self.p
        }
      }
    2 =>
      if self.mode == 3 {
        let dx = self.p * w
        // where it was let go counts too: held still first, it was not flung
        self.track.add(t, x)
        self.vel = self.track.velocity()
        let flung = dx > 40.0 && self.vel > 0.6
        if self.p > 1.0 / 3.0 || flung {
          self.let_go(dmax(self.vel, 0.0) / w)
        } else {
          // back to rest, as fast as the finger let it go (its widths per ms)
          self.go(4, 0.0, v=self.vel / w)
        }
      }
    3 => if self.mode == 3 { self.go(4, 0.0) }
    _ =>
      if self.mode == 3 {
        self.let_go(0.0)
      } else if self.pages.length() > self.floor + 1 {
        let e = self.pages[self.pages.length() - 1]
        if self.pop() {
          (self.went_back)(e.page, e.over, e.rise, self.pages())
        }
      }
  }
}

///|
/// Gone back from where a finger left the page: on from there, as fast as it let it go (`v`, its widths per ms).
fn[P] Nav::let_go(self : Nav[P], v : Double) -> Unit {
  self.leaving = self.pages.pop()
  self.told()
  match self.leaving {
    Some(e) => (self.went_back)(e.page, e.over, e.rise, self.pages())
    None => ()
  }
  self.topped()
  self.go(2, 1.0, v~)
}

///|
/// The stack drawn, filling what it is given: the top page (and, while one
/// moves, the page beside it), each built by `page` on a ground of `bg`.
/// Back (Ctx::back, the left edge's swipe within `edge` of its side, the
/// system's) comes here while it has a page to go back to, unless the top
/// page takes it itself (what is open in it closed first). `floor`: the
/// pages at and under that index are not this stack's to go back from (a
/// pane's stack over a list kept beside it: Ctx::nav_flat's `stacks`):
/// back comes here while it has a page over the floor. `takes_back`: false,
/// back is not its now (the pane it is drawn in not the one in use).
pub fn[P] Ctx::nav(
  self : Ctx,
  nav : Nav[P],
  page : (P) -> Unit,
  bg? : Int64 = 0L,
  edge? : Double = 20.0,
  floor? : Int = 0,
  takes_back? : Bool = true,
) -> Int {
  // (its pages read: built again as they change)
  nav.said.get() |> ignore
  stacks_said.get() |> ignore
  nav.floor = floor
  nav.room_w = self.width
  nav.room_h = self.height
  // (told before its room was known: how long its way takes, worked out now that it is, once; when it set out kept)
  match nav.dur_way {
    Some(way) => {
      let rising = match nav.leaving {
        Some(e) => e.rise
        None => nav.pages[nav.pages.length() - 1].rise
      }
      let room = if rising { nav.room_h } else { nav.room_w }
      if room > 0.0 {
        nav.dur = move_ms(way * room)
        nav.dur_way = None
      }
    }
    None => ()
  }
  if nav.mode == 3 {
    self.page_in_hand = true
  }
  for e in nav.gone {
    self.forget(e.serial)
    (nav.on_leave)(e.page)
  }
  nav.gone.clear()
  if nav.t0 == nav_held {
    // held for what the page pushed shows (Nav::comes_when): where it was, not moving yet; at rest by the latest its
    // slide could end (nav_rest)
    let r = nav.rest_at(self.clock, self.frame_no)
    if r > self.nav_rest {
      self.nav_rest = r
    }
  } else if nav.mode == 1 || nav.mode == 2 || nav.mode == 4 {
    if nav.t0 < 0.0 {
      // it starts now: said to move again (not built in the frame it was to start in, it had been let be)
      nav.t0 = self.clock
      self.moving(nav.mover, nav as &Moving, what="a stack's slide")
    }
    // where its pages are is worked out as they are laid out and painted (Nav::at, Ctx::nav_layer): its frames are
    // painted alone (frame_watch.mbt). Its end is a moment, the frame at it built again (over at the end it says,
    // t0 + dur, to the bit: (t0 + dur - t0) / dur can fall short of 1 by a rounding)
    nav.late_check(self)
    if nav.dur <= 0.0 || self.clock >= nav.t0 + nav.dur {
      nav.settle()
      // the page that slid away forgotten in the frame its slide ends (`on_leave` told), not the next
      for e in nav.gone {
        self.forget(e.serial)
        (nav.on_leave)(e.page)
      }
      nav.gone.clear()
    } else {
      self.wake_at_time(nav.t0 + nav.dur)
    }
    let r = nav.rest_at(self.clock, self.frame_no)
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
  // a page that rose goes up and down over the one under it, which stays
  let rising = top.rise
  // the side the top page is off to (one from the left goes back left, the page under it coming from the right)
  let way = if (nav.from_left)(top.page) { -1.0 } else { 1.0 }
  // back as it was before the stack, for when neither its top page nor it takes it
  let before = self.back_next
  let before_node = self.back_node_next
  let before_edge = self.back_edge_next
  let before_island = self.back_island_next
  let before_chain = self.back_chain_next
  let leaving = nav.leaving is Some(_)
  let i = self.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
    // (pushed: the page it covers takes nothing from the moment it is pushed)
    match under {
      Some(e) => self.nav_layer(nav, e, true, rising, way, bg, page, inert=nav.mode == 1)
      None => ()
    }
    // what the top page takes back for (a sheet, a menu, a step of its own, a stack in it) goes back before the stack
    // does, as Android's BackHandler in a page is asked before the pages' own; the page under it, one leaving, take none
    self.back_next = None
    self.back_node_next = -1
    self.back_island_next = None
    self.back_chain_next = Unsaid
    // (going back: the page leaving takes nothing)
    self.nav_layer(nav, top, false, rising, way, bg, page, inert=leaving)
  })
  let stack_takes = takes_back && (n > floor + 1 || nav.mode >= 3 || (floor == 0 && nav.mode != 0))
  let stack : BackEntry = {
    f: fn(kind, x, w, t, progress) { nav.gesture(kind, x, w, t, progress~) },
    node: i,
    edge,
    island: self.island_said(),
    layer: 0,
  }
  if self.back_next is Some(_) && !leaving && takes_back {
    // (what the top page said first, the stack under it, what was before it under that: what takes back as each over
    // it took it, Ctx::layer_back_taken)
    let under = if stack_takes { Said(stack, before_chain) } else { before_chain }
    self.back_chain_next = back_list_over(self.back_chain_next, under)
  } else if stack_takes {
    self.back_next = Some(stack.f)
    self.back_node_next = stack.node
    self.back_edge_next = stack.edge
    self.back_island_next = stack.island
    self.back_chain_next = Said(stack, before_chain)
  } else {
    self.back_next = before
    self.back_node_next = before_node
    self.back_edge_next = before_edge
    self.back_island_next = before_island
    self.back_chain_next = before_chain
  }
  i
}

///|
/// Builds `body`, back taken in it (Ctx::on_back, Ctx::take_back, an overlay, a stack: Ctx::nav) kept over what took
/// it before: true when it took it; when not, back is as it was. For what goes back only when nothing within it does
/// (a stack drawn flat, whose pop is taken after it: Ctx::nav_flat).
pub fn Ctx::took_back(self : Ctx, body : () -> Unit) -> Bool {
  let before_chain = self.back_chain_next
  let before = self.back_next
  let before_node = self.back_node_next
  let before_edge = self.back_edge_next
  let before_island = self.back_island_next
  self.back_next = None
  self.back_node_next = -1
  self.back_island_next = None
  self.back_chain_next = Unsaid
  body()
  if self.back_next is Some(_) {
    // (what was before it under what it said: what takes back as each over it took it)
    self.back_chain_next = back_list_over(self.back_chain_next, before_chain)
    true
  } else {
    self.back_next = before
    self.back_node_next = before_node
    self.back_edge_next = before_edge
    self.back_island_next = before_island
    self.back_chain_next = before_chain
    false
  }
}

///|
/// Page `e` of the stack, the top or the one `under` it, built over its whole room on a ground of `bg`, placed where
/// its slide has it at the frame's time (Nav::at: the page beside the top edge to edge with it, one that rose going up
/// and down over the one under it, which stays): laid out there, and placed there again as each frame is painted,
/// nothing built (Ctx::moved_by).
fn[P] Ctx::nav_layer(
  self : Ctx,
  nav : Nav[P],
  e : NavPage[P],
  under : Bool,
  rising : Bool,
  way : Double,
  bg : Int64,
  page : (P) -> Unit,
  inert? : Bool = false,
) -> Unit {
  let i = self.box(w=Fill(1.0), h=Fill(1.0), bg~, fn() {
    let saved = self.owner
    let saved_stint = self.stint
    self.owner = e.serial
    self.stint = e.stint
    nav.built_by(e, fn() { self.scope(e.serial, fn() { page(e.page) }) })
    self.owner = saved
    self.stint = saved_stint
  })
  self.nodes[i].layer = true
  if nav.mode != 0 {
    let height = self.height
    self.moved_by(i, fn(w, _) {
      let p = nav.at(self)
      if rising {
        (0.0, if under { 0.0 } else { p * height })
      } else {
        (way * (if under { p - 1.0 } else { p }) * w, 0.0)
      }
    })
  }
  if inert {
    self.draw_only(i)
  }
}

///|
/// Where the top page is, in its widths off to its side (0 in place: Nav's `p`), as its slide has it at the frame's
/// time, from where it set out, by when and how (the clock read followed while it slides: what reads it, as it is
/// painted, painted again each frame till its end); followed by a finger, where the finger has it.
fn[P] Nav::at(self : Nav[P], c : Ctx) -> Double {
  if (self.mode == 1 || self.mode == 2 || self.mode == 4) && self.t0 >= 0.0 {
    self.late_check(c)
    let t = if self.dur <= 0.0 || c.clock >= self.t0 + self.dur {
      1.0
    } else {
      dmax((c.now() - self.t0) / self.dur, 0.0)
    }
    let (x, _) = move_path(self.p0 - self.p1, self.v0, dmin(t, 1.0) * self.dur, self.dur)
    self.p = self.p1 + x
  }
  // (following a finger: where it has it, read so)
  if self.mode == 3 {
    self.finger.get() |> ignore
  }
  self.p
}

///|
/// A page brought in: its first frame drawn from where it starts; the next (built or painted alone) told how late that
/// one was to the screen, its slide's start moved on by that (nav_late_most at most), from its cause's frame, once.
fn[P] Nav::late_check(self : Nav[P], c : Ctx) -> Unit {
  if !self.waits_late {
    return
  }
  if self.late_at < 0.0 {
    self.late_at = c.clock
  } else if c.clock > self.late_at {
    self.waits_late = false
    let late = dmin(h_frame_late(), nav_late_most)
    if late > 0.0 {
      self.t0 = self.t0 + late
      c.moving(self.mover, self as &Moving, what="a stack's slide")
    }
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
          self.focus_moved(0)
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
  // (what takes back now, where it may take input: a node of the window's tree's, else the old views', view_host.mbt;
  // found and done as one event of the window's tree at this moment, what was due by then done first)
  let went = Ref(false)
  let go = fn() {
    match self.back_taker() {
      Some(h) if old_owner_open(h.owner) => {
        (h.f)(4, 0.0, 1.0, view_moment(), -1.0)
        self.read_changed("gone back")
        went.val = true
      }
      _ => ()
    }
  }
  match view_app.val {
    Some(tree) => tree.event(view_moment(), go)
    None => go()
  }
  went.val
}

///|
/// Back taken by what is drawn over the stack (a viewer, a sheet), on the frames it calls this, after the stack is
/// drawn: the system's back, a back button (Ctx::back) call `f` once let go; no edge swipe of its own.
pub fn Ctx::take_back(self : Ctx, f : () -> Unit) -> Unit {
  self.back_next = Some(fn(kind, _x, _w, _t, _) {
    if kind == 2 || kind == 4 {
      f()
    }
  })
  self.back_node_next = -1
  self.back_island_next = self.island_said()
  self.back_says()
}

///|
/// Back taken by what is drawn over the stack, on the frames it calls this, after the stack is drawn, followed as it
/// goes (Ctx::take_back's, step by step): the system's back gesture (Android's predictive back, from either edge: x
/// from the edge it came from, as a stack's page follows it) and a back with no gesture come to `f` as their steps;
/// for what moves back with the finger as a stack's page does without being one (a tape's panels). No edge swipe of
/// its own.
pub fn Ctx::follow_back(self : Ctx, f : (BackStep) -> Unit) -> Unit {
  self.back_next = Some(fn(kind, x, _w, t, _) {
    match kind {
      0 => f(Began(x, t))
      1 => f(Moved(x, t))
      2 => f(LetGo(x, t))
      3 => f(CalledOff)
      _ => f(Back)
    }
  })
  self.back_node_next = -1
  self.back_island_next = self.island_said()
  self.back_says()
}

///|
/// The top page of `nav` alone, in place, nothing sliding and nothing swiped back: a desktop's pane beside a sidebar,
/// whose pages are the same stack as a phone's (Ctx::nav draws it so on a narrow window). A page gone is forgotten
/// (its widgets' state, `on_leave` told) as Ctx::nav forgets it; one moving is put where it was going.
/// `stacks`: what is pushed over (Nav::push_over) a stack of the pane's own, as a phone's (a pane on a tape, a phone's
/// screen beside a list): it slides in over the page under it, and back takes it off sliding (following the system's
/// gesture) as Ctx::nav has them, down to the page put there in place (its `floor`), which is shown in place as ever;
/// `takes_back` false, back not its now (Ctx::nav's: the pane not the one in use).
pub fn[P] Ctx::nav_flat(
  self : Ctx,
  nav : Nav[P],
  page : (P) -> Unit,
  bg? : Int64 = 0L,
  stacks? : Bool = false,
  takes_back? : Bool = true,
) -> Int {
  // (its pages read: built again as they change)
  nav.said.get() |> ignore
  stacks_said.get() |> ignore
  if stacks && nav.stacked() {
    // (one pushed over it slides in once it has what it shows, waiting as long as one put in place waits:
    // Nav::shows_when's, asked this frame)
    if nav.flat_asked == self.frame_no {
      nav.comes_when(nav.flat_ready, nav.flat_most)
    }
    return self.nav(nav, page, bg~, floor=nav.over_floor(), takes_back~)
  }
  if nav.mode != 0 || nav.leaving is Some(_) {
    nav.settle()
  }
  let top = nav.pages[nav.pages.length() - 1]
  // the page put on top since, waited for while the one before stays: as its owner said it at its causes
  // (Nav::flat_keep), else as the frames found it (Nav::shows_when)
  let held = if nav.flat_owner { nav.flat_kept_entry() } else { nav.flat_held(self) }
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
