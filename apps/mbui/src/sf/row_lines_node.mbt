// The row's title and its actions on one line, followed by lines across the same room, made once as tree nodes.

///|
/// The words of a row (row_lines') in a row `parent`, beside its mark. `head` makes the first line: its title and
/// what ends it, 12 apart and across their middle. `under` makes the lines under it, each as wide as the words. With
/// `spaced`, successive lines are 2 apart; otherwise they touch. The title made by `head` takes the remaining room:
/// give it grow and shrink, a zero minimum width and, for a one-line name, the cut-words style. Actions keep their own
/// width. Bind changing words and use the tree's show/pick for changing children, as with any other node.
pub fn row_lines_node(
  parent : @view.View,
  head : (@view.View) -> Unit,
  under : (@view.View) -> Unit,
  spaced? : Bool = false,
) -> @view.View {
  parent.box(fn(words) {
    style_node(words, fn() { if spaced { desk_list_text } else { pg_row_words } }, in_row=true)
    words.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    words.box(fn(first) {
      style_node(first, fn() { row_first_line })
      head(first)
    })
    |> ignore
    under(words)
  })
}
