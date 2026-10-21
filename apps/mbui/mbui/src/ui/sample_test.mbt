// What moves as data handed the frames' time (Moving::sample, Ctx::set_out): its start as it sets out, where it is
// each frame from the time handed to it, not the clock.

///|
/// A straight way of `dur` ms as data: set out at `start` (+inf: not yet known), where it is the time since over its
/// length; the times it was handed, kept.
struct Way {
  mut start : Double
  dur : Double
  sampled : Array[Double]
  mover : @ui.Mover
}

///|
impl @ui.Moving for Way with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.start + self.dur
}

///|
impl @ui.Moving for Way with sample(self, now) {
  if self.start == @double.infinity {
    self.start = now
  }
  self.sampled.push(now)
}

///|
fn Way::at(self : Way, now : Double) -> Double {
  if now >= self.start + self.dur {
    1.0
  } else {
    (now - self.start) / self.dur
  }
}

///|
test "set out after a long rest: its start that frame's time, each frame handed that frame's, sampled at rest, then not" {
  let way_ms = 100.0
  let w = { start: -1.0, dur: way_ms, sampled: [], mover: @ui.Mover::new() }
  let go = Ref::new(false)
  let seen : Array[(Double, Double)] = []
  let t = @ui.Tester::new(fn(c) {
    if go.val {
      go.val = false
      w.start = c.set_out(w.mover, w as &@ui.Moving, what="a way")
    }
    if w.start >= 0.0 {
      seen.push((c.now(), w.at(c.now())))
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.draw()
  // at rest a long while: nothing said to move, no frames asked
  let rest_ms = 5000.0
  t.run_for(rest_ms)
  t.assert_idle()
  go.val = true
  // set out in the frame it was told in, drawn at its moment: that frame's time
  let told = t.time()
  t.draw()
  assert_eq(w.start, told)
  let start = w.start
  t.run_for(way_ms + 50.0)
  // each frame after the one it set out in handed its time before it built, and what it built read the closed form at
  // that time (no frame's length assumed)
  let last = w.sampled[w.sampled.length() - 1]
  for s in seen {
    if s.0 > start && s.0 <= last {
      assert_true(w.sampled.contains(s.0))
    }
    assert_eq(s.1, if s.0 >= start + way_ms { 1.0 } else { (s.0 - start) / way_ms })
  }
  // sampled the frame it is at rest (once), and not after
  let at_rest = w.sampled.filter(fn(n) { n >= start + way_ms })
  assert_eq(at_rest.length(), 1)
  let n = w.sampled.length()
  t.run_for(way_ms)
  assert_eq(w.sampled.length(), n)
  t.assert_idle()
}

///|
test "set out between frames: from the moment it was told, a frame asked for to show it" {
  let way_ms = 100.0
  let w = { start: -1.0, dur: way_ms, sampled: [], mover: @ui.Mover::new() }
  let t = @ui.Tester::new(fn(c) { c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore })
  t.draw()
  let told = t.time()
  let at = t.ctx().set_out(w.mover, w as &@ui.Moving, what="a way")
  assert_eq(at, told)
  w.start = at
  // said to move, at rest at its own end; a frame owed to show it
  assert_true(t.moving().length() == 1 && t.moving()[0].contains("at rest at \{told + way_ms}"), msg=t.moving().join("; "))
  assert_true(t.ctx().wants_frame)
  t.draw()
  assert_eq(w.start, told)
  t.run_for(way_ms)
  t.assert_idle()
}
