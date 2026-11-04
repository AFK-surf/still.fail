// The field's hint does not travel with its box. Causes hide it immediately; its declared shape/flight end lets
// it come back. The clock is read only while drawing the fade, with one scheduled end to stop following it.

///|
fn composer_hint_node(
  owner : @view.View,
  draft : String,
  hidden : () -> Bool,
  shape : () -> String,
) -> (() -> Double, () -> Double) {
  let away = @signals.signal(false)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  owner.reacts(fn() { @sfbase.flight_hint_due(draft) }, fn(until) {
    (due.val)()
    let now = owner.cause_at()
    away.set(until is Some(at) && (at < 0.0 || at > now))
    match until {
      Some(at) if at > now => due.val = owner.at_moment(at, fn() { away.set(false) })
      _ => due.val = fn() {  }
    }
  })
  let hint = @motion.Way::new(if @signals.untracked(fn() { hidden() || away.get() }) { 0.0 } else { 1.0 })
  let first = Ref(true)
  let before = Ref("")
  owner.reacts(fn() { (hidden() || away.get(), shape()) }, fn(state) {
    let (off, next) = state
    let reshaped = !first.val && next != before.val
    first.val = false
    before.val = next
    if off {
      hint.put(0.0)
    } else if reshaped {
      hint.put(0.0)
      hint.go(1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay=composer_shape_ms), at=owner.cause_at())
    } else if hint.target() != 1.0 {
      hint.go(1.0, @motion.tween(@sf.hint_back_ms, ease=Out), at=owner.cause_at())
    }
  })
  owner.owns(fn() { (due.val)() }) |> ignore
  (fn() {
    hint.said()
    hint.value_at(if owner.drawn_past(hint.end()) { hint.end() } else { owner.drawn_at() })
  }, fn() { if away.get() { 0.0 } else { 1.0 } })
}

///|
/// Visible hints exchange through a fade. When the cursor hides the hint there is nothing to fade out: its
/// words, including the field's accessible name, change with the focus that changed their meaning.
fn composer_hint_words_node(owner : @view.View, wanted : () -> String, hidden : () -> Bool) -> (() -> String, () -> Double) {
  let said = @signals.signal(@signals.untracked(wanted))
  let fade = @motion.Way::new(1.0)
  let made_in = @ui.current().frame_number()
  let due : Ref[() -> Unit] = Ref(fn() {  })
  owner.reacts(fn() { (wanted(), hidden()) }, fn(state) {
    let (next, off) = state
    (due.val)()
    let now = owner.cause_at()
    if off || @ui.current().frame_number() == made_in || owner.tree.drawn_of(owner.id()) is None {
      // Focus may be handed to the editor while its first frame is still being made. Nothing of the previous
      // phrase was shown, even if layout already gives drawn_of a box. There is no previous phrase to fade out.
      said.set(next)
      fade.put(1.0)
    } else if next == said.get() {
      if fade.target() != 1.0 { fade.go(1.0, @motion.tween(@sf.hint_back_ms, ease=Out), at=now) }
    } else {
      fade.go(0.0, @motion.tween(@sf.hint_back_ms, ease=Leave), at=now)
      let at = fade.end()
      due.val = owner.at_moment(at, fn() {
        said.set(next)
        fade.go(1.0, @motion.tween(@sf.hint_back_ms, ease=Out), at~)
      })
    }
  })
  owner.owns(fn() { (due.val)() }) |> ignore
  (fn() { said.get() }, fn() {
    fade.said()
    fade.value_at(if owner.drawn_past(fade.end()) { fade.end() } else { owner.drawn_at() })
  })
}
