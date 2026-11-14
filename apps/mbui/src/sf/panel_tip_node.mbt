// A tip by a part of what a panel's body or foot is made of (a key a page makes itself there), in the layer of tips the
// panel is lent: the one way each of them shows its name by it (panel_icon_button_node's too).

///|
/// `label`'s tip by `anchor`, a part of what a panel's body or foot is made of, on its foot's side, in the layer of tips
/// the panel it is in is lent (panel_tips_lent: over all that is presented, so Escape shuts it before the panel); none
/// outside a panel.
pub fn panel_tip_node(anchor : @view.View, label : () -> String) -> Unit {
  match anchor.lent(panel_tips_lent) {
    Some(tips) => tip_node(tips, anchor, label) |> ignore
    None => ()
  }
}
