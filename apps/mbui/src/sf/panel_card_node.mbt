// A card a page lays out itself in a panel's body whose body is nodes (panel_card_out's, presenters.mbt): where it
// stands across the panel, by what the panel lends its body (panel_in_lent), as the old body's card stands by what the
// panel set as it built it.

///|
/// A card a page lays out itself in a panel's body (panel_card_out's) at node `v` of it: `panel_card_in` (16) in from
/// the panel's sides, concentric with its corners, out (or in) from the column it stands in by as far as that is in
/// from them (PanelIn's `sides`, its presenter's own room at its sides: a sheet's that fills its share none, a sheet a
/// press opened a pick's rows', one opened by nothing and a dialog in the window's middle their words'; a panel's list's
/// that less as far as it reaches out); none in a small panel (what it holds stands at its padding already) or outside
/// a panel.
pub fn panel_card_out_node(v : @view.View) -> @ui.Style {
  match v.lent(panel_in_lent) {
    Some(at) if !at.small => @ui.style(mx=room(panel_card_in - at.sides))
    _ => no_card_out
  }
}

///|
/// Under the last of what a dialog in the window's middle holds where that is a card (panel_card_last's, where the body
/// is nodes): the room its foot leaves less what a card at its foot stands in, so the card's foot corners are concentric
/// with the dialog's; none elsewhere.
pub fn panel_card_last_node(v : @view.View) -> @ui.Style {
  match v.lent(panel_in_lent) {
    Some(p) if p.centred && !p.small => @ui.style(mb=room(-(dialog_pad - panel_card_in)))
    _ => no_card_out
  }
}
