// Time in a test is said by the test (docs/determinism.md): an input is handed in and the frames it causes drawn, at
// its moment; time goes on only by `run_for` (a declared duration: a motion's, a timer's); and at its end nothing may
// go on asking for frames (`assert_idle`). Nothing waits for motion to end: motion only draws what the state already
// is, so what a test asserts of the state holds as the input is taken, and a picture is taken at a moment the test
// names.

///|
/// The frames owed now, drawn at this moment (no time goes by): after an input, the frame that takes it, the one after
/// (what read it late: a list's rows), a layout read back once more; after a change the test made (a value it set),
/// the frame that shows it. Three at most.
pub fn Tester::draw(self : Tester) -> Unit {
  self.frame(ms=0.0)
  let mut n = 1
  while n < 3 && (g().wants_frame || self.fake.wants) {
    self.frame(ms=0.0)
    n = n + 1
  }
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
}

///|
/// Nothing asks for a frame now: no frame asked for, no wake owed, no fiber or ticket of the runtime running. Else the
/// test fails, saying who.
pub fn Tester::assert_idle(self : Tester) -> Unit {
  // (the frame the last input or motion left owed is drawn first: idle is what comes after)
  self.draw()
  let c = g()
  let why = []
  if c.wants_frame || self.fake.wants {
    why.push("a frame asked for" + by_of(c.frame_by))
  }
  if c.wake_waited >= 0.0 {
    why.push("a wake at \{c.wake_waited.to_int()} ms" + by_of(c.wake_by))
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
}

///|
fn by_of(l : SourceLoc?) -> String {
  match l {
    Some(l) => " (by \{l})"
    None => ""
  }
}

///|
/// When the last motion said is at rest (the frames' clock, as `time`; -1: none moves): a test runs to it by
/// run_for(motion_end() - time()).
pub fn Tester::motion_end(self : Tester) -> Double {
  ignore(self)
  g().motion_end()
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
  self.frame()
  self.draw()
}

///|
/// The key named `name` pressed, as a scripted run names keys (drive.mbt `key`): `esc`, `enter`, `shift+enter`,
/// `cmd+k` (Ctrl off macOS)…; false for a name it does not know. The frames it causes drawn.
pub fn Tester::key_named(self : Tester, name : String) -> Bool {
  match key_named(name) {
    Some((code, mods)) => {
      on_key(code, mods)
      self.frame()
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
      self.frame()
      self.draw()
      true
    }
    None => false
  }
}
