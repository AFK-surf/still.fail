// What scrolls inside a list that scrolls up and down: sideways (a code block that is not wrapped, a wide table, as
// Compose's horizontalScroll in a LazyColumn), or up and down within a box kept to a height (a tool step's long output,
// verticalScroll under heightIn). What it holds is laid out as wide (or as tall) as it is and cut to the box; a finger
// moving its way first drags it (and flings it on, slowing) while it can go that way, any other move is the list's, as
// if it had gone down on the list; the wheel likewise.

///|
priv struct Sideways {
  /// up and down (a capped box) rather than sideways
  vertical : Bool
  /// how far it is scrolled (0 at its start) and how far it can be
  mut x : Double
  mut max : Double
  /// flung on: at `v0` (px per ms) from `x0`, slowing by sideways_friction, from `t0` (the frames' clock; +inf: it
  /// starts at its first step), at rest at `rest` (-1: not flung) at `x_end`; held by a finger
  mut vel : Double
  mut x0 : Double
  mut v0 : Double
  mut t0 : Double
  mut rest : Double
  mut x_end : Double
  mover : Mover
  mut held : Bool
  /// this frame's box and what it holds (node indices), for their widths once laid out
  mut box : Int
  mut inner : Int
  mut frame : Int
}

///|
let sideways : Map[Int, Sideways] = {}

///|
/// How a fling slows: as the desktop's coasting (0.997 a ms; scroll.mbt), a little firmer on a phone's short rows.
let sideways_friction : Double = 0.996

///|
/// A box (as wide as `w`) whose content is laid out as wide as it is and scrolled sideways inside it (see the file's
/// head). `key` keeps where it is scrolled to from frame to frame. Its id, for what is drawn in it.
pub fn Ctx::sideways(
  self : Ctx,
  key : String,
  w? : Size = Fill(1.0),
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  body : () -> Unit,
) -> Int {
  let id = self.id("\u{1}sideways\u{1}" + key)
  let st = self.scroll_state(id, false)
  let px = if padx >= 0.0 { padx } else { pad }
  let py = if pady >= 0.0 { pady } else { pad }
  let mut inner = -1
  let b = self.box(dir=Row, w~, clip=true, id~, fn() {
    inner = self.box(tx=-st.x, pl=px, pr=px, pt=py, pb=py, body)
  })
  self.nodes[b].sideways = true
  // a scroll target (the pointer's), not a tap's
  self.nodes[b].hit = false
  st.box = b
  st.inner = inner
  st.frame = self.frame_no
  b
}

///|
/// The state of the scrolling box `id`, stepped to this frame (flung on, slowing until it stops or reaches an end).
fn Ctx::scroll_state(self : Ctx, id : Int, vertical : Bool) -> Sideways {
  let st = match sideways.get(id) {
    Some(s) => s
    None => {
      let s = {
        vertical,
        x: 0.0,
        max: 0.0,
        vel: 0.0,
        x0: 0.0,
        v0: 0.0,
        t0: 0.0,
        rest: -1.0,
        x_end: 0.0,
        mover: Mover::new(),
        held: false,
        box: -1,
        inner: -1,
        frame: -1,
      }
      sideways[id] = s
      s
    }
  }
  if !st.held && st.rest >= 0.0 {
    if st.t0 == @double.infinity {
      // its first step: it sets out now, its way solved once (where it stops, when)
      st.fling_from(self.now)
    }
    if self.now >= st.rest {
      st.x = st.x_end
      st.rest = -1.0
      st.vel = 0.0
    } else {
      st.x = fling_at(st.x0, st.v0, self.now - st.t0)
    }
  }
  st.x = dclamp(st.x, 0.0, dmax(st.max, 0.0))
  st
}

///|
/// How far a fling at `v0` (px per ms) has gone `t` ms on, slowing by sideways_friction a ms: solved for the time, the
/// same at any frame rate.
fn fling_at(x0 : Double, v0 : Double, t : Double) -> Double {
  let lf = @math.ln(sideways_friction)
  x0 + v0 * (@math.pow(sideways_friction, t) - 1.0) / lf
}

