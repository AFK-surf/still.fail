// Time in a test is said by the test (docs/determinism.md): an input is handed in and the frames it causes drawn, at
// its own moment; time goes on by `run_for` (a declared duration: a motion's, a timer's), straight to its end, a frame
// there (and at each wake the view asked for on the way); `frame()` draws the display's next frame (1000/60 ms apart
// by default). How many frames come before a moment changes nothing of what is so at it: MBUI_TEST_FPS draws the
// display's frames on run_for's way too, and the tests come out the same (scripts/fps_check.sh). At a test's end
// nothing may go on asking for frames (`assert_idle`). Nothing waits for motion to end: motion only draws what the
// state already is, so what a test asserts of the state holds as the input is taken, and a picture is taken at a
// moment the test names.

///|
/// The frames owed now, each at the display's next frame, as a host draws them: after an input, the frame that takes
/// it, the one after (what read it late: a list's rows), a layout read back once more; after a change the test made (a
/// value it set), the frame that shows it; a motion said, the frame it starts at. Not a motion going on (time goes on
/// by run_for). Three at most: a layout read back still moving after them never converges, and the test fails, saying
/// whose.
pub fn Tester::draw(self : Tester) -> Unit {
  // (what the test changed, as an event from outside is: a part kept is built anew, kept_part.mbt)
  outside_came()
  self.drawn_now()
}

///|
/// The frames the app has asked for drawn, each at the display's next frame, as a host draws them (nothing said
/// changed: none of Tester::draw's telling): after an input handed on, the frame that takes it and any it asks for
/// after.
pub fn Tester::frames_owed(self : Tester) -> Unit {
  self.draw_owed(0)
}

///|
/// The frames owed now (Tester::draw's) after what is the hand's on mbui's own (a pointer moved, a wheel turned): not
/// a change of the test's.
fn Tester::drawn_now(self : Tester) -> Unit {
  self.frame_now()
  self.draw_owed(1)
}

///|
/// A frame at this moment (a host's run's frames: at its next, Tester::set_frame_times).
fn Tester::frame_now(self : Tester) -> Unit {
  if self.host_frames {
    self.frame(ms=0.0)
  } else {
    self.frame_at(self.fake.time)
  }
}

///|
/// The frames owed drawn (Tester::draw's, after `n` drawn already), each at the display's next frame: what a frame left
/// owed is drawn as the Tester stands, at its making (Tester::new), not left to the next input.
fn Tester::draw_owed(self : Tester, n : Int) -> Unit {
  let mut n = n
  while self.owed_now() {
    if n == draw_frames_most {
      let c = g()
      if c.read_back_moved {
        let s = "Tester::draw: what the view reads (\{c.read_back_key}) still changes after \{n} frames: it does not converge"
        println(s)
        abort(s)
      }
      return
    }
    self.frame_now()
    n = n + 1
  }
}

///|
/// The most frames drawn owed one after another (Tester::draw).
let draw_frames_most = 3

///|
/// Whether a frame is owed at this moment (Tester::draw): an input's frame after, a layout read back that moved, a
/// motion said that starts at the next frame, the host's events, a frame asked for. A motion going on is not.
fn Tester::owed_now(self : Tester) -> Bool {
  let c = g()
  c.took_input || c.read_back_moved || c.motion_unstarted || self.fake.wants || c.frame_by is Some(_)
}

///|
/// What is said to move and is not at rest after the last frame, a line each: what it is (a spring, an Anim and its
/// key, a list's ease, a stack's slide), who told it, and when it is at rest.
pub fn Tester::moving(self : Tester) -> Array[String] {
  ignore(self)
  g().moving_now()
}

///|
/// When what moves named `name` is at rest (the frames' clock): the latest of those whose line (Tester::moving)
/// says `name` (`c.spring "seg"`, `Anim "fade"`, a key); +inf when one has not started; -1 when none moves. What a
/// test runs to when the motion has no rest of its own to ask.
pub fn Tester::rest_of(self : Tester, name : String) -> Double {
  ignore(self)
  rest_of(name)
}

///|
/// When what moves named `name` is at rest (Tester::rest_of): for a component's own rest query (@kit.toast_rest).
pub fn rest_of(name : String) -> Double {
  let c = g()
  let mut last = -1.0
  for e in c.movers {
    if e.what.contains(name) {
      let r = e.m.rest_at(c.clock, c.frame_no)
      if r > c.clock && r > last {
        last = r
      }
    }
  }
  last
}

