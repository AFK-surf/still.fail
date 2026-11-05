///|
test "panic layout cannot change a child binding" {
  let tree = @view.Tree::new(fn(root) {
    let child = root.box(fn(_) { })
    root.layout(Is(()), fn(_, space) {
      child.width(Is(Some(30.0))) |> ignore
      let measured = space.measure(child)
      @view.arrangement(100.0, 100.0, [measured.at(0.0, 0.0)])
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
