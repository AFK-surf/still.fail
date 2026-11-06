///|
/// A window layer for a control's popup. It lives with that control, but its available room and clipping are the
/// window's: a menu cannot inherit a row's height, scrolling bounds or layout motion. Made as it is asked, in what the
/// window holds: never in a layout (a list's row built as it comes into the list), which lays out nothing of the
/// window's (popup_root_when, popup_root_lazy).
pub fn popup_root_node(owner : @view.View) -> @view.View {
  let mut root = owner
  while root.parent() is Some(p) { root = p }
  root.box(fn(layer) { layer.over(Is(true)).over_all(Is(true)) |> ignore }).lives_with(owner)
}

///|
/// `make` given `owner`'s window layer (popup_root_node) the first time `open` holds, at that moment (the press, the
/// key, the pointer that opened it), kept with `owner` from then: none made for a control whose popup never opens (a
/// list's every row's menu). Open as `owner` is built in a layout (its row made again as the list scrolls), made as that
/// layout is done, before anything is drawn or hit (View::made_after_layout).
pub fn popup_root_when(owner : @view.View, open : () -> Bool, make : (@view.View) -> Unit) -> Unit {
  let made = Ref(false)
  let make_now = fn() {
    if !made.val && owner.alive() {
      made.val = true
      make(popup_root_node(owner))
    }
  }
  owner.reacts(open, fn(on) { if on && !made.val { owner.made_after_layout(make_now) } })
}

///|
/// `owner`'s window layer (popup_root_node), made the first time it is asked (a tip shown as the pointer rests: an
/// event's moment), kept with `owner` from then.
pub fn popup_root_lazy(owner : @view.View) -> () -> @view.View {
  let layer : Ref[@view.View?] = Ref(None)
  fn() {
    match layer.val {
      Some(l) if l.alive() => l
      _ => {
        let l = popup_root_node(owner)
        layer.val = Some(l)
        l
      }
    }
  }
}
