// A dialog's rows (dialog_rows', for a panel whose body is nodes: panel_nodes): in a dialog in the middle of the window,
// the list out across its sides and down to its foot, each row round as its height, the last concentric with its foot
// corners, their words back on the dialog's line; elsewhere (a sheet, a small panel beside what opened it) as they are.

///|
/// The styles of a list of rows `row_h` high (its own, and each row's) made in node `v` of a panel's body, as
/// dialog_rows says them to an old body: where the body is a dialog's in the middle of the window (as
/// panel_centred_node lends it: PanelIn's `centred`), the list out to where a capsule that high stands concentric with
/// the dialog's corners, reaching across the room its column stands in from its padding too (its words' line,
/// column_in_now's), and down past its padding to there; each row round, its words back that far in. None elsewhere.
pub fn dialog_rows_node(v : @view.View, row_h : Double) -> (@ui.Style, @ui.Style) {
  guard panel_in_of(v).centred else { return (no_style, no_style) }
  // (from its column: its padding, and the room its column stands in from that: panel_words less dialog_pad)
  let out = @ui.capsule_in(dialog_r, row_h) - dialog_pad
  let side = out - (panel_words - dialog_pad)
  (@ui.style(mx=room(side), mb=room(out)), @ui.style(radius=Full, px=room(-side)))
}
