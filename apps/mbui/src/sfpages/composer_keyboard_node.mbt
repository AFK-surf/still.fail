// Focus belongs to the active chat, even when navigation keeps two composers alive. A focus request is received as
// a cause; it does not wait for an old frame to rebuild the editor.

///|
fn composer_keyboard_node(
  root : @view.View,
  src : Source,
  spec : () -> ComposerSpec,
  w : Writing,
  field : @view.View,
  active : () -> Bool,
  neighbour : ((Int) -> Unit)?,
) -> Unit {
  let entered = Ref(false)
  root.reacts(fn() {
    (active(), spec().locked, field.takes_input(), composing.wanted.get(), field.focused())
  }, fn(state) {
    let (on, locked, input, wanted, focused) = state
    if !on { entered.val = false; return }
    if locked { return }
    let first = !entered.val
    entered.val = true
    // Entering under a modal still asks for the initial cursor. The field keeps that request for the modal to
    // return to; it never takes the modal's cursor away or repeats the request when the modal later closes.
    if !input {
      if first && !@sf.soft_keyboard() { w.field.focus() }
      return
    }
    if wanted {
      if !focused { w.field.focus() }
      if field.focused() { composing.wanted.set(false) }
    } else if first && !@sf.soft_keyboard() && !@ui.current().field_focused() {
      w.field.focus()
    }
  })
  root.on_key(fn(k) {
    if !active() || spec().locked || !field.takes_input() { return false }
    if !@ui.current().field_focused() {
      let prefs = (src.topic)("prefs", {}).value
      match @settings.binding_of(k.code, k.mods) {
        Some(key) if @settings.keys_of(prefs, "composer.focus").contains(key) => {
          w.field.focus()
          return true
        }
        _ => ()
      }
    }
    false
  }) |> ignore
}

///|
fn composer_input_key(
  src : Source,
  spec : () -> ComposerSpec,
  w : Writing,
  active : () -> Bool,
  neighbour : ((Int) -> Unit)?,
  code : Int,
  mods : Int,
) -> Bool {
    if !active() || spec().locked { return false }
    if mods == 0 && w.text.get() == "" && !(@sfbase.neighbour_held.val)() && @sfbase.refs_at(w.key) is None {
      let by = if code == @ui.key_code_up { -1 } else if code == @ui.key_code_down { 1 } else { 0 }
      if by != 0 {
        match neighbour {
          Some(go) => go(by)
          None => match @sfbase.workspace_in_view(src).0 {
            Some(ws) => (@sfbase.neighbour_go.val)(src, ws, by)
            None => return false
          }
        }
        return true
      }
    }
    false
}
