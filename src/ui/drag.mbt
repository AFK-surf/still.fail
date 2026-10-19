// What a finger drags that is not a list or a pager: a sheet by its top, the bottom bar's ball and panel. A box
// given a drag (Ctx::drag_area) takes the presses and drags that land on it as a list would (nothing under it, a
// list behind a sheet, scrolls), and says each frame where the finger has it: pressed, moved past the slop along its
// axis (then it is the drag's, not a tap), let go and how fast. What the drag does is the view's. One `in_list` (a row
// swiped away across a list that scrolls up and down) is the finger's only if it moves along its axis first: moved
// the other way first, the list it lies in takes the press from there, as a sideways box hands it on (sideways.mbt).

///|
/// A drag's axis: what it waits for before it is the finger's. `Hold` takes the press and nothing moves it (a scrim,
/// a sheet's body over a page: drags on it go nowhere).
pub(all) enum DragAxis {
  Hold
  Vertical
  Horizontal
  Free
}

///|
fn DragAxis::same(self : DragAxis, other : DragAxis) -> Bool {
  match (self, other) {
    (Hold, Hold) | (Vertical, Vertical) | (Horizontal, Horizontal) | (Free, Free) => true
    _ => false
  }
}

///|
/// Where a finger has a drag area: `down` while pressed on it; `moving` once it went past the slop along the axis (from
/// then on it is the drag's: no tap); `x0`, `y0` where it went down, `x`, `y` where it is (in the window), `dx`, `dy`
/// since the last frame's look; `ended` once let go after moving (its speed `vx`, `vy`, px per ms), until the view
/// takes it (Drag::take_end); `tapped` when let go without moving (at `x`, `y`), until taken (Drag::take_tap).
pub(all) struct Drag {
  axis : DragAxis
  mut down : Bool
  mut moving : Bool
  mut x0 : Double
  mut y0 : Double
  mut x : Double
  mut y : Double
  mut dx : Double
  mut dy : Double
  mut vx : Double
  mut vy : Double
  mut ended : Bool
  mut tapped : Bool
  /// it hands a move the other way first to what it lies in (Ctx::drag_area `in_list`), found as the finger went down
  in_list : Bool
  mut outer : Int
}

///|
/// The drag areas drawn, by id.
let drags : Map[Int, Drag] = Map([])

///|
/// A box that takes the drags landing on it (see the file's head), as `Ctx::box` otherwise lays out what it holds;
/// what the finger does with it is `drag_of(id)`'s. Its id is a hit target as well, so a tap on it is `clicked`.
pub fn Ctx::drag_area(
  self : Ctx,
  id : Int,
  axis? : DragAxis = Vertical,
  w? : Size = Auto,
  h? : Size = Auto,
  ty? : Double = 0.0,
  in_list? : Bool = false,
  body : () -> Unit,
) -> Int {
  match drags.get(id) {
    Some(d) if d.axis.same(axis) && d.in_list == in_list => ()
    _ => {
      drags[id] = {
        axis,
        down: false,
        moving: false,
        x0: 0.0,
        y0: 0.0,
        x: 0.0,
        y: 0.0,
        dx: 0.0,
        dy: 0.0,
        vx: 0.0,
        vy: 0.0,
        ended: false,
        tapped: false,
        in_list,
        outer: 0,
      }
      self.own(id)
    }
  }
  self.box(w~, h~, ty~, id~, body)
}

///|
/// The drag of area `id` as it is now (None: no such area drawn).
pub fn Ctx::drag_of(self : Ctx, id : Int) -> Drag? {
  ignore(self)
  drags.get(id)
}

///|
/// How far the finger moved it since this was last asked (dx, dy), then none until it moves again.
pub fn Drag::take_move(self : Drag) -> (Double, Double) {
  let m = (self.dx, self.dy)
  self.dx = 0.0
  self.dy = 0.0
  m
}

///|
/// Whether it was let go after moving (once: taken).
pub fn Drag::take_end(self : Drag) -> Bool {
  let e = self.ended
  self.ended = false
  e
}

