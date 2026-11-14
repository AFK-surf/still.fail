// Time in a test is said by the test: an input is handed in and the frames it causes drawn, at
// its own moment; time goes on by `run_for` (a declared duration: a motion's, a timer's), straight to its end, a frame
// there (and at each wake the view asked for on the way); `frame()` draws the display's next frame (1000/60 ms apart
// by default). How many frames come before a moment changes nothing of what is so at it: MBUI_TEST_FPS draws frames
// at its rate on run_for's way too (only there: the moments the test walks are its own), and the tests come out the
// same (scripts/fps_check.sh). At a test's end
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
/// Tester::draw, what it would stop on said instead (a layout read back that does not converge: its words), None where
/// it draws as draw does. The same drawing as draw's and the same words: draw stops on what this says.
pub fn Tester::draw_said(self : Tester) -> String? {
  outside_came()
  self.frame_now()
  self.draw_owed_said(1)
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
  if self.past_inputs_next() || self.frames_on_clock() {
    return
  }
  self.frame_now()
  self.draw_owed(1)
}

///|
/// When the next input comes, as a run's script gave it (a replay's next step, Flow's): a host's frames are drawn
/// before it as the host drew them, and none after it ahead of it, so the input comes at its own moment whatever the
/// display's rate, only more or fewer frames between (+inf: none said).
pub fn Tester::inputs_next(self : Tester, at : Double) -> Unit {
  self.inputs_next = at
}

