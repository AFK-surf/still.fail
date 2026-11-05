///|
test "panic a cached untracked hover cannot move a node" {
  let tree = @view.Tree::new(fn(root) {
    let over = @signals.computed(fn(_) { @signals.untracked(fn() { root.pointed_in() }) })
    over.get() |> ignore
    root.offset(By(fn() { (if over.get() { 50.0 } else { 0.0 }, 0.0) })) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
