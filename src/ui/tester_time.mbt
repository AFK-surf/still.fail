// Time in a test is said by the test (docs/determinism.md): an input is handed in and the frames it causes drawn, at
// its moment; time goes on only by `run_for` (a declared duration: a motion's, a timer's); and at its end nothing may
// go on asking for frames (`assert_idle`). Nothing waits for motion to end: motion only draws what the state already
// is, so what a test asserts of the state holds as the input is taken, and a picture is taken at a moment the test
// names.

///|
/// The frames owed now, drawn at this moment (no time goes by): after an input, the frame that takes it, the one after
/// (what read it late: a list's rows), a layout read back once more; after a change the test made (a value it set),
/// the frame that shows it; a motion said, the frame it starts at. Not a motion going on: at this moment it is where
/// it is (time goes on by run_for). Three at most: a layout read back still moving after them never converges, and
/// the test fails, saying whose.
pub fn Tester::draw(self : Tester) -> Unit {
  self.frame(ms=0.0)
  self.draw_owed(1)
}

///|
/// The frames owed at this moment drawn (Tester::draw's, after `n` drawn at it already): what a frame left owed is
/// drawn where the Tester stands, at its making (Tester::new) and a run's end (run_for), not left to the next input.
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
    self.frame(ms=0.0)
    n = n + 1
  }
}

///|
/// The most frames drawn at one moment (Tester::draw).
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
      let r = e.m.rest_at(c.now, c.frame_no)
      if r > c.now && r > last {
        last = r
      }
    }
  }
  last
}

///|
/// `ms` on the frames' clock, a frame each 16 ms, the last at `ms`.
pub fn Tester::run_for(self : Tester, ms : Double) -> Unit {
  let end = self.fake.time + ms
  while self.fake.time + 16.0 < end {
    self.frame()
  }
  if end > self.fake.time {
    self.frame(ms=end - self.fake.time)
  }
  // (what its last frame said starts there: drawn at that moment, as an input's frames are)
  self.draw_owed(1)
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
      } else {
        ""
      }),
    )
  } else if self.fake.wants && !c.wants_frame {
    why.push("a frame asked for between frames")
  }
  if c.wake_waited >= 0.0 {
    why.push("a wake in \{(c.wake_waited - c.now).ceil().to_int()} ms" + by_of(c.wake_by))
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
  on_text(0, words, 0, 0)
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
