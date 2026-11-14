// The layer of tips a presented panel lends what its body and its foot are made of (panel_tips_lent), for a part a page
// makes there itself that says its own tip as the library's parts do (tip_node's other ways: `within`, `repeats`).

///|
/// The layer of tips the panel `v` is made in is lent (presented_nodes': over all that is presented, so Escape shuts a
/// tip before the panel); none outside a panel.
pub fn panel_tips_of(v : @view.View) -> TipLayer? {
  v.lent(panel_tips_lent)
}
