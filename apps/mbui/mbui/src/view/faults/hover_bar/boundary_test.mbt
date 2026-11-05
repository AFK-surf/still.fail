///|
test "panic a scrollbar's hover cannot resize its track" {
  let tree = @view.Tree::new(fn(root) {
    root.height(By(fn() { Some(if root.bar_near(12.0) { 80.0 } else { 100.0 }) })) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
}
