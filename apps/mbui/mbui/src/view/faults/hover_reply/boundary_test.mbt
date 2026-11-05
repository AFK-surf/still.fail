///|
test "panic an immediate hover reaction cannot change layout" {
  let tree = @view.Tree::new(fn(root) {
    root.reacts(fn() { root.pointer_within() }, fn(over) {
      root.width(Is(Some(if over { 80.0 } else { 100.0 }))) |> ignore
    })
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
