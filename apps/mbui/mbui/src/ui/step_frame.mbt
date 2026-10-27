// A frame stepped, not built: where the only thing that moves on is a look by the clock on its resident steps
// (cycle_look.mbt: a spinner's spokes, a waiting dot, every 100 ms), the frame before drawn again with each such look
// where its cycle is now, nothing built, laid out or painted (2026-10-27, an iPhone Duo's list beside a chat at work:
// its whole page built ten times a second for its spokes, 12 to 20% of a core with nothing touched). A frame is
// stepped only where it would come out as the one built would: nothing came from outside since (outside_events: an
// input, a message, the host's event, a fiber's step), no input at all (a pointer moved over it), no motion, nothing
// owed nor waited on, no timer of the runtime's due, nothing else that woke it due, and the window, its scale and what
// the system says of it (its words' size, its colours, the keyboard) as they were. Every frame a Tester draws that
// could be stepped is built whole as well and the two held to the same instances (step_check): what a step leaves out
// shows there.

///|
/// The frame drawn last, as it can be stepped: whether it can, what it was drawn at, what it read of outside and of the
/// system, what else woke it (its time, and whether it was waited on), and the instances its looks by the clock were
/// drawn with before their looks (each one's place in the instances, and it as it was).
priv struct StepFrame {
  mut ok : Bool
  mut w : Double
  mut h : Double
  mut scale : Double
  mut outside : Int
  mut steps : Int
  mut env : String
  mut until : Double
  mut waited : Double
  mut ninst : Int
  tagged : Array[(Int, FixedArray[Double])]
  /// how many frames were stepped (under a Tester: held to the frame built, step_check), for the probe and the tests
  mut n : Int
  /// whether the frame told outside what it built (Ctx::after_build, Ctx::tell): what that does is the next's
  mut told : Bool
  /// why the last frame was not stepped, for the probe (MBUI_PROBE): what kept it from being stepped
  mut why : String
  /// the frame built before, as it was before its looks by the clock (their tags as tags, whatever their numbers), and
  /// whether this one drew the same: what it told outside changed nothing it draws
  mut prev : FixedArray[Double]
  mut prev_n : Int
  mut same : Bool
  /// what the frame told outside (its after_build's and tell's ids, in order), and what the one before told: the
  /// same, said again each frame, and drawing the same, what they do changes nothing
  mut tells : Array[Int]
  mut tells_before : Array[Int]
}

///|
// kept across runs: put back by each Tester (step_reset) and said again by each frame drawn whole (Ctx::step_keep)
let step : StepFrame = {
  ok: false,
  w: 0.0,
  h: 0.0,
  scale: 0.0,
  outside: -1,
  steps: -1,
  env: "",
  until: -1.0,
  waited: -1.0,
  ninst: 0,
  tagged: [],
  n: 0,
  told: false,
  why: "",
  prev: FixedArray::make(0, 0.0),
  prev_n: -1,
  same: false,
  tells: [],
  tells_before: [],
}

///|
/// None to step from, as a run begins.
fn step_reset() -> Unit {
  step.ok = false
  step.outside = -1
  step.steps = -1
  step.env = ""
  step.until = -1.0
  step.waited = -1.0
  step.ninst = 0
  step.tagged.clear()
  step.n = 0
  step.told = false
  step.why = ""
  step.prev = FixedArray::make(0, 0.0)
  step.prev_n = -1
  step.same = false
  step.tells = []
  step.tells_before = []
}

///|
/// Under a Tester: the test may have changed what the app reads (a value it set, a page pushed), as no host's frame
/// can, so the next frame is built (and not held to a step).
fn step_test_changed() -> Unit {
  step.ok = false
}

///|
/// What a frame built tells outside (frame_body): Ctx::after_build's ids, then Ctx::tell's.
fn step_told(after : Array[Int], told : Array[Int]) -> Unit {
  step.tells_before = step.tells
  step.tells = after + told
  step.told = !step.tells.is_empty()
}

///|
/// What the system says that a build reads as it builds, not told as an event from outside: as it was, a frame stepped
/// draws what a build would.
fn step_env() -> String {
  "\{reduced_motion()} \{h_reduce_transparency()} \{system_dark()} \{window_inset()} \{font_scale()} " +
  "\{whole_px_layout()} \{h_a11y_on()} \{h_ime_inset()} \{copy_shown()}"
}

///|
/// As the paint ends, before the looks by the clock are drawn (frame_body): what else woke the frame, and each
/// instance a look by the clock is to be drawn on, as it is before its look.
fn Ctx::step_note(self : Ctx) -> Unit {
  // (the same as the frame built before: what each build tells outside, said again each frame (a size kept, a trouble
  // let go), changed nothing)
  let n = self.ninst * inst_size
  let mut same = self.ninst == step.prev_n
  let mut k = 0
  while same && k < n {
    let (a, b) = (self.inst[k], step.prev[k])
    if a != b && !(k % inst_size == 20 && a < 0.0 && b < 0.0) {
      same = false
    }
    k = k + 1
  }
  step.same = same
  if step.prev.length() < n {
    step.prev = FixedArray::make(n, 0.0)
  }
  for q in 0..<n {
    step.prev[q] = self.inst[q]
  }
  step.prev_n = self.ninst
  step.tagged.clear()
  step.until = self.wake_at
  step.waited = self.wake_waited
  for q in 0..<self.ninst {
    let b = q * inst_size
    if cycle_tag_of(self.inst, b) != 0 {
      let kept = FixedArray::make(inst_size, 0.0)
      for k in 0..<inst_size {
        kept[k] = self.inst[b + k]
      }
      step.tagged.push((q, kept))
    }
  }
}

