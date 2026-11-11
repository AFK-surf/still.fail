// A row a page lays out itself in a panel's body made of nodes, its words on the panel's words' line (panel_row_in's,
// read where the body is nodes: panel_in_of).

///|
/// What a row node `v` of a panel's body made of nodes lays its words in by (panel_row_in's): in a small panel a row's
/// padding in at its sides and its corner concentric with the panel's (small_panel_row_in's); elsewhere as far in as the
/// panel's words (panel_words_in_node). Its ground under the hand is the row's own (panel_row_in's `hovered`:
/// hovered_node).
pub fn panel_row_in_node(v : @view.View) -> @ui.Style {
  if panel_in_of(v).small {
    small_panel_row_in_node
  } else {
    panel_words_in_node(v)
  }
}

///|
// kept across runs: a value (no field of it changes)
let small_panel_row_in_node : @ui.Style = @ui.style(px=room(text_in), radius=Inner)
