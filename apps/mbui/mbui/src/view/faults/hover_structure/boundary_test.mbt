///|
test "panic hover cannot choose which nodes exist" {
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { root.pointed() }, fn(v) { v.words(Is("hover")) |> ignore })
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
