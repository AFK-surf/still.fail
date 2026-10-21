// Motion as data, not commands (docs/determinism.md): a motion is said once, as it starts (or anew when its target
// changes): where it goes, by what curve, from when, and so until when. Its value at a frame is a function of that
// frame's time. What moves says so itself, once, as it sets out (Ctx::moving: a spring's way as it is sent somewhere,
// an Anim as it is told to go); the framework asks it at each frame's end when it is at rest, draws frames until then
// and after it none. Nothing asks for frames one by one, and a view building says nothing of motion. What never ends
// while shown (a spinner) is a cycle: its phase is a function of the frames' clock, and it is drawn while something
// shown reads it.

///|
/// What moves by itself (a spring's way, an Anim): when it is at rest, on the frames' clock, asked at the end of each
/// frame (`now` its time, `frame` its number) while it is said to move. +inf: it does not know yet (it starts at a
/// frame to come), a frame is owed to it; at or before `now`: at rest, forgotten.
pub(open) trait Moving {
  rest_at(Self, now : Double, frame : Int) -> Double
  sample(Self, now : Double) -> Unit = _
}

///|
/// This frame's time, handed to what is said to move (`now`). Each frame, in this order: the runtime runs to the
/// frame's time (its fibers, fx.mbt); what is said to move is handed it; the view builds. Handed it while it is said to
/// move and the frame it is at rest too: sampled first, forgotten at that frame's end (Ctx::motion_owed). What sets out
/// as the view builds is not handed that frame's: Ctx::set_out answers it. What moves as data reads where it is from
/// it, not the clock. By default nothing.
impl Moving with sample(self, now) {
  ignore(self)
  ignore(now)
}

///|
/// Who moves: what moves holds one, made with it, and is told by it (Ctx::moving). It is that thing itself, not a
/// number: whatever context it was made in, and whatever was made or told before it, it is no other's.
pub struct Mover {
  priv mut told : Int
}

///|
/// A mover of its own, for what moves.
pub fn Mover::new() -> Mover {
  { told: 0 }
}

///|
/// What is said to move: who, what it is, what it is said to be and who told it (Tester::moving).
struct MoverEntry {
  who : Mover
  mut m : &Moving
  mut what : String
}

///|
/// `m` (`who` its mover) sets out: frames until it is at rest. Said once, by what moves, as it sets out; said again
/// (a new way) it replaces what was said. `what` it is (a spring, an Anim and its key), and who told it (`loc`): what a
/// test is told of it while it moves (Tester::moving).
#callsite(autofill(loc))
pub fn Ctx::moving(self : Ctx, who : Mover, m : &Moving, what? : String = "", loc~ : SourceLoc) -> Unit {
  self.moving_as(who, m, (if what == "" { "" } else { what + ", " }) + "told at \{loc}")
}

///|
/// `m` (`who` its mover) sets out now, as Ctx::moving says, and the moment it sets out at (the frames' clock): the
/// moment it is told, whatever frames come after it: told as the view builds or in an input's handler, this frame's;
/// told between frames, the clock's then (a frame is asked for, to show it). Where what moves as data starts from, not
/// the clock. Not for a fiber: its clock is the runtime's (whole ms), not the frames'.
#callsite(autofill(loc))
pub fn Ctx::set_out(self : Ctx, who : Mover, m : &Moving, what? : String = "", loc~ : SourceLoc) -> Double {
  self.moving_as(who, m, (if what == "" { "" } else { what + ", " }) + "told at \{loc}")
  if self.in_frame() {
    self.now
  } else {
    self.owe_frame()
    h_now()
  }
}

///|
/// What is said to move, handed this frame's time (Moving::sample): before the view builds.
fn Ctx::movers_sample(self : Ctx) -> Unit {
  // (what a sample sets out anew is handed the time from the next frame)
  let n = self.movers.length()
  for i in 0..<n {
    self.movers[i].m.sample(self.now)
  }
}

///|
/// The same as Ctx::moving, `what` saying all of what it is and who told it (what moves again by itself, as first told).
pub fn Ctx::moving_as(self : Ctx, who : Mover, m : &Moving, what : String) -> Unit {
  who.told = who.told + 1
  for e in self.movers {
    if physical_equal(e.who, who) {
      e.m = m
      e.what = what
      return
    }
  }
  self.movers.push({ who, m, what })
}

///|
/// What is said to move and is not at rest at the last frame's end: what it is, who told it, when it is at rest.
fn Ctx::moving_now(self : Ctx) -> Array[String] {
  let out = []
  for e in self.movers {
    let r = e.m.rest_at(self.now, self.frame_no)
    if r > self.now {
      let at = if r == @double.infinity { "not started" } else { "at rest at \{r} ms" }
      out.push(e.what + " (" + at + ")")
    }
  }
  out
}

