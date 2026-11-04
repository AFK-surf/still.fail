// The message list lends its width constraint to the nodes made inside each lazy row.

///|
let chat_row_width : @view.Lent[@view.WidthContext] = @view.Lent::new()

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
