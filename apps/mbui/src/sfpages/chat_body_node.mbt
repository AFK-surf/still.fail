// The chat's list and editor are measured by their common parent. The editor's measured height is a local layout
// result, never a signal which changes the list after that same layout has already finished.

///|
pub fn chat_body_layout(
  body : @view.View,
  list : @view.View,
  composer : @view.View,
  made : () -> ChatComposerNode?,
  tabletop? : () -> (Double, Double)? = fn() { None },
  recent? : @view.View,
) -> Unit {
  body.layout_box(By(fn() {
    let editor = made().map(fn(n) {
      let (base, side, place, limits, change) = (n.layout_room)()
      (n.root.id(), n.composer.cap.id(), base, side, place, limits, change)
    })
    (editor, tabletop())
  }), fn(l, state) {
    let size = l.measure(composer, l.width)
    let room = match state.0 {
      Some((root_id, cap_id, base, side, place, limits, change)) => {
        let p = match limits { Some(limits) => limits.in_width(l.width).2; None => place }
        let least = base + @sf.capsule_in(p.corner, side)
        let total = body.tree.view_of(root_id).map(fn(n) { n.laid_size().1 }).unwrap_or(0.0)
        let cap = body.tree.view_of(cap_id).map(fn(n) { n.laid_size().1 }).unwrap_or(0.0)
        dmax(total + change, total - cap + least)
      }
      None => 0.0
    }
    let height = dmax(0.0, l.height - room)
    let (list_height, composer_y) = match state.1 {
      Some((top, foot)) => (dmin(height, dmax(0.0, top)), dmax(0.0, dmin(foot, height)))
      None => (height, l.height - size.1)
    }
    l.measure(list, l.width, height=list_height) |> ignore
    l.place(list, 0.0, 0.0)
    l.place(composer, 0.0, composer_y)
    match (recent, state.1) {
      (Some(recent), Some(_)) => {
        let top = composer_y + size.1
        l.measure(recent, l.width, height=dmax(0.0, l.height - top)) |> ignore
        l.place(recent, 0.0, top)
      }
      _ => ()
    }
  }) |> ignore
}
