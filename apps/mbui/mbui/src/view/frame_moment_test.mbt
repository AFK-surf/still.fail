// A frame lays out what it shows as of the moment it is given, whatever the host's clock says by then (2026-11-05: what
// a frame's layout told, a size laid out otherwise, was taken at the host's now, which had gone on; each such moved what
// was sliding away a little further, its place told again, laid out again inside the pass before, till the slide
// ended: thousands deep on an emulator as a chat was left, its GL thread out of stack).

///|
test "a frame lays out at the moment it is given, the host later by then: what it tells as it is laid out does not move it to the host's now" {
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
  assert_eq(tree.logic_at(), 100.0)
  assert_eq(tree.drawn_at(), 100.0)
  assert_eq(seen.val, Some((80.0, 30.0)))
  assert_eq(host_reads.val, 0)
}
