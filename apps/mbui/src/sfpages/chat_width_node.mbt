// The message list lends its width constraint to the nodes made inside each lazy row.

///|
let chat_row_width : @view.Lent[@view.WidthContext] = @view.Lent::new()

///|
/// Give a message's bubble its pane's current width without feeding a measured width back into layout.
fn chat_bubble_width(node : @view.View, elsewhere : () -> Double) -> Unit {
  match node.lent(chat_row_width) {
    Some(width) => width.bind(node, By(fn() { (composer_side(), @sf.native_on()) }), fn(w, inputs) {
      let (side, native) = inputs
      node.max_width(Is(Some(composer_words_width_given(w, side, native) + 2.0 * bubble_side))) |> ignore
    })
    None => node.max_width(By(fn() { Some(composer_words_width(elsewhere()) + 2.0 * bubble_side) })) |> ignore
  }
}

///|
fn chat_inline_layout(node : @view.View, elsewhere : () -> Bool, apply : (Bool) -> Unit) -> Unit {
  match node.lent(chat_row_width) {
    Some(width) => width.bind(node, Is(()), fn(w, _) { apply(w <= chat_narrow_w) })
    None => node.reacts(elsewhere, apply)
  }
}

///|
fn chat_stacked_layout(node : @view.View, elsewhere : () -> Bool, apply : (Bool) -> Unit) -> Unit {
  match node.lent(chat_row_width) {
    Some(width) => width.bind(node, By(fn() { @sf.native_on() }), fn(w, native) { apply(native && w <= chat_narrow_w) })
    None => node.reacts(elsewhere, apply)
  }
}
