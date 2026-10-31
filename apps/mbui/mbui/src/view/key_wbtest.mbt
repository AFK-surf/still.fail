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

///|
test "what a node said it is: let go with it; its index made another's that says nothing, nothing said of it" {
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let b_on = @signals.signal(false, same=fn(a, b) { a == b })
  let at = Ref(-1)
  let t = Tree::new(
    fn(root) {
      root.show(fn() { a_on.get() }, fn(v) {
        at.val = v.at
        v.says(Is(Some(said(Button, label="甲")))) |> ignore
      })
      root.show(fn() { b_on.get() }, fn(v) { at.val = v.at })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let a_at = at.val
  a_on.set(false)
  assert_true(t.nodes[a_at].said is None)
  b_on.set(true)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(at.val, a_at)
  assert_true(t.nodes[at.val].said is None && t.said_order().iter().all(fn(s) { s.said is None }))
}