///|
/// `ms` on the frames' clock, straight to it: a frame at each moment something is due (a wake the view asked for, the
/// end of what is said to move), and the last at `ms` itself, what is so at `ms` drawn there; with frames between (MBUI_TEST_FPS: a run at a frame rate, which comes
/// out the same) a frame at each of the display's frames too. None after it: what that frame leaves owed (an input's
/// frame after, a host's event) is drawn by what the test does next.
pub fn Tester::run_for(self : Tester, ms : Double) -> Unit {
  // (what the test changed before it shows at its first frame: a step of the test's, frame_watch.mbt)
  test_stepped()
  // (on the display's frame where it falls on one, to the bit: the same moment however it was summed)
  let end = self.on_grid(self.fake.time + ms)
  // (a host's run's frames: each of them on the way, the last the first at or past the end, as the host drew)
  if self.host_frames {
    while self.fake.time < end - 1.0e-9 {
      self.clock_frame()
    }
    return
  }
  // what the last frame left owed (a tell answered at once, a host's answer posted, an input's frame after) drawn at
  // its moment first, as a host draws it at its next frame: not at the end of the run
  if end > self.fake.time + 1.0e-9 {
    self.draw_owed(1)
  }
  while self.fake.time < end - 1.0e-9 {
    // the next of: what is due (a wake the view asked for, a motion's end), the end, and with frames between
    // (MBUI_TEST_FPS) the display's next frame; each drawn at its own moment: what happens at a time happens at it,
    // at any frame rate or none, and the last frame is the end's
    let mut next = if self.between { dmin(self.tick_after(self.fake.time), end) } else { end }
    let due = self.on_grid(self.next_due())
    if due > self.fake.time + 1.0e-9 && due < next {
      next = due
    }
    self.frame_at(next)
    // what that frame left owed (a host's answer posted, an input's frame after, a layout read back) drawn at its
    // moment, as Tester::draw draws it: what it sets off goes on from there, not from the next due moment
    if next < end - 1.0e-9 {
      self.draw_owed(1)
    }
  }
}

///|
/// `t`, or the display's frame a hair after it (within a millionth of a ms): a moment summed one way or another, the
/// same.
fn Tester::on_grid(self : Tester, t : Double) -> Double {
  if t == @double.infinity {
    return t
  }
  // (never before it: a moment a hair past the display's frame, a motion's end summed as t0 + dur, is its own; drawn
  // at the frame just before it, the motion would be a rounding short of its end)
  let tick = self.tick_at(t)
  if tick >= t && tick - t < 1.0e-6 {
    tick
  } else {
    t
  }
}

///|
/// The earliest moment after now that something is due at: a wake the view asked for (Ctx::wake_in, wake_at), or the
/// declared end of what is said to move (its rest: an event at its moment, as a host's frames show it, where what
/// waits for it goes on); +inf when none. Where what moves is meanwhile needs no frame: it is a function of the time.
fn Tester::next_due(self : Tester) -> Double {
  let c = g()
  let now = self.fake.time
  let mut due = if c.wake_at > now { c.wake_at } else { @double.infinity }
  for e in c.movers {
    let r = e.m.rest_at(c.clock, c.frame_no)
    if r > now && r < due {
      due = r
    }
  }
  // (and what the outside the test stands for says next: a kept message, at its moment)
  match outside_due.val {
    Some(f) => {
      let r = f()
      if r > now && r < due {
        due = r
      }
    }
    None => ()
  }
  due
}

