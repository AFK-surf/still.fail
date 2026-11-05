// This asserts the pinned baseline's counterexample, not the desired contract.
// The original desired assertion (100, 100, (80, 30), zero host reads) was red
// in commit 0f5ba584f8. Keep the baseline observation inside the experiment.

///|
test "control: layout can advance a supplied frame to a later host clock" {
  let host_now = Ref(0.0)
  let host_reads = Ref(0)
  let seen : Ref[(Double, Double)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(child) {
        child.width(Is(Some(80.0)))
        .height(By(fn() { Some(20.0 + root.tree.drawn_at() / 10.0) }))
        .shrink(Is(0.0)) |> ignore
        child.reacts(fn() { child.laid_size_told() }, fn(size) { seen.val = size })
      }) |> ignore
    },
    time=fn() { host_reads.val += 1; host_now.val },
  )
  defer { tree.dispose() }
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  host_reads.val = 0
  host_now.val = 200.0
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq(tree.logic_at(), 200.0)
  assert_eq(tree.drawn_at(), 200.0)
  assert_eq(seen.val, Some((80.0, 40.0)))
  assert_eq(host_reads.val, 4)
}
