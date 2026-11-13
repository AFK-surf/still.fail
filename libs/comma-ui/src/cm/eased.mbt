// A number a part's look moves between as its state changes (how lit it is under the hand, how far a knob has gone):
// on a way of mbui's motion (@motion.Way), from the moment of what changed it, on one of Comma's durations and curves;
// drawn where it is at the moment it is drawn while it goes, where it went once it is there.
// (sf's EdgeWay is the same for still.fail's look: one to share once the parts' ways are mbui's.)

///|
/// One number a look moves: its way, and the end of the way it goes now (a moment of the node's timeline, what reads it
/// told as it is there).
struct Eased {
  way : @motion.Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
}

///|
/// At `v`, still.
pub fn Eased::new(v : Double) -> Eased {
  { way: @motion.Way::new(v), ended: @signals.signal(0), due: fn() {  } }
}

///|
/// Off to `to` over `ms` on Comma's curve `ease` (tokens_made's `ease_*`), `delay` ms after `n`'s cause's moment, from
/// where it is then; its end a moment of `n`'s.
pub fn Eased::go(
  self : Eased,
  n : @view.View,
  to : Double,
  ms : Double,
  ease : (Double, Double, Double, Double),
  delay? : Double = 0.0,
) -> Unit {
  if self.way.target() == to {
    return
  }
  (self.due)()
  self.way.go(to, @motion.tween_to(duration=ms, ease=curve(ease), delay~), at=n.cause_at())
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(self.ended.untracked() + 1) })
  } else {
    fn() {  }
  }
}

///|
/// Where it is as `n` is drawn: at the moment it is drawn at while it goes, where it went once it is there.
pub fn Eased::shown(self : Eased, n : @view.View) -> Double {
  self.ended.get() |> ignore
  self.way.shown_on(n)
}

///|
/// A look that moves with what `on` says, 1 while it holds and 0 while not, over `ms` on `ease` from the moment it
/// changed: made in `n`, let go with it.
pub fn eased_by(n : @view.View, on : () -> Bool, ms : Double, ease : (Double, Double, Double, Double)) -> Eased {
  let e = Eased::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
  n.reacts(on, fn(now) { e.go(n, if now { 1.0 } else { 0.0 }, ms, ease) })
  e
}