///|
/// Nothing asks for a frame now: no frame asked for, no motion said that is not at rest, no wake owed, no fiber or
/// ticket of the runtime running. Else the test fails, saying who. What never ends while shown (a cycle: a spinner, a
/// breath) does not break it: it is said (Tester::cycles).
pub fn Tester::assert_idle(self : Tester) -> Unit {
  // messages posted that no frame took: what came from outside, not looked at (messages.mbt)
  let posted = posted_left()
  // (the frame the last input or motion left owed is drawn first: idle is what comes after)
  self.draw()
  let c = g()
  let why = []
  if posted != "" {
    why.push(posted)
  }
  if c.frame_by is Some(_) {
    why.push("a frame asked for" + by_of(c.frame_by))
  } else if c.motion_left {
    why.push("a motion said is not at rest: " + c.moving_now().join("; "))
  } else if c.wants_frame && !c.cycling {
    why.push(
      "a frame asked for" +
      (if c.took_input {
        " (an input's frame after)"
      } else if c.read_back_moved {
        " (what the view reads still changed: \{c.read_back_key})"
      } else if watch_said.val != "" {
        " (\{watch_said.val})"
      } else {
        ""
      }),
    )
  } else if layout_left() {
    why.push(
      "a frame asked for to lay out (" +
      (if layout_said.val != "" { layout_said.val } else { "what a part or a list's row read changed: \{nodes_run.told_by}" }) +
      ")",
    )
  } else if self.fake.wants && !c.wants_frame {
    why.push("a frame asked for between frames")
  }
  if paint_left() {
    why.push("a frame asked for to paint (\{paint_said.val})")
  }
  if c.wake_waited >= 0.0 {
    why.push("a wake in \{(c.wake_waited - c.clock).ceil().to_int()} ms" + by_of(c.wake_by))
  }
  let rt = fx.val.unsettled()
  if rt != "" {
    why.push(rt)
  }
  if why.length() > 0 {
    let s = "Tester::assert_idle: not idle: " + why.join("; ")
    println(s)
    abort(s)
  }
  let cycles = self.cycles()
  if cycles.length() > 0 {
    println("Tester::assert_idle: idle, but for what never ends while shown: " + cycles.join("; "))
  }
  let periodic = self.periodic()
  if periodic.length() > 0 {
    println("Tester::assert_idle: idle, but for what comes again while shown: " + periodic.join("; "))
  }
}

///|
/// Whether the frame being ended leaves nothing that ends to come, asked as it ends (on_frame, before what moves on
/// asks for the next frame): no frame asked for, no motion said that is not at rest, no wake owed, nothing of the
/// runtime running (a fiber ready or waiting for a frame, what is awaited from outside: the host's work, the core's
/// answers as the app tracks them, a timer said once). What never ends while shown (Ctx::cycle) or comes again
/// (Ctx::every) does not count: what it shows at that moment is its clock's. What a host has had posted and no frame
/// has taken yet (post.h) is the host's to count. Said of a run (Tester::at_rest, asserted), never waited on: a wait
/// until it is would be settling by another name.
fn Ctx::at_rest(self : Ctx) -> Bool {
  self.frame_by is None &&
  !self.motion_left &&
  !self.wants_frame &&
  !paint_left() &&
  self.wake_waited < 0.0 &&
  fx.val.unsettled() == ""
}

///|
/// What keeps the frame being ended from its rest (Ctx::at_rest), in words, for an assertion that it is at rest that
/// fails: "" when nothing does.
fn Ctx::rest_why(self : Ctx) -> String {
  let why = []
  if self.frame_by is Some(_) {
    why.push("a frame asked for" + by_of(self.frame_by))
  } else if self.wants_frame {
    why.push(
      "a frame asked for" +
      (if self.took_input {
        " (an input's frame after)"
      } else if self.read_back_moved {
        " (what the view reads still changed: \{self.read_back_key})"
      } else {
        ""
      }),
    )
  }
  if paint_left() {
    why.push("a frame asked for to paint (\{paint_said.val})")
  }
  if self.motion_left {
    why.push("a motion said is not at rest: " + self.moving_now().join("; "))
  }
  if self.wake_waited >= 0.0 {
    why.push("a wake in \{(self.wake_waited - self.clock).ceil().to_int()} ms" + by_of(self.wake_by))
  }
  let rt = fx.val.unsettled()
  if rt != "" {
    why.push(rt)
  }
  why.join("; ")
}

///|
/// Whether the app is at its rest after the last frame (Ctx::at_rest, as that frame ended), with no frame asked for
/// between frames and no message posted that no frame took. For assertions only (`assert_true(t.at_rest())`, a test's
/// end): no loop, `until` or run goes on until it is (detlint's at-rest-wait).
pub fn Tester::at_rest(self : Tester) -> Bool {
  g().frame_rest && !self.fake.wants && posted_left() == ""
}

///|
/// What keeps the app from its rest after the last frame, in words (Tester::at_rest): "" when nothing does.
pub fn Tester::rest_why(self : Tester) -> String {
  let why = []
  let c = g()
  if !c.frame_rest {
    why.push(c.rest_why())
  }
  if self.fake.wants {
    why.push("a frame asked for between frames")
  }
  let posted = posted_left()
  if posted != "" {
    why.push(posted)
  }
  why.filter(fn(w) { w != "" }).join("; ")
}

///|
/// What comes again every so often while shown in the last frame (Ctx::every): its period and who reads it, a line each.
pub fn Tester::periodic(self : Tester) -> Array[String] {
  ignore(self)
  g().periodic.map(fn(p) { "every \{p.0.to_int()} ms by \{p.1}" })
}

