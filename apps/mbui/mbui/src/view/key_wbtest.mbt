///|
test "keys and back: a node let go holds none of what it said it does as its index waits to be made another's" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let at = Ref(-1)
  let t = Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        at.val = v.at
        v.on_key(fn(_k) { true }).takes_back(fn() {  }) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_true(t.nodes[at.val].on_key is Some(_) && t.nodes[at.val].on_back is Some(_))
  there.set(false)
  assert_true(!t.nodes[at.val].live)
  assert_true(t.nodes[at.val].on_key is None && t.nodes[at.val].on_back is None)
}
