// A page waiting for something, as nodes, in the same room as waiting_page's old view.

///|
/// The mark, title and lead, then what can be done while waiting. Its words follow their readers.
pub fn waiting_page_node(
  parent : @view.View,
  mark : String,
  title : () -> String,
  lead : () -> String,
  body : (@view.View) -> Unit,
) -> Unit {
  let touch = @signals.untracked(fn() { native_input() is Finger })
  parent.box(fn(room) {
    room.width_share(Is(1.0)).grow(Is(1.0)).lines_up(Is(Some(Middle))) |> ignore
    if touch {
      room.lies_along(Is(Middle)) |> ignore
    } else {
      room.box(fn(top) { top.height(Is(Some(wait_top))) |> ignore }) |> ignore
    }
    room.box(fn(col) {
      col
      .width_share(Is(1.0))
      .padding(Is(if touch { (28.0, 0.0, 28.0, 0.0) } else { (24.0, 0.0, 24.0, 0.0) }))
      .gap(Is(14.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      if !touch { col.max_width(Is(Some(wait_w))) |> ignore }
      icon_node(col, mark, if touch { wait_icon_touch } else { wait_icon }, By(fn() { @ui.tree_theme().color(Fg) })) |> ignore
      words_node(col, title, fn() { if touch { wait_title_touch } else { wait_title } }).words_centered(Is(true)) |> ignore
      words_node(col, lead, fn() { wait_lead }).words_centered(Is(true)) |> ignore
      body(col)
    })
    |> ignore
  })
  |> ignore
}