///|
/// What never ends while shown in the last frame (Ctx::cycle): its period and who reads it, a line each.
pub fn Tester::cycles(self : Tester) -> Array[String] {
  ignore(self)
  g().cycles.map(fn(c) { "\{c.0.to_int()} ms by \{c.1}" })
}

///|
/// The focused field emptied, as a scripted run's `clear` empties it: all of it picked, then taken out.
pub fn Tester::clear(self : Tester) -> Unit {
  on_key(key_select_all, 0)
  on_key(key_backspace, 0)
  self.draw()
}

///|
fn by_of(l : SourceLoc?) -> String {
  match l {
    Some(l) => " (by \{l})"
    None => ""
  }
}

///|
/// Where the words (or `=WORDS` exactly, `icon:NAME` an @sf icon, `img:NAME` an image by the end of its source) are
/// on screen, as a scripted run's steps find them (drive.mbt): the middle of each, laid out inside the window.
pub fn Tester::locate(self : Tester, what : String) -> Array[(Double, Double)] {
  ignore(self)
  on_screen(g(), what)
}

///|
/// Where `what` is on screen that a finger reaches (not under what lies over it: a sheet, a scrim), as a scripted run's
/// tap finds it (drive.mbt reachable): the same press in a test as in the run.
pub fn Tester::reachable(self : Tester, what : String) -> Array[(Double, Double)] {
  ignore(self)
  reachable(g(), what)
}

///|
/// The focused field's words ("" when none is focused).
pub fn Tester::field_words(self : Tester) -> String {
  ignore(self)
  field_words(g())
}

///|
/// `words` pasted where the focus is, as a scripted run pastes (drive.mbt `paste`): put on the clipboard, then given
/// as the system gives a paste; the frames it causes drawn.
pub fn Tester::paste(self : Tester, words : String) -> Unit {
  h_clipboard_set(words)
  on_text(text_paste, words, 0, 0)
  self.draw()
}

///|
/// The key named `name` pressed, as a scripted run names keys (drive.mbt `key`): `esc`, `enter`, `shift+enter`,
/// `cmd+k` (Ctrl off macOS)…; false for a name it does not know. The frames it causes drawn.
pub fn Tester::key_named(self : Tester, name : String) -> Bool {
  match key_named(name) {
    Some((code, mods)) => {
      on_key(code, mods)
      self.draw()
      true
    }
    None => false
  }
}

///|
/// The window's size (points).
pub fn Tester::size(self : Tester) -> (Double, Double) {
  ignore(self)
  let c = g()
  (c.width, c.height)
}

///|
/// The notifications the app shows now, oldest first (@ui.notice_show).
pub fn Tester::notices(self : Tester) -> Array[Notice] {
  self.fake.notices.copy()
}

///|
/// The notification whose title or words hold `text` tapped, as the system taps one: what it opens is given to the
/// app (@ui.notice_opened), the frames that causes drawn. False when none holds it.
pub fn Tester::tap_notice(self : Tester, text : String) -> Bool {
  match self.fake.notices.search_by(fn(n) { n.title.contains(text) || n.body.contains(text) }) {
    Some(k) => {
      self.fake.notice_opened = self.fake.notices[k].opens
      // (the system takes it away as it is tapped)
      self.fake.notices.remove(k) |> ignore
      self.draw()
      true
    }
    None => false
  }
}

///|
/// The next timer the app is waiting on (a wake said once: Ctx::wake_in, @kit.after; or its runtime's: a fiber's
/// sleep, Runtime::after, a core's timer as its client says it), when it comes and who said it; None while none is.
/// Not what comes again by itself (Ctx::every: Tester::periodic; a runtime's `later`). What a run's end goes on to, as
/// it goes on to a motion's declared end (Tester::rest_of).
pub fn Tester::next_wake(self : Tester) -> (Double, String)? {
  ignore(self)
  let c = g()
  let ui = if c.wake_waited < 0.0 { None } else { Some((c.wake_waited, by_of(c.wake_by))) }
  let rt = match fx.val.next_due() {
    Some((at, who)) => Some((at.to_double(), " (the runtime's: " + (if who == "" { "a timer" } else { who }) + ")"))
    None => None
  }
  match (ui, rt) {
    (Some(a), Some(b)) => if b.0 < a.0 { Some(b) } else { Some(a) }
    (Some(a), None) => Some(a)
    (None, b) => b
  }
}
