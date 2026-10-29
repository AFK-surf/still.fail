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
  /// this build's box and what it holds (node indices: a frame built again, its last build's), for their widths once
  /// laid out; the build (Ctx::build_number)
  mut box : Int
  mut inner : Int
  mut frame : Int
  /// one box of several built as one (`across`: a long text's rows in a list): the others built this frame
  others : Array[(Int, Int)]
  /// the boxes are one across rows: how far it can go only grows while it is kept (rows out of view say nothing)
  mut across : Bool
  /// what it was last sent to its end for (Ctx::sideways's `to_end`), and whether it is to go there once laid out
  mut end_for : String
  mut to_end : Bool
  /// the part last asked to be in view (Ctx::sideways's `show`, an id: Ctx::show as it becomes another)
  mut show_last : Int
  /// its scroll bar (scroll_bar.mbt), when it last scrolled, and the theme it was built in (its bar's colour)
  bar : Bar
  mut last_scroll : Double
  mut theme : Theme
  /// the frame it was last built in (one not built is shown by nothing: at rest)
  mut built_frame : Int
  /// a field's words, more lines than it shows (Ctx::editor): how far it can go is its layout's (layout.mbt), not boxes'
  mut field : Bool
  /// built with room at its foot for its bar (Ctx::sideways: as it could scroll when last laid out)
  mut bar_room : Bool
  /// how far in from either side its bar runs (Ctx::sideways's `bar_in`)
  mut bar_in : Double
}

///|
let sideways : Map[Int, Sideways] = {}

///|
/// How a fling slows: as the desktop's coasting (0.997 a ms; scroll.mbt), a little firmer on a phone's short rows.
let sideways_friction : Double = 0.996

///|
/// A box (as wide as `w`) whose content is laid out as wide as it is and scrolled sideways inside it (see the file's
/// head). `key` keeps where it is scrolled to from frame to frame. `across`: the boxes of `key` in any scope (a long
/// text's rows in a list, each its own row) are one: scrolled together, as far as the widest of them seen. `to_end`:
/// sent to its end once laid out whenever this changes (a path's end in view as it goes deeper, as Compose's
/// scrollTo(maxValue)). `fill`: what it holds at least as wide as the box (what fills it there sharing it: a strip of
/// tabs across it), scrolled only where it needs more. `show`: the part built in it with that id brought into view
/// once laid out whenever it is another (the chosen one of a strip of tabs, as it is first shown and as another is
/// chosen), as little as that takes. `bar_in`: its bar runs that far in from either side, under the view it is for,
/// where what it holds scrolls out past that view (a table out across a chat's margins: under the message's words, not
/// to the screen's edges). Its id, for what is drawn in it.
pub fn Ctx::sideways(
  self : Ctx,
  key : String,
  w? : Size = Fill(1.0),
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  across? : Bool = false,
  to_end? : String = "",
  fill? : Bool = false,
  show? : Int = 0,
  bar_in? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  let id = if across { self.root_id("\u{1}sideways\u{1}" + key) } else { self.id("\u{1}sideways\u{1}" + key) }
  let st = self.scroll_state(id, false)
  st.theme = self.theme
  st.built_frame = self.frame_no
  st.bar_in = bar_in
  let px = if padx >= 0.0 { padx } else { pad }
  let py = if pady >= 0.0 { pady } else { pad }
  // (while what it holds is wider than it (as last laid out: read back), room at its foot for its bar, under what it
  // holds, its own padding there counted: the bar never lies over what it holds (the user, 2026-10-25: a table's bar
  // over its last row). One of several scrolled as one has its bar along their list's foot: none.)
  st.bar_room = !across && st.max > 0.5
  let foot = if st.bar_room { dmax(py, scroll_bar_room) } else { py }
  let mut inner = -1
  let b = self.box(dir=Row, w~, clip=true, id~, fn() {
    self.sideways_depth += 1
    // (filling: as wide as the box where what it holds needs no more, never narrower than that: Ctx::box keep)
    let inner_w = if fill { Some(Fill(1.0)) } else { None }
    inner = self.box(w?=inner_w, keep=fill, tx=-st.x, pl=px, pr=px, pt=py, pb=foot, body)
    self.sideways_depth -= 1
  })
  // where more of it goes on past an edge, what it holds fades out towards that edge (as far as it goes on, a line's
  // worth at most), not cut off there (the user, 2026-10-30: 「现在有很多粗暴裁剪的」)
  self.fade_to(inner, b, start=cut_soft(st.x, st.x), end=cut_soft(st.max - st.x, st.max - st.x))
  self.nodes[b].sideways = true
  // a scroll target (the pointer's), not a tap's
  self.nodes[b].hit = false
  st.across = across
  if to_end != "" && to_end != st.end_for {
    st.end_for = to_end
    st.to_end = true
  }
  if show != 0 && show != st.show_last {
    st.show_last = show
    self.show(show)
  }
  self.sideways_built(st, b, inner)
  row_said_sideways(id, b, inner)
  b
}