///|
/// Below this (px per ms) a fling has stopped.
let sideways_stop_v : Double = 0.02

///|
/// Flung from where it is at `now`: when it stops (slowed below sideways_stop_v, or at an end it reaches first, whole
/// ms) and where.
fn Sideways::fling_from(self : Sideways, now : Double) -> Unit {
  self.t0 = now
  self.x0 = self.x
  self.v0 = self.vel
  let v = self.v0.abs()
  if v <= sideways_stop_v {
    self.rest = -1.0
    self.vel = 0.0
    return
  }
  let lf = @math.ln(sideways_friction)
  let t_stop = @math.ln(sideways_stop_v / v) / lf
  // the end it goes to, if it gets there first: f^t = 1 + d ln f / v0
  let bound = if self.v0 > 0.0 { dmax(self.max, 0.0) } else { 0.0 }
  let arg = 1.0 + (bound - self.x0) * lf / self.v0
  let t_hit = if arg > 0.0 { @math.ln(arg) / lf } else { @double.infinity }
  let t_end = if t_hit < t_stop { t_hit } else { t_stop }
  self.rest = now + t_end.ceil()
  self.x_end = if t_hit < t_stop { bound } else { dclamp(fling_at(self.x0, self.v0, t_stop), 0.0, dmax(self.max, 0.0)) }
}

///|
/// A fling, at rest at its end (+inf until its first step: it sets out at the frame after it was let go).
impl Moving for Sideways with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  if self.held {
    -1.0
  } else if self.rest >= 0.0 && self.t0 == @double.infinity {
    @double.infinity
  } else {
    self.rest
  }
}

///|
/// A box at most `max_h` tall whose content, when taller, scrolls up and down inside it (see the file's head); `key`
/// keeps where it is scrolled to. Its id.
pub fn Ctx::capped(
  self : Ctx,
  key : String,
  max_h : Double,
  w? : Size = Fill(1.0),
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  padx? : Double = 0.0,
  pady? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  let id = self.id("\u{1}capped\u{1}" + key)
  let st = self.scroll_state(id, true)
  let mut inner = -1
  let b = self.box(w~, max_h~, bg~, radius~, clip=true, id~, fn() {
    inner = self.box(w=Fill(1.0), ty=-st.x, padx~, pady~, body)
  })
  self.nodes[b].sideways = true
  self.nodes[b].hit = false
  st.box = b
  st.inner = inner
  st.frame = self.frame_no
  b
}

///|
/// How far what the box `key` holds is scrolled sideways (0 at its start).
pub fn Ctx::sideways_at(self : Ctx, key : String) -> Double {
  match sideways.get(self.id("\u{1}sideways\u{1}" + key)) {
    Some(s) => s.x
    None => 0.0
  }
}

///|
/// When the box `key` (Ctx::sideways, or Ctx::capped: `capped`), flung, stops (the frames' clock): -1 when it is not
/// flung, +inf when let go and not set out yet (the next frame). What a test runs to after a swipe on it.
pub fn Ctx::sideways_rest(self : Ctx, key : String, capped? : Bool = false) -> Double {
  let k = if capped { "\u{1}capped\u{1}" } else { "\u{1}sideways\u{1}" }
  match sideways.get(self.id(k + key)) {
    Some(s) => s.rest_at(self.now, self.frame_no)
    None => -1.0
  }
}

///|
/// Once laid out: how far each box built this frame can scroll; the rest forgotten.
fn Ctx::sideways_after_layout(self : Ctx) -> Unit {
  if sideways.is_empty() {
    return
  }
  let gone : Array[Int] = []
  sideways.each(fn(id, st) {
    if st.frame != self.frame_no {
      if !st.held {
        gone.push(id)
      }
      return
    }
    let o = self.nodes[st.box]
    let i = self.nodes[st.inner]
    st.max = if st.vertical { dmax(0.0, i.fh - o.fh) } else { dmax(0.0, i.fw - o.fw) }
    if st.x > st.max {
      st.x = st.max
    }
  })
  for id in gone {
    sideways.remove(id)
  }
}

