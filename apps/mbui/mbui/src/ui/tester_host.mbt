// Each frame a Tester draws as a host would see it: whether the app asked for it, whether it drew something else than
// the frame before, why the old frame was built whole, what of the window a host that keeps its picture draws again
// (the parts h_present works out). Counts and moments, never times: the same on every machine.
// A frame no one asked for that drew something else is one a phone never shows; a frame asked for that changed
// nothing is work a phone does for nothing. Both are asserted here, as a host would meet them.

///|
/// One frame as the host got it.
#derive(Debug)
pub(all) struct HostFrame {
  /// its time on the clock
  at : Double
  /// whether the frame before asked for it (an input, a wake, a motion going on); false: a host draws none here
  asked : Bool
  /// whether what it drew differs from the frame before (drawn_hash)
  changed : Bool
  /// why the old frame was built whole in it ("" not: Tester::built_why)
  why : String
  /// the parts of the window a host that keeps its picture draws again (x, y, w, h; w < 0: all of it), and their share
  /// of the window (1: all)
  damage : Array[(Double, Double, Double, Double)]
  damage_share : Double
}

///|
/// The frames recorded since Tester::record_host (None: not recording).
// kept across runs: a test's, begun and taken by it; put back as a run begins (Tester::new: host_record_forget)
let host_record : Ref[Array[HostFrame]?] = Ref(None)

///|
/// Whether the next frame drawn is one the app asked for (Tester::run_as_host says; any other frame is a test's input's
/// or a moment it names, which a host draws).
// kept across runs: set for one frame by run_as_host, true otherwise
let host_asked_next : Ref[Bool] = Ref(true)

///|
/// The frames a recording Tester presented, the next compared with the last, as `presented` is a host's (h_present).
// kept across runs: a recording's, made anew as it begins (Tester::record_host)
let host_presented : Ref[@damage.Damage] = Ref(@damage.Damage::new())

///|
/// The parts the last frame presented handed its host (h_present, a recording Tester's).
// kept across runs: written by each frame a recording Tester presents
let host_parts_last : Ref[Array[(Double, Double, Double, Double)]] = Ref([])

///|
/// The hash of the frame recorded last.
// kept across runs: written by each frame recorded
let host_hash_last : Ref[Int64] = Ref(0L)

///|
fn host_record_forget() -> Unit {
  host_record.val = None
  host_asked_next.val = true
  host_parts_last.val = []
}

///|
/// A recording Tester's frame presented (h_present's fake host): the parts a host that keeps its picture is handed.
fn host_presented_now(buf : FixedArray[Double], count : Int) -> Unit {
  guard host_record.val is Some(_) else { return }
  // (a frame no one asked for is one a host never presents: what it keeps is still the last presented, the next frame's
  // parts worked out against that)
  guard host_asked_next.val else {
    host_parts_last.val = []
    return
  }
  let c = g()
  let (r, gg, b) = c.clear
  host_parts_last.val = host_presented.val.next(buf, count, c.window_w, c.window_h, c.scale, r, gg, b)
}

///|
/// Every frame drawn from now on recorded as its host got it (Tester::host_frames takes them).
pub fn Tester::record_host(self : Tester) -> Unit {
  ignore(self)
  host_record.val = Some([])
  host_presented.val = @damage.Damage::new()
  host_parts_last.val = []
  host_hash_last.val = drawn_hash()
}

///|
/// The frames recorded since Tester::record_host or the last taken, oldest first; recording goes on.
pub fn Tester::host_frames(self : Tester) -> Array[HostFrame] {
  self.reads_own()
  ignore(self)
  match host_record.val {
    Some(r) => {
      let out = r.copy()
      r.clear()
      out
    }
    None => []
  }
}

///|
/// The frame just drawn at `at`, recorded where recording (frame_shown_at's end).
fn host_frame_drawn(at : Double) -> Unit {
  guard host_record.val is Some(r) else {
    host_asked_next.val = true
    return
  }
  let hash = drawn_hash()
  let parts = host_parts_last.val
  let c = g()
  let area = parts.iter().fold(init=0.0, fn(a, q) { if q.2 < 0.0 || a < 0.0 { -1.0 } else { a + q.2 * q.3 } })
  let share = if area < 0.0 {
    1.0
  } else if c.window_w > 0.0 && c.window_h > 0.0 {
    area / (c.window_w * c.window_h)
  } else {
    0.0
  }
  r.push({
    at,
    asked: host_asked_next.val,
    changed: hash != host_hash_last.val,
    why: built_why.val,
    damage: parts,
    damage_share: share,
  })
  host_parts_last.val = []
  // (what the next frame changed is said against what the host shows: the last frame asked for)
  if host_asked_next.val {
    host_hash_last.val = hash
  }
  host_asked_next.val = true
}

///|
/// The display's frames for `ms` from now as a host draws them, recorded (Tester::record_host): each drawn, and said
/// asked or not by what the frame before asked for as it ended (on_frame's h_request_frame, h_request_frame_on,
/// h_wake_after). A frame not asked for that drew something else (HostFrame's asked false, changed true) is one a
/// phone never shows: what it drew stands still there until something else asks.
/// `skip_unasked`: a frame not asked for is not drawn at all, the clock moved past it, as an idle host does: what
/// shows then is only what the app asked the host for.
pub fn Tester::run_as_host(
  self : Tester,
  ms : Double,
  skip_unasked? : Bool = false,
) -> Unit {
  let end = self.on_grid(self.fake.time + ms)
  let mut on = self.fake.frames_on
  let mut first = true
  while self.fake.time < end - 1.0e-9 {
    let next = self.tick_after(self.fake.time)
    let woken = self.fake.wake >= 0.0 && self.fake.wake <= next + 1.0e-9
    // (the first: what was asked between frames as well, a test's input or a host's callback; a wake only as the host
    // was told it, h_wake_after, never what the app holds of it alone)
    let asked = if first {
      self.wanted_after() == 0.0 || woken
    } else {
      self.fake.wants || self.fake.frames_on != on || woken
    }
    first = false
    if woken {
      self.fake.wake = -1.0
    }
    on = self.fake.frames_on
    if skip_unasked && !asked {
      self.fake.time = next
      continue
    }
    host_asked_next.val = asked
    self.frame_at(next)
  }
}