///|
/// Whether the host's next frame falls after the next input (Tester::inputs_next): not drawn ahead of it. An input due
/// already (what the test waited for came later than in the run) holds back no frame: the test is past it.
fn Tester::past_inputs_next(self : Tester) -> Bool {
  self.host_frames &&
  self.inputs_next > self.fake.time &&
  self.tick_after(self.fake.time) > self.inputs_next + due_hair
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
/// The last frame drawn again at its own moments (the host's and what is drawn's: Tester::frame_shown_at), the clock not
/// moved on: for a check that draws a frame of its own to look at and then the screen back as it was (contrast's,
/// Tester::audit).
fn Tester::frame_again(self : Tester) -> Unit {
  let c = g()
  self.frame_shown_at(self.fake.time, c.clock)
}

///|
/// The frames owed drawn (Tester::draw's, after `n` drawn already), each at the display's next frame: what a frame left
/// owed is drawn as the Tester stands, at its making (Tester::new), not left to the next input.
fn Tester::draw_owed(self : Tester, n : Int) -> Unit {
  match self.draw_owed_said(n) {
    Some(s) => @halt.saying(s)
    None => ()
  }
}

///|
/// The frames owed drawn as draw_owed draws them, what does not converge said and not stopped at: draw_owed's words,
/// the two one drawing (draw_owed stopping on what this says).
fn Tester::draw_owed_said(self : Tester, n : Int) -> String? {
  let mut n = n
  while self.owed_now() {
    if n == draw_frames_most {
      let c = g()
      if c.read_back_moved {
        return Some(
          "Tester::draw: what the view reads (\{c.read_back_key}) still changes after \{n} frames: it does not converge",
        )
      }
      return None
    }
    if self.past_inputs_next() || self.frames_on_clock() {
      return None
    }
    self.frame_now()
    n = n + 1
  }
  None
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
  self.reads_own()
  ignore(self)
  g().moving_now()
}

///|
/// When what moves named `name` is at rest (the frames' clock): the latest of those whose line (Tester::moving)
/// says `name` (`c.spring "seg"`, `Anim "fade"`, a key); +inf when one has not started; where none so named moves
/// now, when the latest of them came to rest (its own end, whichever frames were drawn on its way); -1 where none so
/// named was ever said to move. What a test runs to when the motion has no rest of its own to ask.
pub fn Tester::rest_of(self : Tester, name : String) -> Double {
  self.reads_own()
  ignore(self)
  rest_of(name)
}

///|
/// What was said to move under the Tester, by its line (Tester::moving's), and when it says it is at rest: seen before
/// and after each frame the Tester draws (tester_rests_seen), kept once the motion is over and the app has let go of it, for
/// rest_of. The Tester's own: nothing on the app's way keeps it (a device's app keeps no such record).
// kept across runs: emptied as each Tester is made (Tester::new)
let tester_rested : Map[String, Double] = Map([])

///|
/// What is said to move after the frame just drawn, each end as it says it, kept (tester_rested).
fn tester_rests_seen() -> Unit {
  let c = g()
  let now : Map[String, Bool] = Map([])
  for e in c.movers {
    let r = e.m.rest_at(c.clock, c.frame_no)
    now[e.what] = true
    if r >= 0.0 && r < @double.infinity {
      tester_rested[e.what] = r
    }
  }
  // (one said to be at rest later that moves no more, cut short (put at its end, motion reduced): at rest by this
  // frame, not at the end it said)
  let cut = []
  for what, r in tester_rested {
    if r > c.clock && !now.contains(what) {
      cut.push(what)
    }
  }
  for what in cut {
    tester_rested[what] = c.clock
  }
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
  // (and those so named already at rest: their ends as they said them, the latest, where none moves now)
  if last < 0.0 {
    for what, r in tester_rested {
      if what.contains(name) && r > last {
        last = r
      }
    }
  }
  last
}

///|
/// The clock brought to `at` (a moment on it, not a length) for an input to come at it, as a host's event comes
/// between two of its frames: the display's frames drawn up to the last at or before `at` (where its frames are said,
/// Tester::set_frame_period), then the host's clock put at `at` itself, no frame drawn there. So the same input given
/// at the same moments comes at those moments at any display rate, only more or fewer frames between; an input's own
/// frame (Tester::wheel's, drawn on the display's next frame, which moves the clock there) leaves the next input's
/// moment as it is. A moment already past: nothing.
pub fn Tester::input_at(self : Tester, at : Double) -> Unit {
  if self.host_frames {
    let last = grid_moment(self.origin, ((at - self.origin) / self.period + 1.0e-9).floor(), self.period)
    if last > self.fake.time + 1.0e-9 {
      self.run_for(last - self.fake.time)
    }
  } else if at > self.fake.time {
    self.run_for(at - self.fake.time)
  }
  // (at it to the bit, where a frame of the display's fell on it: its moment on the frames' grid can be a few last bits
  // off `at`, and an input given from there, its moves each an input_step on, would come that much off at every rate)
  if at >= self.fake.time - 1.0e-6 {
    self.fake.time = at
  }
}

///|
/// `ms` on the frames' clock, straight to it: a frame at each moment something is due (a wake the view asked for, the
/// end of what is said to move), and the last at `ms` itself, what is so at `ms` drawn there; with frames between (MBUI_TEST_FPS: a run at a frame rate, which comes
/// out the same) a frame at each of the display's frames too. None after it: what that frame leaves owed (an input's
/// frame after, a host's event) is drawn by what the test does next.
pub fn Tester::run_for(self : Tester, ms : Double) -> Unit {
  // (on the display's frame where it falls on one, to the bit: the same moment however it was summed)
  let end = self.on_grid(self.fake.time + ms)
  // (a host's run's frames: each of them on the way, the last the first at or past the end, as the host drew)
  if self.host_frames {
    while self.fake.time < end - 1.0e-9 {
      self.clock_frame()
    }
    // (asked on by a hair, less than the same moment summed another way: on to the frame that is at or past it; not
    // past a frame a hair short of the end, that frame the end's, as the loop above has it)
    if ms > 0.0 && end > self.fake.time + 1.0e-9 {
      self.clock_frame()
    }
    return
  }
  // (how far apart the frames on its way are: a rate's (MBUI_TEST_FPS); or, where the test asks for the frames a host
  // draws (Tester::run_shown), the display's own, a rate's only where it is closer: the frames a device draws)
  let between = if self.shown && !(self.between > 0.0 && self.between < self.period) {
    self.period
  } else {
    self.between
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
    // (frames on the way only while the app asks for them, as a host draws them: something moving, a frame asked
    // for; at rest, none till what is due)
    let mut next = if between > 0.0 && self.asks_frames() {
      dmin(self.between_after(self.fake.time, between), end)
    } else {
      end
    }
    let due = self.on_grid(self.next_due())
    if due > self.fake.time + 1.0e-9 && due < next {
      next = due
    }
    // (a frame on the way a hair from the end or from what is due is at that moment: the same moment summed another
    // way (the 10th of 24's frames from the origin, 2e-13 short of a 416.67 ms run's end), drawn there and not a hair
    // before it, where what changes at it has not)
    if (end - next).abs() < due_hair {
      next = end
    } else if due > self.fake.time + 1.0e-9 && (due - next).abs() < due_hair {
      next = due
    }
    // (one of the rate's own, on the way: neither the end nor what is due)
    // (the display's own frames, drawn on the way for a test that asked for them at no rate, are no rate's: judged as
    // those a test walks itself)
    self.on_way = self.between > 0.0 && next < end && !(due > self.fake.time + 1.0e-9 && next == due)
    self.frame_at(next)
    // what that frame left owed (a host's answer posted, an input's frame after, a layout read back) drawn at its
    // moment, as Tester::draw draws it: what it sets off goes on from there, not from the next due moment
    if next < end - 1.0e-9 {
      self.draw_owed(1)
    }
    self.on_way = false
  }
  // (and asked on by a hair, less than the same moment summed another way: there, at what was asked, not left a hair
  // short of it (a timer's moment summed as its cause's and a length, past the display's frame the clock is at))
  if ms > 0.0 && end > self.fake.time {
    self.frame_at(end)
  }
}

///|
/// Whether the app asks for frames after the last one, as a host is asked: something said to move, a frame asked for
/// between frames, a message posted that no frame took (Tester::rest_why says which). Where run_for draws the frames
/// on its way (MBUI_TEST_FPS): none while it asks none.
fn Tester::asks_frames(self : Tester) -> Bool {
  !g().frame_rest || self.fake.wants || posted_left() != ""
}

///|
/// The first of run_for's frames on its way after `t` (MBUI_TEST_FPS): `between` apart, counted from the Tester's
/// origin, as the display's are.
fn Tester::between_after(self : Tester, t : Double, between : Double) -> Double {
  let hair = grid_hair * between
  let mut k = ((t - self.origin) / between).floor() - 1.0
  while grid_moment(self.origin, k, between) <= t + hair {
    k = k + 1.0
  }
  grid_moment(self.origin, k, between)
}

///|
/// `ms` on the frames' clock as run_for, with the frames a host draws on its way: each of the display's frames while
/// the app asks for frames (something moving, a frame asked for, a message posted), none while it is at rest, till
/// what is due (a wake, a motion's end, what the outside says next: Tester::between_frames' `due`) or the end. At
/// the default rate as at a rate (MBUI_TEST_FPS, whose frames between they are where they are closer than the
/// display's). For a test that looks at every frame a device draws after a cause (Tester::each_frame): a frame
/// nobody draws shows nothing (the coordinator of the migration, 2026-11-14), and walking the display's frames one by
/// one through a rest draws them all. With a host's own frames (set_frame_times, set_frame_period) it is run_for.
pub fn Tester::run_shown(self : Tester, ms : Double) -> Unit {
  let was = self.shown
  self.shown = true
  self.run_for(ms)
  self.shown = was
}

///|
/// The `k`th of a grid's frames after `origin`, `period` (ms) apart, worked out at once: never summed frame by frame,
/// and where the period is a whole rate's (1000 over a whole number of frames a second, to the bit: 1000/24, 1000/7) k
/// times 1000 over that rate, rounded once. So what is one moment at two rates is one double (24's nth frame and 120's
/// 5nth; tester_grid_wbtest), and what is worked out of it, a fling's place there and a row's where it is drawn, the
/// same to the bit (list_drawn_band_wbtest): k times the period, a rounding already, came out a few last bits apart at
/// the two. Another period (a run's tape's, Tester::set_frame_period) k times itself.
fn grid_moment(origin : Double, k : Double, period : Double) -> Double {
  let rate = (1000.0 / period).round()
  if rate >= 1.0 && 1000.0 / rate == period {
    origin + (k * 1000.0) / rate
  } else {
    origin + k * period
  }
}

///|
/// Whether a host's frames are drawn only as the clock passes them (Tester::frames_by_clock): an input or a message
/// waits for the next of them, as on the host, not drawn a frame ahead of the clock.
// kept across runs: put back by each Tester (Tester::new)
let frames_by_clock_on : Ref[Bool] = Ref(false)

///|
/// A host's frames drawn only as the clock passes them (Tester::come_to, run_for), or also as an input or a message
/// asks for one (Tester::draw: at the display's next frame, the clock on to it): a replay's pace pass, whose inputs
/// come at their moments however the frames fall.
pub fn Tester::frames_by_clock(self : Tester, on : Bool) -> Unit {
  ignore(self)
  frames_by_clock_on.val = on
}

///|
fn Tester::frames_on_clock(self : Tester) -> Bool {
  self.host_frames && frames_by_clock_on.val
}

///|
/// The clock on to `t` as a host's runs between its frames (a replay's pace pass: an input at its moment): the
/// display's frames up to `t` drawn on the way, none at or past it drawn ahead of it; `t` itself no frame of its own.
/// Without a host's frames, run_for.
pub fn Tester::come_to(self : Tester, t : Double) -> Unit {
  posted_tell()
  if !self.host_frames {
    if t > self.fake.time {
      self.run_for(t - self.fake.time)
    }
    return
  }
  // (a host's frames: each of them up to `t` drawn, none past it; the clock then at `t` between two of them, as a
  // host's is when an input comes. And what the outside says between them (a kept message, Tester::between_frames'
  // `due`) at its own moment, told then between frames as a device's host tells what is posted (posted_tell), not
  // held for the next frame: with a host's frames only where it drew them, an idle app's next may be far off)
  let mut told = 0
  while true {
    let next = self.tick_after(self.fake.time)
    let said = match outside_due.val {
      Some(f) => f()
      None => @double.infinity
    }
    if said > self.fake.time && said <= t + due_hair && said < next - due_hair {
      // (said, not left: one that keeps saying a next moment between the same two frames is a fault of what says it)
      if told >= outside_told_most {
        @halt.saying(
          "Tester::come_to: the outside said \{outside_told_most} moments between two of the host's frames, the last at \{said} ms, the next frame at \{next} ms: what says its next moment (Tester::between_frames' due) says one more each time it is told",
        )
      }
      told += 1
      fake_dues_to(self.fake, said)
      if said > self.fake.time {
        self.fake.time = said
      }
      frame_ended_outside()
      posted_tell()
      continue
    }
    if next <= t + due_hair {
      self.clock_frame()
      continue
    }
    break
  }
  fake_dues_to(self.fake, t)
  if t > self.fake.time {
    self.fake.time = t
  }
}

///|
/// How many moments of the outside's come_to tells between two of a host's frames at most: one that keeps saying a
/// next moment is stopped there, saying so, not run on for ever nor let be.
let outside_told_most : Int = 10000

///|
/// Advance by exactly `ms`, drawing due wakes on the way and the requested moment itself, even when the tester is
/// otherwise running on a display's frame grid. Afterwards it keeps the same display clock for subsequent inputs.
pub fn Tester::run_for_exact(self : Tester, ms : Double) -> Unit {
  let host_frames = self.host_frames
  self.host_frames = false
  self.run_for(ms)
  self.host_frames = host_frames
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
  if tick >= t && tick - t < due_hair {
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
  // (and a decode said to take a while, at its moment: Tester::decode_after)
  for id, at in self.fake.decode_due {
    if at > now && at < due && self.fake.images.get(id) is Some(im) && im.state == 0 {
      due = at
    }
  }
  // (and what the fake host does at a moment of its own: FakeHost::due)
  let own = fake_due_next(now)
  if own < due {
    due = own
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
/// What asks for a frame now, said (None where nothing does): a frame asked for, a motion said that is not at rest, a
/// wake owed, a fiber or a ticket of the runtime running, a message posted that no frame took. What never ends while
/// shown (a cycle: a spinner, a breath) is not of it (Tester::cycles). The words assert_idle stops with: the two are one
/// asking, assert_idle stopping on what this says.
pub fn Tester::idle_said(self : Tester) -> String? {
  self.reads_own()
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
      (if layout_said.val != "" { layout_said.val } else { "what a part or a list's row read changed: (\{nodes_run.told_by.0}, \{nodes_run.told_by.1})" }) +
      ")",
    )
  } else if self.fake.wants && !c.wants_frame {
    why.push("a frame asked for between frames")
  }
  if paint_left() {
    why.push("a frame asked for to paint (\{paint_said.val})")
  }
  if c.waited_at() >= 0.0 {
    why.push("a wake in \{(c.waited_at() - c.clock).ceil().to_int()} ms" + c.waited_by())
  }
  let rt = fx.val.unsettled()
  if rt != "" {
    why.push(rt)
  }
  if why.length() > 0 {
    Some("Tester::assert_idle: not idle: " + why.join("; "))
  } else {
    None
  }
}

///|
/// Nothing asks for a frame now: no frame asked for, no motion said that is not at rest, no wake owed, no fiber or
/// ticket of the runtime running. Else the test fails, saying who (Tester::idle_said's words: the two are one asking).
/// What never ends while shown (a cycle: a spinner, a breath) does not break it: it is said (Tester::cycles).
pub fn Tester::assert_idle(self : Tester) -> Unit {
  match self.idle_said() {
    Some(s) => @halt.saying(s)
    None => ()
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
  self.waited_at() < 0.0 &&
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
  if self.waited_at() >= 0.0 {
    why.push("a wake in \{(self.waited_at() - self.clock).ceil().to_int()} ms" + self.waited_by())
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
  self.reads_own()
  g().frame_rest && !self.fake.wants && posted_left() == ""
}

///|
/// What keeps the app from its rest after the last frame, in words (Tester::at_rest): "" when nothing does.
pub fn Tester::rest_why(self : Tester) -> String {
  self.reads_own()
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
  self.reads_own()
  ignore(self)
  g().periodic.map(fn(p) { "every \{p.0.to_int()} ms by \{p.1}" })
}

///|
/// What never ends while shown in the last frame (Ctx::cycle): its period and who reads it, a line each.
pub fn Tester::cycles(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  g().cycles.map(fn(c) { "\{c.0.to_int()} ms by \{c.1}" })
}

///|
/// The focused field emptied, as a scripted run's `clear` empties it: all of it picked, then taken out.
pub fn Tester::clear(self : Tester) -> Unit {
  posted_tell()
  on_key(key_select_all, 0)
  posted_tell()
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
  self.reads_own()
  ignore(self)
  on_screen(g(), what)
}

///|
/// Where `what` is on screen that a finger reaches (not under what lies over it: a sheet, a scrim), as a scripted run's
/// tap finds it (drive.mbt reachable): the same press in a test as in the run.
pub fn Tester::reachable(self : Tester, what : String) -> Array[(Double, Double)] {
  self.reads_own()
  ignore(self)
  reachable(g(), what)
}

///|
/// The focused field's words ("" when none is focused).
pub fn Tester::field_words(self : Tester) -> String {
  self.reads_own()
  ignore(self)
  field_words(g())
}

///|
/// `words` pasted where the focus is, as a scripted run pastes (drive.mbt `paste`): put on the clipboard, then given
/// as the system gives a paste; the frames it causes drawn.
pub fn Tester::paste(self : Tester, words : String) -> Unit {
  h_clipboard_set(words)
  posted_tell()
  on_text(text_paste, words, 0, 0)
  self.draw()
}

///|
/// The key named `name` pressed, as a scripted run names keys (drive.mbt `key`): `esc`, `enter`, `shift+enter`,
/// `cmd+k` (Ctrl off macOS)…; false for a name it does not know. The frames it causes drawn.
pub fn Tester::key_named(self : Tester, name : String) -> Bool {
  match key_named(name) {
    Some((code, mods)) => {
      posted_tell()
      let was = g().focus
      on_key(code, mods)
      self.draw()
      self.focus_moved_held(code, mods, was)
      true
    }
    None => false
  }
}

///|
/// The window's size (points).
pub fn Tester::size(self : Tester) -> (Double, Double) {
  self.reads_own()
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
  self.reads_own()
  ignore(self)
  let c = g()
  let waited = c.waited_at()
  let ui = if waited < 0.0 { None } else { Some((waited, c.waited_by())) }
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

///|
/// Who said what the app waits on next (Ctx::waited_at): an old view's wake, where it said it; the window's tree's.
fn Ctx::waited_by(self : Ctx) -> String {
  if self.wake_waited >= 0.0 && self.waited_at() == self.wake_waited {
    by_of(self.wake_by)
  } else {
    // (which of the tree's timers: where it was said, so that each that comes once is told from one saying itself again)
    match view_app.val {
      Some(tree) if tree.wake_waited_by() != "" => " (the window's tree's, said at \{tree.wake_waited_by()})"
      _ => " (the window's tree's)"
    }
  }
}
