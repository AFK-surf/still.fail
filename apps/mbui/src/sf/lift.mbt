// What a finger holds for its menu, lifted toward it (iOS's context menu; sf/motion.mbt kind 7, a control answering:
// held, its menu open): a little as it is held, all the way once its menu opens, back down as the menu goes. Lifted,
// it is drawn over the menu's scrim and under the menu (Stratum's OverScrim), so that what the menu is of stands out of what
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
  c.stratum(i, OverScrim)
  // (where the sheet is this frame, as it comes and goes: read once the frame is laid out, the same frame)
  let at = "lifted/" + key
  @motion.measure(c, i, at)
  @motion.placed(c, i, fn() {
    match (@kit.sheet_top(c), @motion.measured_rect(c, at)) {
      (Some(top), Some((_, y, _, h))) if y + h + lift_clear > top => {
        // no further than the sheet has come up into the window: what hangs past the window's foot is not thrown up
        // as the sheet starts out from under it, nor dropped back as it goes
        let (_, total) = c.window_size()
        let dy = dmin(0.0, dmax(top - lift_clear - (y + h), top - total))
        { ..@ui.still_look, dy }
      }
      _ => @ui.still_look
    }
  })
}

///|
/// How far it lifts while it is held (of all the way, its menu open), on a spring with a little give.
pub let lift_held : Double = 0.35

///|
// kept across runs: a value (no field of it changes)
let lift_spring : @motion.Spec = @motion.lift_spring

///|
/// How far over a sheet coming up over it what is lifted stays.
let lift_clear : Double = 12.0

///|
/// What of the window's tree is lifted over the scrim (View::over_scrim: a chat's row) kept clear of the sheet up, as
/// lift_over keeps an old view's, and clear of it all the way once it is up (where it is and how tall).
fn init {
  @ui.over_scrim_floor.val = fn(c) { @kit.sheet_place(c) }
}
