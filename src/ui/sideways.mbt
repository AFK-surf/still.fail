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
  /// flung on (px per ms), slowing; held by a finger
  mut vel : Double
  mut held : Bool
  /// the list (or whatever scrolls) it lies in, found as the finger went down
  mut outer : Int
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
      let s = { vertical, x: 0.0, max: 0.0, vel: 0.0, held: false, outer: 0, box: -1, inner: -1, frame: -1 }
      sideways[id] = s
      s
    }
  }
  if !st.held && st.vel != 0.0 {
    let dt = self.dt
    st.x = st.x + st.vel * dt
    st.vel = st.vel * @math.pow(sideways_friction, dt)
    if st.vel.abs() < 0.02 || st.x <= 0.0 || st.x >= st.max {
      st.vel = 0.0
    }
    self.request_frame()
  }
  st.x = dclamp(st.x, 0.0, dmax(st.max, 0.0))
  st
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
      st.outer = outer_scroll(c, x, y)
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
  // along its way, past the slop, and it can go that way: its drag
  let (along, across) = if st.vertical { (dy, dx) } else { (dx, dy) }
  let can = if along < 0.0 { st.x < st.max } else { st.x > 0.0 }
  if along.abs() > slop && along.abs() >= across.abs() && can {
    c.dragging = true
    c.active = 0
    st.held = true
    let past = if along > 0.0 { along - slop } else { along + slop }
    st.x = dclamp(st.x - past, 0.0, st.max)
    return false
  }
  if along.abs() > slop || across.abs() > slop {
    c.drag_scroll = st.outer
    return true
  }
  false
}

///|
/// Let go of scrolling box `id` after dragging it: flung on at the finger's speed (`vx`, `vy`, px per ms).
fn sideways_up(id : Int, vx : Double, vy : Double) -> Unit {
  match sideways.get(id) {
    Some(st) => {
      st.held = false
      st.vel = if st.vertical { -vy } else { -vx }
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
