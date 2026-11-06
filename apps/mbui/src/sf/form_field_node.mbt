// A labelled field and what it holds as nodes of the window's tree.

///|
// kept across runs: a label lent to the inputs made in the field's body, released with that body
let field_label_at : @view.Lent[() -> String] = @view.Lent::new()

///|
/// A field's `label`, optional `aside` at its end, `body`, and `error` or else `hint` under it, six apart. A wide
/// page holds it to 420 at most; a panel and a narrow page give it their width. All words follow their inputs without
/// remaking the body. An input_node or textarea_node made in the body is named by the label to a screen reader.
pub fn field_node(
  parent : @view.View,
  label : () -> String,
  body : (@view.View) -> Unit,
  hint? : () -> String = fn() { "" },
  error? : () -> String = fn() { "" },
  aside? : (@view.View) -> Unit,
) -> @view.View {
  let wide_page = part_of(parent).look is Wide && !in_panel_node(parent)
  parent.box(fn(f) {
    f.gap(Is(6.0)) |> ignore
    if wide_page { f.max_width(Is(Some(field_wide_most))) |> ignore }
    f.box(fn(top) {
      top.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(End))) |> ignore
      top.box(fn(w) {
        w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        styled_words(w, label, fn() { field_label }) |> ignore
      }) |> ignore
      match aside { Some(make) => make(top); None => () }
    }) |> ignore
    f.box(fn(slot) {
      slot.gap(Is(6.0)).lends(field_label_at, label) |> ignore
      body(slot)
    }) |> ignore
    f.show(fn() { error() != "" || hint() != "" }, fn(w) {
      styled_words(w, fn() { if error() != "" { error() } else { hint() } }, fn() {
        if error() != "" { field_error } else { field_hint }
      }) |> ignore
    })
  })
}
