// What a finger drags that is not a list or a pager: a sheet by its top, the bottom bar's ball and panel. A box
// given a drag (Ctx::drag_area) takes the presses and drags that land on it as a list would (nothing under it, a
// list behind a sheet, scrolls), and says each frame where the finger has it: pressed, moved past the slop along its
// axis (then it is the drag's, not a tap), let go and how fast. What the drag does is the view's. Lying in a list, or
// holding one, it is as any of them: the press is none of theirs until one's own way moves past the slop first
// (claim.mbt), so a row swiped across a list that scrolls up and down, or a card swiped across over the list in it,
// each takes what goes its way.

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
/// takes it (Drag::take_end); `tapped` when let go without moving (at `x`, `y`), until taken (Drag::take_tap). `hold`:
/// a finger holds it still long_press_ms before it drags it (Ctx::drag_on): `waits` while this press, a finger's, is
/// to, `held` once it has.
pub(all) struct Drag {
  axis : DragAxis
  hold : Bool
  mut waits : Bool
  mut held : Bool
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
}

///|
/// The drag areas drawn, by id.
let drags : Map[Int, Drag] = Map([])

///|
/// Box `id` a drag area along `axis` (see the file's head): the view draws the box itself, with whatever look it has
/// (a clip, rounded corners), as `Ctx::box(id=…)` in this frame; it adds no node. What the finger does with it is
/// `drag_of(id)`'s; where a press lands on it is where that box is drawn (its clip and its corners). A frame that says
/// this but draws no box `id` has no drag area there: nothing to press. Told another axis, it starts anew. With `hold`,
/// a finger drags it only once held still on it long_press_ms (iOS's and Android's long press before a drag: a thin
/// thing in reach of what is swiped or scrolled past it, a column's edge): the hold takes the press, felt, and it moves
/// with the finger from there; one that moves past the slop before is not its (what else is under it takes it, or
/// nothing moves), and a press let go sooner is its tap. A mouse drags it as any.
pub fn Ctx::drag_on(
  self : Ctx,
  id : Int,
  axis? : DragAxis = Vertical,
  hold? : Bool = false,
) -> Unit {
  match drags.get(id) {
    Some(d) if d.axis.same(axis) && d.hold == hold => ()
    _ => {
      drags[id] = {
        axis,
        hold,
        waits: false,
        held: false,
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
      }
      self.own(id)
    }
  }
}

///|
/// A box that takes the drags landing on it (Ctx::drag_on over a box of its own), as `Ctx::box` otherwise lays out
/// what it holds; what the finger does with it is `drag_of(id)`'s. Its id is a hit target as well, so a tap on it is
/// `clicked`.
pub fn Ctx::drag_area(
  self : Ctx,
  id : Int,
  axis? : DragAxis = Vertical,
  w? : Size = Auto,
  h? : Size = Auto,
  ty? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  self.drag_on(id, axis~)
  self.box(w~, h~, ty~, id~, body)
}

///|
/// The drag of area `id` as it is now (None: no such area drawn). One a finger is to hold first (Ctx::drag_on's
/// `hold`), pressed and still: held long_press_ms since the press went down, the press is its from here (the others
/// under it let it go, no tap), felt, moving; before then, a frame asked for when it will have been.
pub fn Ctx::drag_of(self : Ctx, id : Int) -> Drag? {
  match drags.get(id) {
    Some(d) => {
      // (read so: the press and, while it is on it, where the pointer is: hand.mbt)
      hand.down.get() |> ignore
      if d.down {
        hand.pointer.get() |> ignore
      }
      if d.down && holds_first(d) && self.down && self.press_at >= 0.0 {
        // (a moment: the frame at it woken, wake_in)
        let held = self.clock - self.press_at
        if held >= long_press_ms {
          d.held = true
          d.moving = true
          self.claimed = true
          self.drag_scroll = id
          for other in self.press_chain {
            if other != id {
              drag_cancel(other)
            }
          }
          self.active = 0
          self.dragging = true
          self.edge = 0
          haptic(LongPress)
        } else {
          self.wake_in(long_press_ms - held)
        }
      }
      Some(d)
    }
    None => None
  }
}

///|
/// Whether a press going down now is to hold drag area `d` still before it drags it (Ctx::drag_on's `hold`, a
/// finger's): what this press is, as it goes down, before anything of the one before is let go (drag_down sets it so).
fn waits_held(d : Drag) -> Bool {
  d.hold && pointing() is Finger
}

///|
/// Whether a finger is yet to hold drag area `d` still before it drags it (Ctx::drag_on's `hold`): not its press till
/// then.
fn holds_first(d : Drag) -> Bool {
  d.waits && !d.held
}

///|
/// The finger moved past hold_slop from where it went down before it held a drag area that is to be held first: the
/// press is not that area's (no tap of it, no drag).
fn hold_moved_off(id : Int, x : Double, y : Double) -> Unit {
  match drags.get(id) {
    Some(d) if d.down && holds_first(d) =>
      if ((x - d.x0) * (x - d.x0) + (y - d.y0) * (y - d.y0)).sqrt() > hold_slop {
        drag_cancel(id)
      }
    _ => ()
  }
}

///|
/// How far a finger may wander while it holds a drag area still before it drags it (UILongPressGestureRecognizer's
/// allowableMovement, 10): a finger held still is never quite still, and one about to drag sets off a little early;
/// past it the press is what else is under it.
pub let hold_slop : Double = 10.0

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
      // (a finger's as it went down: what the press is, whatever comes after)
      d.waits = waits_held(d)
      d.held = false
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
/// Drag area `id` pressed but the press another's (claim.mbt): let go, no tap, not ended.
fn drag_cancel(id : Int) -> Unit {
  match drags.get(id) {
    Some(d) if d.down => {
      d.down = false
      d.moving = false
      d.tapped = false
      d.ended = false
    }
    _ => ()
  }
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
/// Back (the system's, a back button: Ctx::back) does `f` this frame, before any stack drawn earlier in it or holding
/// it (Ctx::nav: a page's own goes before the stack's): for what lies over the pages or over a page (a sheet, a panel,
/// a step of a page's), which back closes first. No edge swipe comes here.
pub fn Ctx::on_back(self : Ctx, f : () -> Unit) -> Unit {
  self.back_next = Some(fn(kind, _, _, _, _) { if kind == 4 { f() } })
  self.back_node_next = -1
  self.back_island_next = self.island_said()
  self.back_says()
}
