// How far out what a page lays out itself in a panel's body made of nodes stands, its words on the panel's words'
// line (panel_words_out_by's, read where the body is nodes: panel_in_of).

///|
/// What node `v` of a panel's body made of nodes, whose words stand `by` in from its own side, is laid out by: out
/// from the column by as far as puts its words on the panel's words' line, no further out than the room the panel
/// leaves its rows (panel_words_out_by's); none outside a panel.
pub fn panel_words_out_by_node(v : @view.View, by : Double) -> @ui.Style {
  let at = panel_in_of(v)
  @ui.style(ml=room(dmax(at.words - by, -at.rows_out)))
}
