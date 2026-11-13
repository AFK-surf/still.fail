///|
test "pointed at alone said otherwise: its hits found anew, nothing laid out for it" {
  let points = @signals.signal(true)
  let tree = Tree::new(
    fn(root) {
      root.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(40.0))).points(By(fn() { points.get() })) |> ignore })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let hits = tree.hits
  points.set(false)
  assert_eq((tree.layout_due, tree.hits > hits), (false, true))
}
