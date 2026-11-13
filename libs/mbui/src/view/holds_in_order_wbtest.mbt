///|
/// Whether each of the tree's live nodes holds each other, as Tree::holds and Tree::holds_in_order say it, those two not
/// the same where they differ.
fn holds_differ(t : Tree) -> Array[String] {
  let out = []
  let live = []
  for i, n in t.nodes {
    if n.live {
      live.push({ at: i, gen: n.gen })
    }
  }
  for a in live {
    for b in live {
      if t.holds(a, b) != t.holds_in_order(a, b) {
        out.push("\{a.at} holds \{b.at}: \{t.holds(a, b)}")
      }
    }
  }
  out
}

///|
test "what holds what read off the order as by going up through what holds it: through slots, layers raised over others at the root, nodes let go and their indexes made others'" {
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let b_on = @signals.signal(false, same=fn(a, b) { a == b })
  let up = @signals.signal(0, same=fn(a, b) { a == b })
  let t = Tree::new(
    fn(root) {
      root.box(fn(v) {
        v.show(fn() { a_on.get() }, fn(s) {
          s.box(fn(w) { w.box(fn(_) {  }) |> ignore }) |> ignore
          s.box(fn(_) {  }) |> ignore
        })
        v.box(fn(_) {  }) |> ignore
      })
      |> ignore
      root.show(fn() { b_on.get() }, fn(s) {
        s.box(fn(w) { w.box(fn(_) {  }) |> ignore }).stacked(By(fn() { up.get() })) |> ignore
      })
      root.box(fn(v) { v.box(fn(_) {  }) |> ignore }).stacked(Is(1)) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(holds_differ(t), [])
  b_on.set(true)
  up.set(2)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(holds_differ(t), [])
  a_on.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(holds_differ(t), [])
  a_on.set(true)
  up.set(0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(holds_differ(t), [])
}
