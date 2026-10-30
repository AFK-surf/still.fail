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
  keeps_time(Self) -> Bool = _
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
/// Whether what moves keeps the time it is handed (Moving::sample) for the view to read where it is as it builds (a bar
/// whose springs are read so): then the time it is handed is the clock read followed (Ctx::now), and what is built is
/// built again each frame it moves (frame_watch.mbt); else it is handed the time as it stands, and only what reads
/// where it is, as it reads it, follows the clock. By default it keeps none.
impl Moving with keeps_time(self) {
  ignore(self)
  false
}

///|
/// Who moves: what moves holds one, made with it, and is told by it (Ctx::moving). It is that thing itself, not a
/// number: whatever context it was made in, and whatever was made or told before it, it is no other's.
pub struct Mover {
  priv mut told : Int
  /// how many times it was told, as a signal, once a part or a row kept read where it is (Ctx::shows_motion)
  priv mut said : @signals.Signal[Int]?
}

///|
/// A mover of its own, for what moves.
pub fn Mover::new() -> Mover {
  { told: 0, said: None }
}

///|
/// What it moves is told anew (set going, or put somewhere at once: snapped, set): what was built from where it was
/// (Ctx::shows_motion) is built again.
pub fn Mover::changed(self : Mover) -> Unit {
  self.told = self.told + 1
  match self.said {
    Some(s) => s.set(self.told)
    None => ()
  }
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
    self.clock
  } else {
    self.owe_frame()
    h_now()
  }
}

///|
/// What `f` reads (where a motion is now, a value's signal) read for node `node`, laid out this frame: by the list's row
/// or the part kept that it is drawn in (the innermost; kept_part.mbt, kept_rows.mbt), as though its build had read it,
/// so that it is built again as that changes, and each frame while a motion it reads goes; read as it is where none
/// holds it (or `node` is -1). For what reads, once the frame is laid out, what moves what was laid out (the motion
/// package's moves and reshapes): what a drawing depends on is followed where it is read, whoever told it, wherever
/// and whenever (signals' rule: a dependence is said by the read, not by the write).
pub fn Ctx::reads_for(self : Ctx, node : Int, f : () -> Unit) -> Unit {
  let mut row = 0
  let mut part = 0
  let mut p = node
  while p >= 0 && p < self.nodes.length() {
    match self.drawn_entry(p) {
      Some(e) => {
        if row == 0 && e.said_row != 0 {
          row = e.said_row
        }
        if e.part != 0 {
          part = e.part
          break
        }
      }
      None => ()
    }
    p = self.nodes[p].parent
  }
  read_for(part, row, f)
}

///|
/// What is said to move, handed this frame's time (Moving::sample): before the view builds.
fn Ctx::movers_sample(self : Ctx) -> Unit {
  // (what a sample sets out anew is handed the time from the next frame)
  let n = self.movers.length()
  for i in 0..<n {
    let m = self.movers[i].m
    m.sample(if m.keeps_time() { self.now() } else { self.clock })
  }
}

