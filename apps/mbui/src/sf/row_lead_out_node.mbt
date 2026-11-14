// Where a tile leading a row stands, for a row of nodes (row_lead_out's).

///|
/// row_lead_out's for node `v` (a tile with a ground leading a row of nodes: a maker's mark): out from the row's words
/// to the ladder's inset from its start and top, concentric with its corner there, by the arrangement `v` is laid out
/// in (look_node: a narrow row's words text_in under its top, a wide one's 10) and how far in the row has its words at
/// its start (a row of a panel's body as panel_row_at stands it, as link_row_node and wide_link_row_node lay it out:
/// in a panel's list in a sheet 8, not a page's 16; text_in elsewhere).
pub fn row_lead_out_node(v : @view.View) -> @ui.Style {
  let (top, own) = match look_node(v) {
    Narrow => (text_in, card_pad - corner_inset)
    Wide => (10.0, desk_list_out)
  }
  let side = match panel_row_at(panel_in_of(v), own~, card=on_card_node(v)) {
    Some(p) => p.side
    None => text_in
  }
  @ui.style(ml=room(corner_inset - side), mt=room(corner_inset - top))
}