///|
/// Whether it was let go without moving, a tap (once: taken).
pub fn Drag::take_tap(self : Drag) -> Bool {
  let e = self.tapped
  self.tapped = false
  e
}

///|
/// A press landing on drag area `id` (on_pointer's down): it is the finger's from here.
fn drag_down(id : Int, x : Double, y : Double) -> Bool {
  match drags.get(id) {
    Some(d) => {
      d.down = true
      d.moving = false
      d.x0 = x
      d.y0 = y
      d.x = x
      d.y = y
      d.dx = 0.0
      d.dy = 0.0
      d.vx = 0.0
      d.vy = 0.0
      d.ended = false
      d.tapped = false
      true
    }
    None => false
  }
}

///|
/// A press landing on drag area `id` that lies in a list (`in_list`): what scrolls under it, for a move the other way.
fn drag_find_outer(c : Ctx, id : Int, x : Double, y : Double) -> Unit {
  guard drags.get(id) is Some(d) && d.in_list else { return }
  d.outer = 0
  let ids = c.scroll_ids
  let rects = c.scroll_rects
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if ids[k] != id &&
      !drags.contains(ids[k]) &&
      !sideways.contains(ids[k]) &&
      x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] {
      d.outer = ids[k]
      return
    }
    k = k - 1
  }
}

///|
/// The finger moved on drag area `id` lying in a list, not yet its drag: moved past the slop the other way first, the
/// list takes the press from here (true: handed over, the caller goes on as for a list; the area is let go, no tap).
fn drag_yield(c : Ctx, id : Int, x : Double, y : Double) -> Bool {
  guard drags.get(id) is Some(d) && d.in_list && d.down && !d.moving && d.outer != 0 else { return false }
  let (along, across) = match d.axis {
    Horizontal => ((x - d.x0).abs(), (y - d.y0).abs())
    Vertical => ((y - d.y0).abs(), (x - d.x0).abs())
    _ => return false
  }
  if across > touch_slop() && across > along {
    d.down = false
    c.drag_scroll = d.outer
    return true
  }
  false
}

///|
/// The finger moved on drag area `id`: true once it is past the slop along the axis (a drag, no longer a tap).
fn drag_move(id : Int, x : Double, y : Double) -> Bool {
  match drags.get(id) {
    Some(d) if d.down => {
      if !d.moving {
        let along = match d.axis {
          Hold => 0.0
          Vertical => (y - d.y0).abs()
          Horizontal => (x - d.x0).abs()
          Free => ((x - d.x0) * (x - d.x0) + (y - d.y0) * (y - d.y0)).sqrt()
        }
        if !d.axis.same(Hold) && along > touch_slop() {
          d.moving = true
        }
      }
      if d.moving {
        d.dx = d.dx + (x - d.x)
        d.dy = d.dy + (y - d.y)
      }
      d.x = x
      d.y = y
      d.moving
    }
    _ => false
  }
}

///|
/// Let go on drag area `id` (or called off: `cancel`, no tap and no speed).
fn drag_up(id : Int, x : Double, y : Double, vx : Double, vy : Double, cancel : Bool) -> Unit {
  match drags.get(id) {
    Some(d) if d.down => {
      d.down = false
      d.x = x
      d.y = y
      if d.moving {
        d.vx = vx
        d.vy = vy
        d.ended = true
      } else {
        d.tapped = !cancel
      }
      d.moving = false
    }
    _ => ()
  }
}

///|
/// How long since the last frame (ms): for what steps its own motion a frame at a time (springs a view keeps).
pub fn Ctx::frame_dt(self : Ctx) -> Double {
  self.dt
}

///|
/// Back (the system's, a back button: Ctx::back) does `f` this frame, before any stack drawn earlier in it: for what
/// lies over the pages (a sheet, a panel), which back closes first. No edge swipe comes here.
pub fn Ctx::on_back(self : Ctx, f : () -> Unit) -> Unit {
  self.back_next = Some(fn(kind, _, _, _) { if kind == 4 { f() } })
  self.back_node_next = -1
}
