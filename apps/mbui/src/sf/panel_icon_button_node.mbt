// A small panel's icon button (panel_icon_button's) as a node of the window's tree, made once: a 24 circle, its icon in
// the muted ink, the hover's ground and the ink where the hand is on it; named by its label, read out a button, its tip
// shown by it.

///|
/// A small panel's icon button (panel_icon_button's: close, stop, a step) in `parent`, made once: a 24 circle showing
/// icon `icon` (panel_icon_size), muted, the hover's ground and the ink where the hand is on it (lit_node); read out a
/// button named `label` (as it changes), its tip by it on its foot's side in the layer the panel it is in is lent
/// (panel_tips_lent; none outside a panel); `press` done as it is pressed. The node.
#callsite(autofill(loc))
pub fn panel_icon_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  @headless.button(made_for=loc, parent, label, fn(_) { press() }, fn(v, _) {
    style_node(v, fn() { panel_icon_box })
    let hot = fn() { lit_node(v) }
    // (its hovered{bg=Hover}: the hover's ground where the hand is on it)
    v.ground(By(fn() { if hot() { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    icon_node(v, icon, panel_icon_size, By(fn() { if hot() { theme().p.text } else { theme().p.muted } })) |> ignore
    panel_tip_node(v, label)
  })
}
