///|
test "panic a pointer position derived from placement cannot place another node" {
  let tree = @view.Tree::new(fn(root) {
    let child = root.box(fn(_) { })
    child.offset(By(fn() { root.pointer_here_told().unwrap_or((0.0, 0.0)) })) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