///|
/// How many whole periods of `period` ms the frames' clock has passed since `from` (0 by default): what changes every
/// so often while shown (a run's time said each second, counted from when it started; a clock's minute), and a frame
/// at the next period's start, none between, so what shows the count changes as it does (a run started at 600 ms says
/// its next second at 1600, not at 2000). Before `from`, none (0), the frame at `from` the next. A count kept on
/// another clock (a run's time since the station said it started, the time of day) says how far it is now instead
/// (`elapsed`, ms): its next period's frame is as far from now as that count is from its next. A test's idle is not
/// broken by it: it is said (Tester::periodic), as what comes again for as long as it is shown.
#callsite(autofill(loc))
pub fn Ctx::every(
  self : Ctx,
  period : Double,
  from? : Double = 0.0,
  elapsed? : Double,
  loc~ : SourceLoc,
) -> Int {
  if period <= 0.0 {
    return 0
  }
  if !self.periodic.iter().any(fn(p) { p.1.to_string() == loc.to_string() }) {
    self.periodic.push((period, loc))
  }
  let gone = match elapsed {
    Some(e) => e
    None => self.now - from
  }
  if gone < 0.0 {
    self.wake_at_time(self.now - gone, later=true)
    return 0
  }
  let n = (gone / period).floor()
  // the next period's start: a wake the test's idle does not wait for (it comes for as long as it is shown); counted
  // from `from`, that start itself (from + its periods), else as far on as the count is from its next
  let next = match elapsed {
    Some(_) => self.now + period - (gone - period * n)
    None => from + (n + 1.0) * period
  }
  self.wake_at_time(next, later=true)
  n.to_int()
}

///|
/// Where a cycle of `period` ms is now, from 0 to 1 (a spinner's turn, a breath): read by what shows it, a frame each
/// frame while it is shown. A test's idle is not broken by it: it is said (Tester::cycles), as what never ends.
#callsite(autofill(loc))
pub fn Ctx::cycle(self : Ctx, period : Double, loc~ : SourceLoc) -> Double {
  self.cycling = true
  if !self.cycles.iter().any(fn(c) { c.1.to_string() == loc.to_string() }) {
    self.cycles.push((period, loc))
  }
  if period <= 0.0 {
    0.0
  } else {
    let p = self.now / period
    p - p.floor()
  }
}

///|
/// Whether something said to move is not at rest at this frame's end (the next frame is owed to it); what is, is
/// forgotten.
fn Ctx::motion_owed(self : Ctx) -> Bool {
  let mut owed = false
  self.motion_unstarted = false
  self.movers.retain(fn(e) {
    let r = e.m.rest_at(self.now, self.frame_no)
    if r > self.now {
      owed = true
      if r == @double.infinity {
        self.motion_unstarted = true
      }
      true
    } else {
      false
    }
  })
  owed
}

///|
/// When the last of what is said to move is at rest (-1: none moves).
fn Ctx::motion_end(self : Ctx) -> Double {
  let mut last = -1.0
  for e in self.movers {
    let r = e.m.rest_at(self.now, self.frame_no)
    if r > last {
      last = r
    }
  }
  last
}

// ── a spring, solved ─────────────────────────────────────────────────────────

///|
/// A spring's way as data: from `x0` (moving at `v0` a second) at `t0` (ms, the frames' clock) towards `to`, by
/// stiffness `k` and damping `c`, at rest (`to`, within `rest`) from `end` on. Where it is at a time is solved, not
/// stepped, so it is the same at any frame rate; the way is said anew only when it is sent somewhere else (go) or put
/// somewhere (put). Sent somewhere, it says so (Ctx::moving): frames until it is at rest.
pub struct SpringPath {
  priv mut x0 : Double
  priv mut v0 : Double
  priv mut to : Double
  priv mut t0 : Double
  priv mut end : Double
  priv k : Double
  priv c : Double
  priv rest : Double
  priv id : Mover
}

///|
/// A spring at rest at `x`.
pub fn SpringPath::new(x : Double, k~ : Double, c~ : Double, rest? : Double = 0.001) -> SpringPath {
  { x0: x, v0: 0.0, to: x, t0: 0.0, end: -1.0, k, c, rest, id: Mover::new() }
}

///|
/// Where it is at `now` and how fast it goes (a second).
pub fn SpringPath::at(self : SpringPath, now : Double) -> (Double, Double) {
  if now >= self.end {
    return (self.to, 0.0)
  }
  let (d, v) = spring_at(self.x0 - self.to, self.v0, self.k, self.c, dmax(0.0, now - self.t0) / 1000.0)
  (self.to + d, v)
}

