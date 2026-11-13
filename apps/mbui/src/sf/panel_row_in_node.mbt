// A row a page lays out itself in a panel's body made of nodes, its words on the panel's words' line (panel_row_in's,
// read where the body is nodes: panel_in_of).

///|
/// What a row node `v` of a panel's body made of nodes lays its words in by (panel_row_in's): in a small panel a row's
/// padding in at its sides and its corner concentric with the panel's (small_panel_row_in's); elsewhere as far in as the
/// panel's words (panel_words_in_node). Its ground under the hand is the row's own (panel_row_in's `hovered`:
/// hovered_node).
pub fn panel_row_in_node(v : @view.View) -> @ui.Style {
  let at = panel_in_of(v)
  if at.small {
    small_panel_row_in_node
  } else if at.words > 0.0 {
    let inset = dmax(0.0, panel_card_in - at.sides)
    let pad = dmax(0.0, at.words - inset)
    @ui.style(mx=room(inset), px=room(pad), radius=rounded(row_corner))
  } else if at.rows_out > 0.0 {
    let out = dmin(at.rows_out, text_in)
    @ui.style(mx=room(-out), px=room(out), radius=rounded(row_corner))
  } else {
    panel_words_in_node(v)
  }
}

///|
/// The corner radius matching `panel_row_in_node(v)` for press ripples on panel rows.
pub fn panel_row_corner_node(v : @view.View) -> Double {
  let at = panel_in_of(v)
  if at.small {
    small_panel_inner(r_menu)
  } else if at.words > 0.0 || at.rows_out > 0.0 {
    row_corner
  } else {
    0.0
  }
}

///|
// kept across runs: a value (no field of it changes)
let small_panel_row_in_node : @ui.Style = @ui.style(px=room(text_in), radius=rounded(small_panel_inner(r_menu)))
