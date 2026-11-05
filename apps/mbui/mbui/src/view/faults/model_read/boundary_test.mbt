///|
test "panic layout cannot read an uncaptured model signal" {
  let model = @signals.signal(50.0)
  let tree = @view.Tree::new(fn(root) {
    root.layout(Is(()), fn(_, _) { @view.arrangement(@signals.untracked(fn() { model.get() }), 20.0, []) }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
