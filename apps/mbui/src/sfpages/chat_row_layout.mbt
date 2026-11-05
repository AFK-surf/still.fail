// The row owns its column inset and the space above its contents. Both come
// from this measurement's width, without publishing the list's placed width.

///|
fn chat_row_layout(row : @view.View, content : @view.View, fixed_gap : () -> Double?) -> Unit {
  row.layout(By(fn() { (fixed_gap(), @sf.native_on(), native_row_inset()) }), fn(inputs, space) {
    let (fixed_gap, native, native_inset) = inputs
    let width = space.width().unwrap_or(space.max_width().unwrap_or(0.0))
    let narrow = width <= chat_narrow_w
    let side = if narrow {
      if native { native_inset } else { row_side_narrow }
    } else if native {
      dense_row_side
    } else {
      dmax(row_side_least, (width - chat_column_w) / 2.0)
    }
    let gap = fixed_gap.unwrap_or(if narrow { list_gap_narrow } else { list_gap })
    let body = space.measure(content, width=dmax(0.0, width - 2.0 * side), max_height=None)
    @view.arrangement(width, body.size().1 + gap, [body.at(side, gap)])
  }) |> ignore
}