///|
/// A frame drawn (built whole or stepped) at `w` × `h` at `scale`: whether the next can be stepped from it, its looks by
/// the clock what alone moves on, on their resident steps (the frame they wake it for before anything else's).
fn Ctx::step_keep(self : Ctx, w : Double, h : Double, scale : Double) -> Unit {
  let why = if step.tagged.is_empty() {
    "no look by the clock"
  } else if step.told && !(step.same && step.tells == step.tells_before) {
    "told"
  } else if self.wants_frame {
    "owed"
  } else if self.motion_left {
    "motion"
  } else if self.cycling {
    "a look each frame"
  } else if self.fiber_frame {
    "fiber"
  } else if self.read_back_moved {
    "read back"
  } else if self.frame_by is Some(_) {
    "frame by"
  } else if !self.shots.is_empty() {
    "shot"
  } else if driver.val is Some(_) {
    "driven"
  } else if bench.mode != 0 {
    "bench"
  } else if self.wake_at <= 0.0 {
    "no step"
  } else if step.until >= 0.0 && step.until <= self.wake_at {
    "woken by \{step.until - self.now} ms"
  } else {
    ""
  }
  step.ok = why == ""
  step.why = why
  step.w = w
  step.h = h
  step.scale = scale
  step.outside = outside_events.val
  step.steps = fx.val.steps
  step.env = step_env()
  step.ninst = self.ninst
}

///|
/// Whether the frame at `t` (`fed`: an input came since the last) can be stepped from the last (StepFrame), all that
/// it would be built from as it was.
fn Ctx::step_can(self : Ctx, w : Double, h : Double, scale : Double, t : Double, fed : Bool) -> Bool {
  if !step.ok {
    return false
  }
  let why = if fed {
    "input"
  } else if w != step.w || h != step.h || scale != step.scale {
    "window"
  } else if self.ninst != step.ninst {
    "instances"
  } else if outside_events.val != step.outside {
    "outside"
  } else if fx.val.steps != step.steps || !fx.val.idle() {
    "fibers"
  } else if (match fx.val.next_timer() {
      Some(at) => at.to_double() <= t
      None => false
    }) {
    "timer"
  } else if step.until >= 0.0 && t >= step.until {
    "woken"
  } else if step_env() != step.env {
    "system"
  } else {
    ""
  }
  step.why = why
  why == ""
}

///|
/// The frame before's instances with each look by the clock drawn where its cycle is at `t`, into the frame's own (the
/// Ctx's time `t`, its next step asked for: Ctx::cycle_looks).
fn Ctx::step_looks(self : Ctx, t : Double) -> Unit {
  self.dt = if self.last_now < 0.0 { 16.67 } else { dclamp(t - self.last_now, 0.0, 100.0) }
  self.now = t
  self.last_now = t
  self.wants_frame = false
  self.cycling = false
  self.cycles.clear()
  self.wake_at = step.until
  self.wake_waited = step.waited
  for p in step.tagged {
    let (q, kept) = p
    let b = q * inst_size
    for k in 0..<inst_size {
      self.inst[b + k] = kept[k]
    }
  }
  self.cycle_looks()
}

///|
/// The frame at `t` stepped from the last, if nothing posted since has to be handed first (a frame built for it then,
/// the messages taken already): true when it was.
fn Ctx::step_try(self : Ctx, t : Double) -> Bool {
  take_messages()
  if messages_handed.val > 0 {
    return false
  }
  self.step_looks(t)
  step.n += 1
  self.t_build = 0.0
  self.t_layout = 0.0
  self.t_paint = 0.0
  true
}

///|
/// Under a Tester: the frame at `t` as a step from the last would draw it (nothing posted to hand: else none), to hold
/// the frame built whole to (step_check). The Ctx left as it was.
fn Ctx::step_predict(self : Ctx, t : Double) -> FixedArray[Double]? {
  if !fake_posted.is_empty() {
    return None
  }
  let (now, dt, last, wants, cycling, wake, waited) = (
    self.now,
    self.dt,
    self.last_now,
    self.wants_frame,
    self.cycling,
    self.wake_at,
    self.wake_waited,
  )
  let cycles = self.cycles.copy()
  let was = FixedArray::make(self.ninst * inst_size, 0.0)
  for k in 0..<(self.ninst * inst_size) {
    was[k] = self.inst[k]
  }
  self.step_looks(t)
  let stepped = FixedArray::make(self.ninst * inst_size, 0.0)
  for k in 0..<(self.ninst * inst_size) {
    stepped[k] = self.inst[k]
    self.inst[k] = was[k]
  }
  self.now = now
  self.dt = dt
  self.last_now = last
  self.wants_frame = wants
  self.cycling = cycling
  self.wake_at = wake
  self.wake_waited = waited
  self.cycles.clear()
  self.cycles.append(cycles)
  Some(stepped)
}

///|
/// The frame just built whole held to what a step from the last would have drawn (`stepped`): the same instances, or
/// the run stops, saying where they differ.
fn Ctx::step_check(self : Ctx, stepped : FixedArray[Double]) -> Unit {
  let n = self.ninst * inst_size
  if stepped.length() != n {
    abort("a frame stepped (step_frame.mbt) draws \{stepped.length() / inst_size} instances where the frame built draws \{self.ninst}")
  }
  for k in 0..<n {
    if stepped[k] != self.inst[k] {
      abort("a frame stepped (step_frame.mbt) differs from the frame built at instance \{k / inst_size}, slot \{k % inst_size}: \{stepped[k]} for \{self.inst[k]}")
    }
  }
  step.n += 1
}

///|
/// How many of its frames this Tester could have stepped from the one before (step_frame.mbt), each built whole and
/// held to the step.
pub fn Tester::steps(self : Tester) -> Int {
  ignore(self)
  step.n
}
