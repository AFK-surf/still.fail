///|
/// A line between parts of a panel's body in `parent` (menu_rule's, between a small panel's groups): the words' ink
/// faintly, 1 high, 6 over and under it, as wide as the body.
#callsite(autofill(loc))
pub fn panel_rule_node(parent : @view.View, loc~ : SourceLoc) -> Unit {
  menu_rule_node(parent, 0.0, loc~)
}
