// A row a page lays out itself in a panel's body made of nodes, its words on the panel's words' line (panel_row_in's,
// read where the body is nodes: panel_in_of).

///|
/// What a row node `v` of a panel's body made of nodes lays its words in by (panel_row_in's): in a small panel a row's
/// padding in at its sides and its corner concentric with the panel's (small_panel_row_in's); elsewhere its ground round
/// (row_corner), never a square patch standing in from the panel's sides (the corner rule's lit square, 2026-11-13): on
/// its column's line (a dialog's, a sheet's column: sheet_column_node), out past its words by a corner's inset as far as
/// the panel leaves its rows (rows_out: panel_switch_noted_node's reach), so a tile a small block's corner round stands
/// concentric in it that inset in; else as far in as the panel's words (panel_words_in_node: a sheet's, a panel's
/// list's), round where its column stands in from the panel's sides, square across a sheet whose rows reach its sides. Its
/// ground under the hand is the row's own (panel_row_in's `hovered`: hovered_node).
pub fn panel_row_in_node(v : @view.View) -> @ui.Style {
  let at = panel_in_of(v)
  let reach = dmin(at.rows_out, corner_inset)
  if at.small {
    small_panel_row_in_node
  } else if at.words == 0.0 && reach > 0.0 {
    @ui.style(mx=room(-reach), px=room(reach), radius=rounded(row_corner))
  } else if at.sides > 0.5 {
    panel_words_in_node(v).then(panel_row_round)
  } else {
    panel_words_in_node(v)
  }
}

///|
// kept across runs: a value (no field of it changes)
let small_panel_row_in_node : @ui.Style = @ui.style(px=room(text_in), radius=rounded(small_panel_inner(r_menu)))

///|
// kept across runs: a value (no field of it changes)
let panel_row_round : @ui.Style = @ui.style(radius=rounded(row_corner))
