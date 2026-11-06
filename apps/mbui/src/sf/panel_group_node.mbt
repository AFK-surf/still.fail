// A small panel's group as nodes of the window's tree (panel_group's): its label, if any, and the rows it holds, 2
// apart. The label may change without remaking the rows; a lead belongs to the label and is only present with it.

///|
/// A small panel's group. `body` is made once, directly in the group, so each of its children stands 2 apart. `label`
/// is read as it changes; while empty neither the heading nor `lead` takes room. `lead`, when present, is before the
/// label on its line. The group node.
pub fn panel_group_node(
  parent : @view.View,
  body : (@view.View) -> Unit,
  label? : () -> String = fn() { "" },
  lead? : (@view.View) -> Unit,
) -> @view.View {
  parent.box(fn(group) {
    style_node(group, fn() { panel_group_box })
    group.show(fn() { label() != "" }, fn(heading) {
      style_node(heading, fn() { panel_label_at })
      match lead {
        Some(make) =>
          heading.box(fn(line) {
            style_node(line, fn() { panel_label_led })
            make(line)
            line.box(fn(words) {
              // A wrapped label gives way beside its lead just as an old view's text in a row does.
              words.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              styled_words(words, label, fn() { panel_note_words }) |> ignore
            })
            |> ignore
          })
          |> ignore
        None => heading.box(fn(words) { styled_words(words, label, fn() { panel_note_words }) |> ignore }) |> ignore
      }
    })
    body(group)
  })
}
