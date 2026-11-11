// What a finger holds for its menu, lifted toward it (lift_of and lift_over's, as a node of the window's tree): a little
// as it is held, all the way once its menu opens, back down as the menu goes, on lift_spring from the moment each of
// those is told. Lifted, it is drawn over the menu's scrim and under the menu (View::over_scrim), and kept clear of a
// sheet coming up over where it is by what draws the tree (@ui.over_scrim_floor, said by lift.mbt as the app starts):
// nothing of where it is laid out read here.

///|
/// Node `v` lifted while `held` by a finger a while (lift_held of the way) or while `open` says its menu is up (all the
/// way), as each changes: drawn `scale` times as large all the way up, over the scrim of the menu up and under it.
#callsite(autofill(loc))
pub fn lift_node(v : @view.View, held : () -> Bool, open : () -> Bool, scale : Double, loc~ : SourceLoc) -> Unit {
  let lift = EdgeWay::new(0.0)
  // (as lift_of's: past none and back as its spring gives, over the scrim till it is at none)
  let lifted = fn() { lift.shown(v) }
  v.reacts(
    fn() {
      if open() {
        1.0
      } else if held() {
        lift_held
      } else {
        0.0
      }
    },
    fn(to) { lift.go_by(v, to, lift_spring) },
  )
  v.scale(By(fn() { 1.0 + (scale - 1.0) * lifted() }), loc~).over_scrim(By(fn() { lifted() != 0.0 }), loc~) |> ignore
}
