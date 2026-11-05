///|
test "panic layout cannot create arbitrary children" {
  let tree = @view.Tree::new(fn(root) {
    root.layout(Is(()), fn(_, _) {
      root.box(fn(_) { }) |> ignore
      @view.arrangement(100.0, 100.0, [])
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
