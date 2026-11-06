// The library's pill as a node of the window's tree, following its words, tone, icon and theme.

///|
/// A pill in `parent`, as `pill` draws it: 22 high, 9 in at either end, its optional icon 14 across and 4 before its
/// words. `words`, `tone` and `icon` are read as they change (an empty icon or words is not drawn). Its words stay on
/// one line and may end in an ellipsis. It takes no input, and its words are read as text. The node.
pub fn pill_node(
  parent : @view.View,
  words : () -> String,
  tone? : () -> PillTone = fn() { Neutral },
  icon? : () -> String = fn() { "" },
) -> @view.View {
  let colors = fn() { pill_colors(tone()) }
  parent.box(fn(p) {
    style_node(p, fn() { pill_box })
    p
    .padding(Is((pill_in, 0.0, pill_in, 0.0)))
    .ground(By(fn() { colors().0 }))
    .bone_whole(Is(true))
    |> ignore
    p.show(fn() { icon() != "" }, fn(i) {
      icon_node(i, "", pill_icon, By(fn() { colors().1 }), name_now=icon) |> ignore
    })
    p.show(fn() { words() != "" }, fn(w) {
      w
      .words(By(words))
      .words_look(By(fn() { @ui.style_words(pill_words) }))
      .ink(By(fn() { colors().1 }))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .allow_ellipsis(Is(true))
      |> ignore
    })
  })
}
