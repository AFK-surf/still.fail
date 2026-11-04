// A host draws a frame only where the app asked for one (on_frame's end: h_request_frame, h_request_frame_on,
// h_wake_after); a Tester draws where the test says, and run_for draws at each motion's end whether it was asked
// for or not (next_due). What moves on a Tester while the app asks for no frame stands still on a device until
// something else asks: the picture a test sees is not the one a person sees.

///|
/// Every display frame for `ms` from now drawn, as a host whose display is always on draws them; the moments where
/// what is drawn changed though the frame before asked for no frame by then (none, a wake later, a motion's end it
/// never said): there a host shows the frame before, still, until something else asks for one.
pub fn Tester::unasked_changes(self : Tester, ms : Double) -> Array[Double] {
  let end = self.on_grid(self.fake.time + ms)
  let out : Array[Double] = []
  let mut on = self.fake.frames_on
  let mut before = drawn_hash()
  // (the frame drawn last, before this run: what it asked for as it ended, as on_frame told its host)
  let mut first = true
  while self.fake.time < end - 1.0e-9 {
    let next = self.tick_after(self.fake.time)
    let woken = self.fake.wake >= 0.0 && self.fake.wake <= next + 1.0e-9
    let asked = if first {
      self.wanted_after() <= next + 1.0e-9
    } else {
      self.fake.wants || self.fake.frames_on != on || woken
    }
    first = false
    if woken {
      self.fake.wake = -1.0
    }
    on = self.fake.frames_on
    self.frame_at(next)
    let now = drawn_hash()
    if !asked && now != before {
      out.push(next)
    }
    before = now
  }
  out
}
