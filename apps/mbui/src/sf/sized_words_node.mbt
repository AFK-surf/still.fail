// Words an old view said by a size alone (Ctx::text's `size` and `color`, no style), as a node of the window's tree:
// for a page moving onto the tree, so that what it shows stands where it stood. Their line is the theme's text_line
// times their size (1.4: 16.8 for 12, 15.4 for 11), not a token's own line (Meta's 18, Caption's 16), which is what
// sets them apart from words_node's; what is made new says its words by a style of tokens (words_node), not by this.

///|
/// Words in a node of `parent`'s as an old view's `c.text(words, size=…, color=…)` were (for a page moving onto the
/// tree; what is made new uses words_node and a style of tokens): `size` points (the system's size of words applied),
/// regular, on lines the theme's text_line times it, in `ink`, each as it is now; wrapped within the width they are
/// given, or not where `wrap` is false (Ctx::text's `wrap=false`: one line, as wide as it is); `cut`, on one line cut
/// short in an ellipsis where it is given less (Ctx::text's `max_lines=1` in a box of its own taking the row's room:
/// said so, View::cuts, so what checks that words fit takes it as said). The node.
#callsite(autofill(loc))
pub fn sized_words_node(
  parent : @view.View,
  words : () -> String,
  size : () -> Double,
  ink : () -> Int64,
  wrap? : Bool = true,
  cut? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(w) {
    w
    .words(By(words))
    .words_look(By(fn() {
      {
        size: size(),
        weight: 400,
        // (less than 0: that share of their size as it is drawn, Ctx::text's text_line × size)
        line: -@ui.tree_theme().text_line,
        wrap: wrap && !cut,
        tracking: @view.letters_own,
        balance: false,
        max_lines: 0,
      }
    }))
    .ink(By(ink))
    |> ignore
    if cut {
      w.cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    }
  })
}
