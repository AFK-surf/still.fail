// What a finger holds for its menu, lifted toward it (iOS's context menu; docs/motion.md kind 7, a control answering:
// held, its menu open): a little as it is held, all the way once its menu opens, back down as the menu goes. Lifted,
// it is drawn over the menu's scrim and under the menu (put_over's 3), so that what the menu is of stands out of what
// it dims; a sheet coming up over where it is, it goes up before it, clear of it, and back down with it as it goes.
// A chat's row (sfpages chat_row.mbt) and a message's picture (message_files.mbt) are.

///|
/// How far `key`'s thing is lifted this frame (0 … 1): `held` by a finger a while, `open` its menu up.
pub fn lift_of(c : @ui.Ctx, key : String, held : Bool, open : Bool) -> Double {
  @motion.animate(
    c,
    "lift/" + key,
    if open {
      1.0
    } else if held {
      lift_held
    } else {
      0.0
    },
    spec=lift_spring,
  )
}

///|
/// Node `i` (`key`'s) lifted `lift` of the way (lift_of), drawn `scale` times as large all the way up: over the scrim
/// of the menu up and under it, clear of the sheet the menu is in.
pub fn lift_over(c : @ui.Ctx, i : Int, key : String, lift : Double, scale : Double) -> Unit {
  if lift == 0.0 {
    return
  }
  c.look(i, @ui.look(scale=1.0 + (scale - 1.0) * lift))
  c.put_over(i, z=3)
  // (where the sheet is this frame, as it comes and goes: read once the frame is laid out, the same frame)
  let at = "lifted/" + key
  @motion.measure(c, i, at)
  @motion.placed(c, i, fn() {
    match (@kit.sheet_top(c), @motion.measured_rect(c, at)) {
      (Some(top), Some((_, y, _, h))) if y + h + lift_clear > top =>
        { ..@ui.still_look, dy: top - lift_clear - (y + h) }
      _ => @ui.still_look
    }
  })
}

///|
/// How far it lifts while it is held (of all the way, its menu open), on a spring with a little give.
pub let lift_held : Double = 0.35

///|
// kept across runs: a value (no field of it changes)
let lift_spring : @motion.Spec = @motion.motion_spring(0.32, bounce=0.28)

///|
/// How far over a sheet coming up over it what is lifted stays.
let lift_clear : Double = 12.0
