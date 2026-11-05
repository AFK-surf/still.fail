///|
test "a frame's layout observations keep its supplied moment, however late the host is" {
  let host_now = Ref(0.0)
  let host_reads = Ref(0)
  let seen : Ref[(Double, Double)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(child) {
        child.width(Is(Some(80.0)))
        .height(By(fn() { Some(20.0 + root.tree.drawn_at() / 10.0) }))
        .shrink(Is(0.0)) |> ignore
        child.reacts(fn() { child.laid_size_told() }, fn(size) {
          seen.val = size
        })
      }) |> ignore
    },
    time=fn() {
      host_reads.val += 1
      host_now.val
    },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  host_reads.val = 0
  // The host can be later by the time a frame does its work. Its wall clock is
  // not a new event, and observing layout must not move this frame to it.
  host_now.val = 200.0
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore
  println("frame moment: logic=\{tree.logic_at()} drawn=\{tree.drawn_at()} size=\{seen.val} host_reads=\{host_reads.val}")
  assert_eq(tree.logic_at(), 100.0)
  assert_eq(tree.drawn_at(), 100.0)
  assert_eq(seen.val, Some((80.0, 30.0)))
  assert_eq(host_reads.val, 0)
}
