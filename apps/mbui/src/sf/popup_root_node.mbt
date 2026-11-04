///|
/// A window layer for a control's popup. It lives with that control, but its available room and clipping are the
/// window's: a menu cannot inherit a row's height, scrolling bounds or layout motion.
pub fn popup_root_node(owner : @view.View) -> @view.View {
  let mut root = owner
  while root.parent() is Some(p) { root = p }
  root.box(fn(layer) { layer.over(Is(true)).over_all(Is(true)) |> ignore }).lives_with(owner)
}
