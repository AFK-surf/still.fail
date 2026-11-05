///|
test "panic layout properties cannot read hover from the placed result" {
  let tree = @view.Tree::new(fn(root) {
    root.width(By(fn() { Some(if root.pointer_within() { 80.0 } else { 100.0 }) })) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
