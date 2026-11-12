// The rows at a dialog's foot (dialog_foot_rows', for a panel whose body is nodes: panel_nodes): in a dialog in the
// middle of the window, out past its words at its sides and its foot to where the last stands concentric with its foot
// corners, their words back on the dialog's line; elsewhere (a sheet, a small panel beside what opened it) as they are.

///|
/// A list of a panel's rows at a dialog's foot in `parent` (a station's card's ways on), `style` round them, what `body`
/// makes in it: in a dialog in the middle of the window (PanelIn's `centred`) down past its padding to where they reach
/// (foot_rows_out's), its rows told how far out they reach (foot_rows_lent: panel_row_by's capsule there); elsewhere in
/// `style` alone, its rows as they are.
#callsite(autofill(loc))
pub fn dialog_foot_rows_node(
  parent : @view.View,
  style : @ui.Style,
  body : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let centred = panel_in_of(parent).centred
  parent.box(made_for=loc, fn(b) {
    if !centred {
      style_node(b, fn() { style })
      body(b)
      return
    }
    style_node(b, fn() { style.then(@ui.style(mb=room(-foot_rows_out_node()))) })
    b.lends(foot_rows_lent, foot_rows_out_node) |> ignore
    body(b)
  })
  |> ignore
}

///|
/// How far a dialog's foot rows reach out past its words, where what it holds is nodes (foot_rows_out's): from its side
/// (dialog_pad) to where a capsule a wide row high stands concentric with its corner, and across the room its column
/// stands in from its padding (its words' line: panel_words less dialog_pad, column_in_now's there).
fn foot_rows_out_node() -> Double {
  dialog_pad - @ui.capsule_in(dialog_r, desk_row_least()) + (panel_words - dialog_pad)
}
