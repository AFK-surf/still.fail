// Where a tile leading a row stands, for a row of nodes (row_lead_out's).

///|
/// row_lead_out's for node `v` (a tile with a ground leading a row of nodes: a maker's mark): out from the row's words
/// to the ladder's inset from its start and top, concentric with its corner there, by the arrangement `v` is laid out
/// in (look_node: a narrow row's words text_in under its top, a wide one's 10).
pub fn row_lead_out_node(v : @view.View) -> @ui.Style {
  let top = match look_node(v) {
    Narrow => text_in
    Wide => 10.0
  }
  @ui.style(ml=room(corner_inset - text_in), mt=room(corner_inset - top))
}
