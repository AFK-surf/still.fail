// A sheet's column of its own as nodes of the window's tree (sheet_column's): what a panel's body lays out itself on
// the panel's words' line, its rows' grounds reaching out across the room it leaves at its sides.

///|
/// A sheet's column of its own in `parent` (sheet_column's: a panel's body a page lays out itself, the settings' joining a
/// station), what `body` makes in it: on a sheet, as far in from the panel's sides as its words are (the words' line
/// the body is lent, else a sheet's words' own, sheet_panel_sides), its rows' grounds reaching out across that room
/// (rows_out) and their words on the column's line, as in a sheet the presenters lay out; in a dialog in the window's
/// middle, whose body stands in such a column already, as it is there.
#callsite(autofill(loc))
pub fn sheet_column_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let at = panel_in_of(parent)
  parent.box(made_for=loc, fn(col) {
    if at.centred {
      style_node(col, fn() { sheet_column_box })
    } else {
      // (the words' line, from the panel's sides: where the body is lent it, else a sheet's words' own)
      let pad = if at.sides + at.words > 0.0 { at.words } else { sheet_panel_sides }
      let sides = at.sides + pad
      style_node(col, fn() { sheet_column_box.then(@ui.style(px=room(pad))) })
      panel_in_lend(col, look_node(parent), 0.0, sides~, rows_out=dmax(0.0, sides - panel_card_in), small=at.small, clear=at.clear)
    }
    body(col)
  })
  |> ignore
}
