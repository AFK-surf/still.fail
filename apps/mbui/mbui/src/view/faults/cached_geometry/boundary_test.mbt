///|
test "panic layout inputs cannot use a cached computation of geometry" {
  let tree = @view.Tree::new(fn(_) { })
  let root = tree.root()
  let geometry = @signals.computed(fn(_) { root.laid_size_told().map(fn(s) { s.0 }).unwrap_or(0.0) })
  geometry.get() |> ignore
  tree.frame(100.0, 100.0, now=0.0) |> ignore
  geometry.get() |> ignore
  root.layout(By(fn() { geometry.get() }), fn(w, _) { @view.arrangement(w, 100.0, []) }) |> ignore
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
