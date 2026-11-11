///|
/// Where a device meets it: a tool's tip (sf's tool_node), made in a layer over the window for the control it tells of
/// (View::lives_with) and let go as that control's scope stops, the control let go with the row that holds it. The tip
/// is held by none of what is being let go, so its run is taken out of the drawing order by itself (Tree::order_taken_out),
/// not passed over as one going with what holds it (View::let_go).
test "a node another's scope lets go as that one goes with what holds it, held in another layer: out of the drawing order" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tree::new(
    fn(root) {
      let layer = root.box(fn(l) { l.width(Is(Some(390.0))).height(Is(Some(100.0))) |> ignore })
      root.box(fn(col) {
        col.show(fn() { on.get() }, at_once=true, fn(row) {
          row.height(Is(Some(40.0))) |> ignore
          row.box(fn(control) {
            control.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
            layer.box(fn(tip) { tip.width(Is(Some(60.0))).height(Is(Some(20.0))) |> ignore }).lives_with(control)
            |> ignore
          })
          |> ignore
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.kept_said(), None)
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.kept_said(), None)
}
