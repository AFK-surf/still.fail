// A frame of the looks by the clock alone (frame_watch.mbt) asks for the resident clock's next step as a frame built
// whole asks it: from its own moment, whether it has looks of its own to apply or not (2026-11-05: the chats' list flung
// back to its top on a phone, a frame of its looks alone at 2700 ms kept the step the frame before asked, 2700, and the
// frame built whole there asked 2800; the Tester's check stopped the run).

///|
/// A finger down at (x, y0), moved to y1 a display's frame at a time over `ms`, let go there: as a host hands it on.
fn resident_drag(t : @ui.Tester, x : Double, y0 : Double, y1 : Double, ms : Double) -> Unit {
  let p = t.frame_period()
  let n = (ms / p).ceil().to_int()
  t.touch_at(0, x, y0, t.time())
  for i in 1..=n {
    t.run_as_host(p)
    t.touch_at(1, x, y0 + (y1 - y0) * i.to_double() / n.to_double(), t.time())
  }
  t.touch_at(2, x, y1, t.time())
}

///|
test "the chats' list flung back to its top on a phone: each frame of its looks alone asks the next resident step as one built whole" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  t.record_host()
  resident_drag(t, 200.0, 700.0, 200.0, 300.0)
  t.run_as_host(1500.0)
  resident_drag(t, 200.0, 300.0, 600.0, 80.0)
  // (the Tester draws each frame of the looks alone whole as well and compares the two, what each asks next too)
  t.run_as_host(2000.0)
}
