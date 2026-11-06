// The retained panel owns its body. An old view embedded as a small island can opt into the old drawing-time panel
// context for that island alone; none of the globals escape its callback.

///|
priv struct PanelOldInfo {
  look : Look
  column : Bool
  column_in : Double
  dialog : Bool
  whole : Bool
  clear : () -> Double
  held : () -> Bool
  side : () -> @ui.Side
}

///|
// kept across runs: lent to each panel body for its lifetime
let panel_old_at : @view.Lent[() -> PanelOldInfo] = @view.Lent::new()

///|
// kept across runs: lent to each panel body for its lifetime
let panel_width_at : @view.Lent[() -> Double] = @view.Lent::new()

///|
/// The width of the presenter that contains `v`, before its body padding, in logical pixels. This follows window
/// changes in a binding. Outside a panel it is the window width.
pub fn panel_width_node(v : @view.View) -> Double {
  match v.lent(panel_width_at) {
    Some(width) => width()
    None => v.window().0
  }
}

///|
/// Draw a single legacy island inside a retained panel body with the old panel's scoped layout context. Call this
/// from that island's `@ui.old` callback, passing its retained parent; do not wrap the entire panel body. Outside a
/// retained panel this calls `body` unchanged. Values are restored after the callback, including for nested islands.
pub fn panel_old_context(v : @view.View, body : () -> Unit) -> Unit {
  guard v.lent(panel_old_at) is Some(read) else { body(); return }
  let info = read()
  let at = panel_row_context(v)
  let old_geometry = (panel_sides_in.val, rows_out.val, words_in_now.val, small_panel_now.val)
  let old_column = (column_given.val, column_in_now.val, in_dialog.val, untitled_clear_now.val)
  let old_other = (panel_body_now.val, panel_whole_now.val, panel_held_now.val, beside_given.val, title_row_given.val)
  let drawing_was = presenter_drawing_now.val
  panel_sides_in.val = at.sides_in
  rows_out.val = at.rows_out
  words_in_now.val = at.words_in
  small_panel_now.val = at.small
  column_given.val = info.column
  column_in_now.val = info.column_in
  in_dialog.val = info.dialog
  untitled_clear_now.val = (info.clear)()
  panel_body_now.val = old_other.0 + 1
  panel_whole_now.val = old_other.1 + (if info.whole { 1 } else { 0 })
  panel_held_now.val = (info.held)()
  beside_given.val = { ..old_other.3, side: (info.side)() }
  title_row_given.val = panel_title_row_given_node(v)
  presenter_drawing_now.val = v.tree.stack_of(v.id())
  with_look(info.look, body)
  panel_sides_in.val = old_geometry.0
  rows_out.val = old_geometry.1
  words_in_now.val = old_geometry.2
  small_panel_now.val = old_geometry.3
  column_given.val = old_column.0
  column_in_now.val = old_column.1
  in_dialog.val = old_column.2
  untitled_clear_now.val = old_column.3
  panel_body_now.val = old_other.0
  panel_whole_now.val = old_other.1
  panel_held_now.val = old_other.2
  beside_given.val = old_other.3
  title_row_given.val = old_other.4
  presenter_drawing_now.val = drawing_was
}
