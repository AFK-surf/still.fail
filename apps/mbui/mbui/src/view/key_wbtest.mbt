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

///|
test "hand: a node's cells of whether it is held or pointed at made as read, let go with it: shown and hidden again and again, as many as there were" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v.box(fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(40.0))).on_press(fn() {  }).ground(By(fn() {
            if b.pressed() || b.pointed() {
              1L
            } else {
              2L
            }
          }))
          |> ignore
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let cells = fn() {
    t.nodes.iter().filter(fn(n) { n.pressed_cell is Some(_) || n.pointed_cell is Some(_) }).count()
  }
  let at_first = cells()
  for _ in 0..<20 {
    there.set(false)
    there.set(true)
  }
  t.frame(390.0, 844.0) |> ignore
  assert_eq(cells(), at_first)
  assert_true(at_first > 0)
}
