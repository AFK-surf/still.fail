// The modifier keys currently held over the window. A host tells each change at its input's moment; a Tester gives the
// same input through hold_mods. This is separate from a press's modifiers, which stay as they were at its down.

///|
// kept across runs: reset_globals puts it back
let modifiers_now : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
fn host_modifiers_now() -> Int {
  match fake.val {
    Some(f) => f.mods
    None => @hostapi.mods_held()
  }
}

///|
fn modifiers_said(mods : Int) -> Unit {
  if @signals.untracked(fn() { modifiers_now.get() }) == mods { return }
  modifiers_now.set(mods)
  input_taped("modifiers", h_now(), [mods.to_double()])
}

///|
fn on_modifiers(mods : Int) -> Unit {
  let now = if @signals.untracked(app_focused) { mods } else { 0 }
  if @signals.untracked(fn() { modifiers_now.get() }) == now { return }
  view_event(fn() { modifiers_said(now) })
}
