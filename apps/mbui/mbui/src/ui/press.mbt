// The finger as each frame sees it (Ctx::press): whether it went down or was let go since the frame before, where it
// went down and in which frame (the press's name), whether it has moved past the slop since, whether it was held there
// still for a long press's time. What an app works out of a press of its own (a press outside a field lets the
// keyboard go; a menu a press opened is not opened again by it; a held word picked), the same in every build of the
// frame and for every app: the framework's own presses are its claims (claim.mbt) and its taps (Ctx::clicked).

///|
/// A press as a frame saw it. `fresh`: it went down since the frame before (a frame saw it up, this one down); `lifted`:
/// let go since; `x`, `y`: where it went down; `frame`: the frame that first saw it down (its name: what it opened is
/// not opened again by it); `moved`: past the slop (8) since; `long`: held still there for long_press_ms (what these
/// two say kept until the next press: a long press let go is no tap); `mods`: the keys held as it went down (mod_cmd,
/// mod_alt…: a press with ⌘ held is the desktop's other press), whatever is held or let go of after.
pub(all) struct Press {
  down : Bool
  fresh : Bool
  lifted : Bool
  x : Double
  y : Double
  frame : Int
  moved : Bool
  long : Bool
  mods : Int
} derive(Eq, Show, Debug)

///|
/// No press yet.
// kept across runs: a value (no field of it changes)
let no_press : Press = {
  down: false,
  fresh: false,
  lifted: false,
  x: 0.0,
  y: 0.0,
  frame: 0,
  moved: false,
  long: false,
  mods: 0,
}

///|
/// How far a finger goes before a press has moved (what Android's views take as a touch's slop, at 8).
pub let press_slop : Double = 8.0

///|
/// The press as this frame sees it, worked out as the frame starts (every build of the frame sees the same). A tap down
/// and up between two frames (no frame saw it down) is a press of its own: not moved, not long. While the finger is
/// down and still, the frame at which it will have been held long is woken.
pub fn Ctx::press(self : Ctx) -> Press {
  // (read so: what reads it is built again as the press goes down, goes past the slop while it is down, is let go, or a
  // tap comes: hand.mbt; not as it moves within it or past it)
  hand.down.get() |> ignore
  hand_presses_read()
  hand.beyond.get() |> ignore
  if self.press_seen_frame == self.frame_no {
    return self.press_seen
  }
  self.press_seen_frame = self.frame_no
  let (px, py, down) = (self.px, self.py, self.down)
  let was = self.press_seen
  let fresh = down && !self.press_was_down
  let lifted = !down && self.press_was_down
  let mut p = { ..was, down, fresh, lifted }
  if fresh {
    p = { ..p, x: px, y: py, frame: self.frame_no, moved: false, long: false, mods: self.press_mods }
    self.press_seen_at = self.clock
  }
  // (a tap down and up between two frames: a press of its own, not the long one before it, gone down and let go there)
  if !down && !self.press_was_down {
    match self.tapped {
      Some((tx, ty)) => {
        p = { ..p, fresh: true, lifted: true, x: tx, y: ty, frame: self.frame_no, moved: false, long: false, mods: self.press_mods }
        self.press_seen_at = self.clock
      }
      None => ()
    }
  }
  if down && ((px - p.x).abs() > press_slop || (py - p.y).abs() > press_slop) {
    p = { ..p, moved: true }
  }
  if down && !p.moved && !p.long {
    // (a moment: the frame at it woken, wake_in)
    let held = self.clock - (if self.press_at >= 0.0 { self.press_at } else { self.press_seen_at })
    if held >= long_press_ms - held_slack_ms {
      p = { ..p, long: true }
    } else {
      self.wake_in(long_press_ms - held)
    }
  }
  self.press_was_down = down
  self.press_seen = p
  p
}
