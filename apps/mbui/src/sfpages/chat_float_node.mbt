// The list's floating actions and the composer's clearance share one layout.
// Neither the pane's width nor the measured foot is published back to padding.

///|
fn chat_float_node(
  parent : @view.View,
  foot : () -> @view.Height,
  lift : () -> Double,
  make : (@view.View) -> Unit,
) -> @view.View {
  parent.box(fn(layer) {
    layer.over(Is(true)) |> ignore
    let clearance = layer.box(fn(space) { space.height_measured(By(foot)) |> ignore })
    let content = layer.box(make)
    layer.layout(By(fn() { (composer_side(), @sf.native_on(), lift()) }), fn(inputs, space) {
      let (side, native, lift) = inputs
      let w = space.width().unwrap_or(space.max_width().unwrap_or(0.0))
      let h = space.height().unwrap_or(space.max_height().unwrap_or(0.0))
      let foot = space.measure(clearance, width=w)
      let right = (w - composer_width_for(w, side, native)) / 2.0 + float_in
      let action = space.measure(content, max_width=Some(dmax(0.0, w - right)), max_height=None)
      let (aw, ah) = action.size()
      @view.arrangement(w, h, [
        foot.at(0.0, h - foot.size().1),
        action.at(w - right - aw, h - foot.size().1 - lift - ah),
      ])
    }) |> ignore
  })
}