///|
/// Where it is at `now`.
pub fn SpringPath::value(self : SpringPath, now : Double) -> Double {
  self.at(now).0
}

///|
/// Where it goes.
pub fn SpringPath::target(self : SpringPath) -> Double {
  self.to
}

///|
/// When it is at rest (the frames' clock, ms; before now: it is).
pub fn SpringPath::end(self : SpringPath) -> Double {
  self.end
}

///|
/// Sent to `to` at `now`, from where it is then, as fast as it goes then (or at `v` a second). `what` it is, for a
/// test told what moves (Tester::moving).
#callsite(autofill(loc))
pub fn SpringPath::go(
  self : SpringPath,
  now : Double,
  to : Double,
  v? : Double,
  what? : String = "a spring",
  loc~ : SourceLoc,
) -> Unit {
  let (x, v1) = self.at(now)
  self.x0 = x
  self.v0 = v.unwrap_or(v1)
  self.to = to
  self.t0 = now
  self.end = now + 1000.0 * spring_end(x - to, self.v0, self.k, self.c, self.rest)
  g().moving(self.id, self as &Moving, what=what + " to \{to}", loc~)
}

///|
pub impl Moving for SpringPath with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.end
}

///|
/// Sent to `to` at this frame's time (`c`'s clock: no clock read by its caller), from where it is then, as fast as it
/// goes then (or at `v` a second).
#callsite(autofill(loc))
pub fn SpringPath::go_at(self : SpringPath, c : Ctx, to : Double, v? : Double, loc~ : SourceLoc) -> Unit {
  match v {
    Some(v) => self.go(c.now, to, v~, loc~)
    None => self.go(c.now, to, loc~)
  }
}

///|
/// Where it is at this frame's time (`c`'s clock).
pub fn SpringPath::value_at(self : SpringPath, c : Ctx) -> Double {
  self.value(c.now)
}

///|
/// At `x` at once, at rest (held by a finger, placed).
pub fn SpringPath::put(self : SpringPath, x : Double) -> Unit {
  self.x0 = x
  self.v0 = 0.0
  self.to = x
  self.end = -1.0
}

///|
/// A damped spring's way from `x0` (moving at `v0`, per second) to rest at 0, `t` seconds on: where it is and how
/// fast it goes. Under-, critically and over-damped, in closed form.
fn spring_at(x0 : Double, v0 : Double, k : Double, c : Double, t : Double) -> (Double, Double) {
  let w0 = k.sqrt()
  let z = c / (2.0 * w0)
  if z < 1.0 - 1.0e-9 {
    let wd = w0 * (1.0 - z * z).sqrt()
    let a = x0
    let b = (v0 + z * w0 * x0) / wd
    let e = @dmath.exp(-z * w0 * t)
    let cs = @dmath.cos(wd * t)
    let sn = @dmath.sin(wd * t)
    let x = e * (a * cs + b * sn)
    let v = e * ((b * wd - z * w0 * a) * cs - (a * wd + z * w0 * b) * sn)
    (x, v)
  } else if z > 1.0 + 1.0e-9 {
    let r = w0 * (z * z - 1.0).sqrt()
    let r1 = -z * w0 + r
    let r2 = -z * w0 - r
    let c2 = (v0 - r1 * x0) / (r2 - r1)
    let c1 = x0 - c2
    let e1 = @dmath.exp(r1 * t)
    let e2 = @dmath.exp(r2 * t)
    (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
  } else {
    let b = v0 + w0 * x0
    let e = @dmath.exp(-w0 * t)
    ((x0 + b * t) * e, (b - w0 * (x0 + b * t)) * e)
  }
}

///|
/// When (seconds on) a spring from `x0` at `v0` has come to rest: within `eps` of it and slower than `eps` a second,
/// for good (its envelope there). 0 when it is at rest already.
fn spring_end(x0 : Double, v0 : Double, k : Double, c : Double, eps : Double) -> Double {
  if x0.abs() < eps && v0.abs() < eps {
    return 0.0
  }
  let w0 = k.sqrt()
  let z = c / (2.0 * w0)
  // the slowest decay rate, and a bound of the amplitude
  let rate = if z < 1.0 { z * w0 } else { w0 * (z - (z * z - 1.0).sqrt()) }
  let amp = x0.abs() + (v0.abs() + z * w0 * x0.abs()) / (w0 * dmax(1.0e-6, (1.0 - z * z).abs().sqrt())) + 1.0
  let bound = dmax(amp, amp * w0)
  dmax(0.0, @dmath.ln(bound / eps) / rate)
}