///|
/// Box `b` scrolling what `inner` holds, its state `st`, built this build (or put back as built: a list's row or a part
/// kept as its nodes, kept_nodes.mbt): where it is for what works out how far it can go once laid out; one of several
/// scrolled as one, with the others built this build.
fn Ctx::sideways_built(self : Ctx, st : Sideways, b : Int, inner : Int) -> Unit {
  st.built_frame = self.frame_no
  if st.across && st.frame == self.build_no {
    st.others.push((b, inner))
  } else {
    st.box = b
    st.inner = inner
    st.others.clear()
    st.frame = self.build_no
  }
}

///|
/// An id as `key` gives it at the build's root, whatever scope it is asked in.
fn Ctx::root_id(self : Ctx, key : String) -> Int {
  mix(if self.id_stack.is_empty() { self.id_seed } else { self.id_stack[0] }, stable_hash(key).to_int())
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
        others: [],
        across: false,
        end_for: "",
        to_end: false,
        show_last: 0,
        bar: Bar::new(),
        last_scroll: -1.0e9,
        theme: self.theme,
        built_frame: -1,
        field: false,
        bar_room: false,
        bar_in: 0.0,
      }
      sideways[id] = s
      s
    }
  }
  if !st.held && st.rest >= 0.0 {
    if st.t0 == @double.infinity {
      // its first step: it sets out now, its way solved once (where it stops, when)
      st.fling_from(self.clock)
    }
    if self.clock >= st.rest {
      st.x = st.x_end
      // (its bar fades from the fling's end)
      st.last_scroll = dmax(st.last_scroll, st.rest)
      st.rest = -1.0
      st.vel = 0.0
    } else {
      st.x = fling_at(st.x0, st.v0, self.now() - st.t0)
    }
  }
  st.x = dclamp(st.x, 0.0, dmax(st.max, 0.0))
  // (where its fling and its bar have it, read by what is built round it, a part or a row kept: built again as it is
  // told anew, wherever and whenever, and each frame while it moves: Ctx::shows_motion)
  self.shows_motion(st.mover, dmax(st.fling_rest(), st.bar.rest(self.clock, st.bar_until())) > self.clock)
  st
}

///|
/// How far a fling at `v0` (px per ms) has gone `t` ms on, slowing by sideways_friction a ms: solved for the time, the
/// same at any frame rate.
fn fling_at(x0 : Double, v0 : Double, t : Double) -> Double {
  let lf = @dmath.ln(sideways_friction)
  x0 + v0 * (@dmath.pow(sideways_friction, t) - 1.0) / lf
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
  let lf = @dmath.ln(sideways_friction)
  let t_stop = @dmath.ln(sideways_stop_v / v) / lf
  // the end it goes to, if it gets there first: f^t = 1 + d ln f / v0
  let bound = if self.v0 > 0.0 { dmax(self.max, 0.0) } else { 0.0 }
  let arg = 1.0 + (bound - self.x0) * lf / self.v0
  let t_hit = if arg > 0.0 { @dmath.ln(arg) / lf } else { @double.infinity }
  let t_end = if t_hit < t_stop { t_hit } else { t_stop }
  self.rest = now + t_end.ceil()
  self.x_end = if t_hit < t_stop { bound } else { dclamp(fling_at(self.x0, self.v0, t_stop), 0.0, dmax(self.max, 0.0)) }
}

///|
/// A fling's end (+inf until its first step: it sets out at the frame after it was let go; -1 none).
fn Sideways::fling_rest(self : Sideways) -> Double {
  if self.held {
    -1.0
  } else if self.rest >= 0.0 && self.t0 == @double.infinity {
    @double.infinity
  } else {
    self.rest
  }
}

///|
/// Until when it scrolls, its bar shown before it fades: its last scroll, the end of its fling.
fn Sideways::bar_until(self : Sideways) -> Double {
  let flung = self.fling_rest()
  if flung >= 0.0 {
    dmax(self.last_scroll, flung)
  } else {
    self.last_scroll
  }
}

