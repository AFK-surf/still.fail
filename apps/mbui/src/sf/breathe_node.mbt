// What waits breathing (breathe's) as a node of the window's tree: whole to `low` and back in breath_ms, each way on
// CSS's ease-in-out, read as it is drawn by the clock's cycle (View::cycle, from moment 0 on, as Ctx::cycle_look's).
// What stops waiting takes it back to whole over dur_ms (eased out) from the moment it stops, its share of the breath
// going to none; at that way's declared end (a moment of the timeline: View::at_moment) the clock is no longer read, so
// nothing asks a frame of it once it is whole.

///|
/// Node `v` breathing (breathe's, as a node: its opacity) while `waits` says so (as it changes): whole to `low` and back
/// in breath_ms; what stops waiting, back to whole over dur_ms from the moment it stops, its breath not read again once
/// it is there; waiting again, its breath back over dur_ms. Still and whole while `failed` says so (the red words over
/// it say why).
#callsite(autofill(loc))
pub fn breathe_node(
  v : @view.View,
  waits? : () -> Bool = fn() { true },
  low? : Double = 0.5,
  failed? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  let first = @signals.untracked(waits)
  // (how much of its breath it takes, 0 … 1: breathe's `share`)
  let share = EdgeWay::new(if first { 1.0 } else { 0.0 })
  // (whole and at rest: none of its breath taken, its way there over; nothing of the clock read)
  let whole = @signals.signal(!first)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(waits, fn(w) {
    // (as it is when said, and told again as it was: nothing to set off)
    guard share.target() != (if w { 1.0 } else { 0.0 }) else { return }
    (due.val)()
    due.val = fn() {  }
    if w {
      whole.set(false)
      share.go(v, 1.0, dur_ms, ease=Out)
    } else {
      share.go(v, 0.0, dur_ms, ease=Out)
      due.val = v.at_moment(share.end(), fn() { whole.set(true) })
    }
  })
  v.alpha(
    By(fn() {
      if failed() || whole.get() {
        1.0
      } else {
        let f = v.cycle(breath_ms)
        let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
        1.0 - (1.0 - low) * dmax(0.0, share.shown(v)) * @ui.Ease::InOut.at(way)
      }
    }),
    loc~,
  )
  |> ignore
}
