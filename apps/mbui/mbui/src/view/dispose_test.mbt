///|
test "disposing a tree commits its children's cleanup after the whole tree has stopped observing it" {
  let count = @signals.signal(2)
  let inside : Array[Int] = []
  let outside : Array[Int] = []
  let stop = @signals.effect_scope(fn() {
    @signals.effect(fn() { outside.push(count.get()) }) |> ignore
  })
  let t = @view.Tree::new(fn(root) {
    root.reacts(fn() { count.get() }, fn(n) { inside.push(n) })
    for _ in 0..<2 {
      root.box(fn(child) {
        child.owns(fn() { count.set(@signals.untracked(fn() { count.get() }) - 1) }) |> ignore
      }) |> ignore
    }
  })
  t.dispose()
  assert_eq(inside, [2], msg="no observer in a tree being disposed sees a partial cleanup")
  assert_eq(outside, [2, 0], msg="the final cleanup is still told outside the tree")
  assert_eq(t.alive(), 0)
  stop()
}