///|
/// A fling, at rest at its end, and its bar, at rest once faded.
impl Moving for Sideways with rest_at(self, now, frame) {
  if self.built_frame != frame {
    return -1.0
  }
  dmax(self.fling_rest(), self.bar.rest(now, self.bar_until()))
}

///|
/// Box `st` scrolled now (a finger, the wheel, its thumb, sent to its end or to a part where it showed): its bar shows
/// (and then fades) from now, said as what moves.
fn Ctx::sideways_scrolled(self : Ctx, st : Sideways) -> Unit {
  st.bar.wake(self.clock, st.bar_until())
  st.last_scroll = self.clock
  self.moving(st.mover, st as &Moving, what="a box scrolled inside a list and its scroll bar")
}

///|
/// The id of the box Ctx::capped makes for `key`: where it is laid out, how tall it shows (Ctx::laid_size), read by
/// what holds it (a dialog: how tall its body shows besides its title and buttons).
pub fn Ctx::capped_id(self : Ctx, key : String) -> Int {
  self.id("\u{1}capped\u{1}" + key)
}

///|
/// A box at most `max_h` tall whose content, when taller, scrolls up and down inside it (see the file's head); `key`
/// keeps where it is scrolled to. `shrinks`: in a column, shorter still when the column has less room left (CSS's
/// flex-shrink on what scrolls: a dialog's body when the dialog would be taller than its maximum). `mx`: its sides that
/// far out from where they would be (out across a panel's padding, negative: what it holds scrolls to the panel's
/// sides, `padx` in from them). Its id.
pub fn Ctx::capped(
  self : Ctx,
  key : String,
  max_h : Double,
  w? : Size = Fill(1.0),
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  padx? : Double = 0.0,
  pady? : Double = 0.0,
  shrinks? : Bool = false,
  mx? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  let id = self.capped_id(key)
  let st = self.scroll_state(id, true)
  st.theme = self.theme
  st.built_frame = self.frame_no
  let mut inner = -1
  let b = self.box(w~, max_h~, mx~, bg~, radius~, clip=true, id~, fn() {
    inner = self.box(w=Fill(1.0), ty=-st.x, padx~, pady~, body)
  })
  // (where more goes on past its top or its foot, fading out towards it: Ctx::sideways)
  self.fade_to(inner, b, top=cut_soft(st.x, st.x), foot=cut_soft(st.max - st.x, st.max - st.x))
  self.nodes[b].sideways = true
  self.nodes[b].shrinks = shrinks
  self.nodes[b].hit = false
  self.sideways_built(st, b, inner)
  row_said_sideways(id, b, inner)
  b
}

///|
/// How far what the box `key` holds is scrolled sideways (0 at its start); `across` as Ctx::sideways's.
pub fn Ctx::sideways_at(self : Ctx, key : String, across? : Bool = false) -> Double {
  match sideways.get(if across { self.root_id("\u{1}sideways\u{1}" + key) } else { self.id("\u{1}sideways\u{1}" + key) }) {
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
    Some(s) => s.fling_rest()
    None => -1.0
  }
}

///|
/// Once laid out: how far each box built this frame can scroll; the rest forgotten.
fn Ctx::sideways_after_layout(self : Ctx) -> Unit {
  if sideways.is_empty() {
    self.shows_after_layout()
    return
  }
  let gone : Array[Int] = []
  sideways.each(fn(id, st) {
    if st.frame != self.build_no {
      // (one in a part or a list's row drawn again, not built, is still there: kept, where it was scrolled to and
      // what a press on it waits for)
      if !st.held && !sideways_kept(id, self.frame_no) {
        gone.push(id)
      }
      return
    }
    if st.field {
      return
    }
    let o = self.nodes[st.box]
    let i = self.nodes[st.inner]
    let mut most = if st.vertical { dmax(0.0, i.fh - o.fh) } else { dmax(0.0, i.fw - o.fw) }
    for bi in st.others {
      most = dmax(most, self.nodes[bi.1].fw - self.nodes[bi.0].fw)
    }
    st.max = if st.across { dmax(st.max, most) } else { most }
    // (come to scroll, or no longer: built again with its bar's room, or without)
    if !st.vertical && !st.across && (st.max > 0.5) != st.bar_room {
      self.read_changed("a sideways box come to scroll or not: its bar's room")
    }
    if st.to_end {
      st.to_end = false
      if st.x != st.max {
        st.x = st.max
        if self.bar_drawn(id) is Some(_) {
          self.sideways_scrolled(st)
        }
        // (built again before this frame goes out: drawn there at once)
        self.read_changed("a sideways box sent to its end")
      }
    }
    if st.x > st.max {
      st.x = st.max
    }
  })
  for id in gone {
    sideways.remove(id)
  }
  self.shows_after_layout()
}

