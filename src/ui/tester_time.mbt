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
