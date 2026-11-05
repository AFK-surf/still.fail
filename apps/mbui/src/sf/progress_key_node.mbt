///|
/// A key of a bar for what comes by itself as a node (progress_key's): round, `side` across, the pointer's ground on it;
/// its `glyph` `mark` big in its middle, in its place while something comes how far it has come (`coming()`: Some of a
/// part, coming_node's; None while nothing comes), update_key's dot, red's, where something `failed()`. Read out a button
/// named `label()`; pressed, `press`. The key's node (what a panel it opens comes from).
pub fn progress_key_node(
  parent : @view.View,
  side : Double,
  mark : Double,
  glyph : String,
  label : () -> String,
  coming : () -> Double??,
  failed : () -> Bool,
  press : () -> Unit,
) -> @view.View {
  parent.box(fn(k) {
    k
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    // (round as its ground is while there is one, as an old view's key's hovered{} look)
    .radius(By(fn() { if lit_node(k) { side / 2.0 } else { 0.0 } }))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { if lit_node(k) { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    k.presses(Is(true)).focusable(Is(true)).on_press(press) |> ignore
    let rippled = press_look(k, Is(side / 2.0), fn() { false })
    let on_it = fn(d : @view.Drag) { k.finger_target(d.wx, d.wy) }
    k.gesture(
      @ui.touch_slop(),
      press=fn(d) { rippled(d) },
      tap=fn(d) { if on_it(d) { press() } },
      drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && on_it(d) { press() } },
    )
    |> ignore
    k.pick(fn() { coming() is Some(_) }, fn(m, on) {
      if on {
        coming_node(m, fn() { coming().unwrap_or(None) }, mark, fn() { theme().p.text })
      } else {
        icon_node(m, glyph, mark, By(fn() { theme().p.text })) |> ignore
      }
    })
    // (red's dot, 3 in from its top right, on a ring of the page's ground)
    k.show(failed, fn(at) {
      at
      .over(Is(true))
      .width(Is(Some(side)))
      .height(Is(Some(side)))
      .padding(Is((0.0, update_dot_in, update_dot_in, 0.0)))
      .lines_up(Is(Some(End)))
      |> ignore
      at.box(fn(r) {
        r
        .width(Is(Some(update_dot_side)))
        .height(Is(Some(update_dot_side)))
        .radius(Is(update_dot_side / 2.0))
        .ground(By(fn() { @ui.tree_theme().color(Bg) }))
        .padding(Is((update_dot_rim, update_dot_rim, update_dot_rim, update_dot_rim)))
        |> ignore
        r.box(fn(d) {
          d.grow(Is(1.0)).width_share(Is(1.0)).radius(Is(update_dot_side / 2.0)).ground(By(fn() { @ui.tree_theme().color(Danger) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
}