///|
/// The scroll target under (x, y) that is not a sideways box (what a vertical move on one goes to).
fn outer_scroll(c : Ctx, x : Double, y : Double) -> Int {
  let ids = c.scroll_ids
  let rects = c.scroll_rects
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if !sideways.contains(ids[k]) &&
      x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] {
      return ids[k]
    }
    k = k - 1
  }
  0
}

///|
/// A finger down on a sideways box: it stops, and what it lies in is found (for a move up or down).
fn sideways_down(c : Ctx, id : Int, x : Double, y : Double) -> Unit {
  match sideways.get(id) {
    Some(st) => {
      st.vel = 0.0
      st.rest = -1.0
    }
    None => ()
  }
}

///|
/// The finger moved on sideways box `id`: past the slop sideways first, it drags it; up or down first, the list it lies
/// in takes the press from there (true: handed over, the caller goes on as for a list).
fn sideways_move(c : Ctx, id : Int, x : Double, y : Double) -> Bool {
  guard sideways.get(id) is Some(st) else { return false }
  if c.dragging {
    let d = if st.vertical { y - c.last_y } else { x - c.last_x }
    st.x = dclamp(st.x - d, 0.0, st.max)
    return false
  }
  let dx = x - c.press_x
  let dy = y - c.press_y
  let slop = touch_slop()
  // along its way, past the slop, and it can go that way: its drag (taken: claim.mbt; up or down first, or at its
  // end, the press was the list's)
  let (along, across) = if st.vertical { (dy, dx) } else { (dx, dy) }
  let can = if along < 0.0 { st.x < st.max } else { st.x > 0.0 }
  if along.abs() > slop && along.abs() >= across.abs() && can {
    c.dragging = true
    c.active = 0
    st.held = true
    let past = if along > 0.0 { along - slop } else { along + slop }
    st.x = dclamp(st.x - past, 0.0, st.max)
  }
  false
}

///|
/// Let go of scrolling box `id` after dragging it: flung on at the finger's speed (`vx`, `vy`, px per ms).
fn sideways_up(c : Ctx, id : Int, vx : Double, vy : Double) -> Unit {
  match sideways.get(id) {
    Some(st) => {
      st.held = false
      st.vel = if st.vertical { -vy } else { -vx }
      // said once, as it is let go: it sets out at the next frame, its way solved there (fling_from)
      if st.vel.abs() > sideways_stop_v {
        st.rest = 0.0
        st.t0 = @double.infinity
        c.moving(st.mover, st as &Moving, what="a fling of a box scrolled inside a list")
      }
      // in the motion log (MBUI_MOTION_LOG=1) as let go: where it is, how far it can go
      if sideways_logging() {
        h_log("MOTION \{h_now()} scrolled/\{if st.vertical { "down" } else { "across" }} at=\{st.x} max=\{st.max}")
      }
    }
    None => ()
  }
}

///|
/// The wheel over scrolling box `id`: its part along the box's way moves it while it can go that way (true when it
/// took it).
fn sideways_wheel(id : Int, dx : Double, dy : Double) -> Bool {
  match sideways.get(id) {
    Some(st) => {
      let (along, across) = if st.vertical { (dy, dx) } else { (dx, dy) }
      let can = if along > 0.0 { st.x < st.max } else { st.x > 0.0 }
      if along == 0.0 || along.abs() < across.abs() || !can {
        return false
      }
      st.vel = 0.0
      st.rest = -1.0
      st.x = dclamp(st.x + along, 0.0, st.max)
      true
    }
    None => false
  }
}

///|
let sideways_log : Ref[Int] = { val: -1 }

///|
fn sideways_logging() -> Bool {
  if sideways_log.val < 0 {
    sideways_log.val = match fake.val {
      Some(_) => 0
      None => if @host.env("MBUI_MOTION_LOG") == "1" { 1 } else { 0 }
    }
  }
  sideways_log.val == 1
}
