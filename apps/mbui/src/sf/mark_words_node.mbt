// Words that are part of a mark (a workspace's letter in its square, a badge's `!` on its disc): drawn by their points
// as the mark round them is, as an icon is, never grown by the system's size of words out of what holds them.

///|
/// Words of `style` in a node of `parent`'s that are part of a mark of a size said (its letter, its `!`): as words_node's,
/// but at the size they are said whatever the system's size of words (View::box's `words_as_said`: what is worked out
/// of View::words_scale in it is at 1), so they stay in their mark as it does. Each as it is now. The node.
#callsite(autofill(loc))
pub fn mark_words_node(
  parent : @view.View,
  words : () -> String,
  style : () -> @ui.TextStyle,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, words_as_said=true, fn(w) { styled_words(w, words, style) |> ignore })
}
