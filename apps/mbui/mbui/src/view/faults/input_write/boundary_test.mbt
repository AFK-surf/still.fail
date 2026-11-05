///|
test "panic layout input capture cannot write model state" {
  let model = @signals.signal(0)
  let tree = @view.Tree::new(fn(root) {
    root.layout(By(fn() { model.set(1); 20.0 }), fn(h, _) {
      @view.arrangement(100.0, h, [])
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