///|
/// The same as Ctx::moving, `what` saying all of what it is and who told it (what moves again by itself, as first told).
pub fn Ctx::moving_as(self : Ctx, who : Mover, m : &Moving, what : String) -> Unit {
  who.changed()
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
    let r = e.m.rest_at(self.clock, self.frame_no)
    if r > self.clock {
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
  self.tick_said(false, period, loc)
  let gone = match elapsed {
    Some(e) => e
    None => self.clock - from
  }
  if gone < 0.0 {
    self.wake_at_time(self.clock - gone, later=true, loc~)
    return 0
  }
  // the next period's start: a wake the test's idle does not wait for (it comes for as long as it is shown); counted
  // from `from`, that start itself (from + its periods), else as far on as the count is from its next
  let (n, next) = match elapsed {
    Some(_) => {
      let n = (gone / period).floor()
      // (on a period's start, the division a hair short of it: that period begun, as periods_at counts)
      let n = if self.clock + period - (gone - period * n) <= self.clock { n + 1.0 } else { n }
      (n.to_int(), self.clock + period - (gone - period * n))
    }
    None => periods_at(self.clock, from, period)
  }
  self.wake_at_time(next, later=true, loc~)
  n
}

///|
/// How far apart a resident cycle steps (ms): what stays up for as long as something elsewhere goes on (a station's
/// glyph blinking while it works, a chat's waiting dots and watching beat, a service's breath while it is alive) on one
/// clock, the spokes' (still.fail's: 「进行中」逐格走), drawn once a step, together, never on each of the display's
/// frames. (Drawn as the display refreshed, one shown redrew the whole window 60 to 120 times a second for as long as
/// it showed: minutes, hours, over Home with an agent at work.)
pub let cycle_step_ms : Double = 100.0

///|
/// Where a cycle of `period` ms is now, from 0 to 1 (a spinner's turn, a breath), read by what shows it while it is
/// shown. A wait (a spinner, a skeleton's breath, a band of unknown progress: gone when what it waits for comes) is
/// drawn each frame, smooth. `resident`: it stays up for as long as what it tells of lasts (cycle_step_ms), so it is at
/// the step of the clock it is at, a frame at the next step, none between. A cycle of 0 is drawn each frame (a player
/// playing: its pictures come as the display's frames do). A test's idle is not broken by it: it is said
/// (Tester::cycles), as what never ends.
#callsite(autofill(loc))
pub fn Ctx::cycle(self : Ctx, period : Double, resident? : Bool = false, loc~ : SourceLoc) -> Double {
  self.tick_said(true, period, loc)
  if period <= 0.0 {
    self.cycling = true
    part_live()
    return 0.0
  }
  // (a frame measured for contrast: each loop at its start, a breath whole, a spinner's first spoke lit, as it is seen
  // at its strongest: contrast.mbt)
  if inst_owners.on {
    return 0.0
  }
  let at = if resident {
    let step = (self.clock / cycle_step_ms).floor()
    self.wake_at_time((step + 1.0) * cycle_step_ms, later=true, loc~)
    step * cycle_step_ms
  } else {
    self.cycling = true
    part_live()
    self.now()
  }
  let p = at / period
  p - p.floor()
}

///|
/// Where a loop of `length` ms is now (ms into it) whose look changes at `ends` (ms into it, ascending: a moving
/// picture's frames' ends, the steps of a mark's blink), a frame as the next comes, none between. Said as a cycle
/// (Ctx::cycle).
#callsite(autofill(loc))
pub fn Ctx::loop_at(self : Ctx, length : Double, ends : Array[Double], loc~ : SourceLoc) -> Double {
  if !self.cycles.iter().any(fn(c) { c.1.to_string() == loc.to_string() }) {
    self.cycles.push((length, loc))
  }
  if length <= 0.0 {
    return 0.0
  }
  let laps = (self.clock / length).floor()
  let t = self.clock - laps * length
  let mut next = length
  for e in ends {
    if e > t {
      next = e
      break
    }
  }
  self.wake_at_time(laps * length + next, later=true, loc~)
  t
}

///|
/// Whether something said to move is not at rest at this frame's end (the next frame is owed to it); what is, is
/// forgotten.
fn Ctx::motion_owed(self : Ctx) -> Bool {
  let mut owed = false
  self.motion_unstarted = false
  self.movers.retain(fn(e) {
    let r = e.m.rest_at(self.clock, self.frame_no)
    if r > self.clock {
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
    let r = e.m.rest_at(self.clock, self.frame_no)
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
  /// a Move's way instead (SpringPath::moved): as long as it goes far, from where it is sent (0: a spring's)
  priv mut dur : Double
  priv moves : Bool
}

///|
/// A spring at rest at `x`.
pub fn SpringPath::new(x : Double, k~ : Double, c~ : Double, rest? : Double = 0.001) -> SpringPath {
  { x0: x, v0: 0.0, to: x, t0: 0.0, end: -1.0, k, c, rest, id: Mover::new(), dur: 0.0, moves: false }
}

///|
/// At rest at `x`, sent on a Move's way (move_path) as long as its way is far (move_ms: its units points), as fast
/// as it goes (or is let go at): a sheet risen, sunk, let go.
pub fn SpringPath::moved(x : Double) -> SpringPath {
  { x0: x, v0: 0.0, to: x, t0: 0.0, end: -1.0, k: 0.0, c: 0.0, rest: 0.0, id: Mover::new(), dur: 0.0, moves: true }
}

///|
/// Where it is at `now` and how fast it goes (a second).
pub fn SpringPath::at(self : SpringPath, now : Double) -> (Double, Double) {
  if now >= self.end {
    return (self.to, 0.0)
  }
  if self.moves {
    let (d, v) = move_path(self.x0 - self.to, self.v0 / 1000.0, dmax(0.0, now - self.t0), self.dur)
    return (self.to + d, v * 1000.0)
  }
  let (d, v) = spring_at(self.x0 - self.to, self.v0, self.k, self.c, dmax(0.0, now - self.t0) / 1000.0)
  (self.to + d, v)
}

///|
/// Where it is at `now` (what is being built from it, built again each frame till it rests: kept_part.mbt).
pub fn SpringPath::value(self : SpringPath, now : Double) -> Double {
  g().shows_motion(self.id, now < self.end)
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
  if self.moves {
    self.dur = if x == to && self.v0 == 0.0 { 0.0 } else { move_ms((x - to).abs()) }
    self.end = now + self.dur
  } else {
    self.end = now + 1000.0 * spring_end(x - to, self.v0, self.k, self.c, self.rest)
  }
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
    Some(v) => self.go(c.clock, to, v~, loc~)
    None => self.go(c.clock, to, loc~)
  }
}

///|
/// Where it is at this frame's time (`c`'s clock).
pub fn SpringPath::value_at(self : SpringPath, c : Ctx) -> Double {
  self.value(c.now_before(self.end))
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

///|
/// What comes again while it shows, said where it is built (`cycle`: never ends, Ctx::cycle; else every `period`,
/// Ctx::every): the frame's (Tester::cycles, periodic), and held by the node it is built in (`node`, else what is being
/// built), said again of it where it is kept as its nodes (ticks_said_again).
fn Ctx::tick_said(self : Ctx, cycle : Bool, period : Double, loc : SourceLoc, node? : Int = -1) -> Unit {
  self.tick_add(cycle, period, loc)
  let i = if node >= 0 { node } else { self.cur }
  if i >= 0 && i < self.count {
    let n = self.nodes[i]
    match n.ticks {
      Some(ts) => ts.push((cycle, period, loc))
      None => n.ticks = Some([(cycle, period, loc)])
    }
  }
}

///|
fn Ctx::tick_add(self : Ctx, cycle : Bool, period : Double, loc : SourceLoc) -> Unit {
  let into = if cycle { self.cycles } else { self.periodic }
  if !into.iter().any(fn(c) { c.1.to_string() == loc.to_string() }) {
    into.push((period, loc))
  }
}

///|
/// What the nodes `from` until `to` said comes again as they were built (a row or a part kept as its nodes, put back
/// unbuilt), said again.
fn Ctx::ticks_said_again(self : Ctx, from : Int, to : Int) -> Unit {
  for i in from..<to {
    match self.nodes[i].ticks {
      Some(ts) =>
        for t in ts {
          self.tick_add(t.0, t.1, t.2)
        }
      None => ()
    }
  }
}