///|
/// What was asked into view (Ctx::show): the id, and the frame it was asked in.
let shows_asked : Array[(Int, Int)] = []

///|
/// What `id` names brought into view once laid out, in every box that scrolls round it (Ctx::capped, Ctx::sideways),
/// the innermost first, each as little as that takes (the web's scrollIntoView, block and inline "nearest"): where
/// the keyboard moves what is chosen (the focus, a menu's option chosen while the focus stays in a field), as it moves
/// it. Asked as the cause comes, not each frame: a box the person scrolled stays where they left it. Not in a list's
/// rows (Ctx::list_scroll_to).
pub fn Ctx::show(self : Ctx, id : Int) -> Unit {
  if id != 0 {
    shows_asked.push((id, self.frame_no))
  }
}

///|
/// Once laid out: what was asked into view (Ctx::show) brought there, scrolled at once (a step of the keys, as a
/// browser's menu: no glide behind each press); one not laid out this frame waits for the next (a menu laid out the
/// frame after the key that opened it), then is forgotten.
fn Ctx::shows_after_layout(self : Ctx) -> Unit {
  if shows_asked.is_empty() {
    return
  }
  // the boxes scrolling this build, by their node: their id and state
  let boxes : Map[Int, (Int, Sideways)] = {}
  sideways.each(fn(id, st) {
    if st.frame == self.build_no && !st.field && st.box >= 0 {
      boxes[st.box] = (id, st)
    }
  })
  let left : Array[(Int, Int)] = []
  for ask in shows_asked {
    let (want, frame) = ask
    let mut k = 0
    while k < self.count && self.nodes[k].id != want {
      k = k + 1
    }
    if k >= self.count {
      if self.frame_no <= frame + 1 {
        left.push(ask)
      }
      continue
    }
    // its rect as laid out (each box's scroll in it already), less how much further the boxes inside the one looked at
    // were scrolled here
    let p = self.nodes[k]
    let mut shift_x = 0.0
    let mut shift_y = 0.0
    let mut a = p.parent
    while a >= 0 && a < self.count {
      match boxes.get(a) {
        Some((sid, st)) => {
          let o = self.nodes[st.box]
          let i = self.nodes[st.inner]
          let (from, size, view) = if st.vertical {
            (p.y - shift_y - i.y, p.fh, o.fh)
          } else {
            (p.x - shift_x - i.x, p.fw, o.fw)
          }
          let to = if from < st.x || size > view {
            from
          } else if from + size > st.x + view {
            from + size - view
          } else {
            st.x
          }
          let to = dclamp(to, 0.0, dmax(st.max, 0.0))
          let moved = to - st.x
          if to != st.x {
            st.x = to
            st.rest = -1.0
            st.vel = 0.0
            if self.bar_drawn(sid) is Some(_) {
              self.sideways_scrolled(st)
            }
            // (built again before this frame goes out: drawn there at once)
            self.read_changed("a part brought into view in a box that scrolls")
          }
          if st.vertical {
            shift_y = shift_y + moved
          } else {
            shift_x = shift_x + moved
          }
        }
        None => ()
      }
      a = self.nodes[a].parent
    }
  }
  shows_asked.clear()
  for ask in left {
    shows_asked.push(ask)
  }
}

///|
/// Whether sideways box `id` is in a part or a list's row shown in `frame`, as its build said what scrolls in it.
fn sideways_kept(id : Int, frame : Int) -> Bool {
  for _, st in kept_rows {
    if st.shown == frame && st.scroll_ids.contains(id) {
      return true
    }
  }
  for _, st in kept_parts {
    if st.shown == frame && st.scroll_ids.contains(id) {
      return true
    }
  }
  false
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
    let was = st.x
    st.x = dclamp(st.x - d, 0.0, st.max)
    if st.x != was {
      c.sideways_scrolled(st)
    }
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
    c.sideways_scrolled(st)
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
      g().sideways_scrolled(st)
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
      None => if @hostapi.env("MBUI_MOTION_LOG") == "1" { 1 } else { 0 }
    }
  }
  sideways_log.val == 1
}
