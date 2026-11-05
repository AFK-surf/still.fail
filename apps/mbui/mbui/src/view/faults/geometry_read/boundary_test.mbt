///|
test "panic layout cannot read the previous placed rectangle" {
  let tree = @view.Tree::new(fn(root) {
    root.layout(Is(()), fn(_, _) {
      let (_, _, w, h) = root.rect()
      @view.arrangement(w, h, [])
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
