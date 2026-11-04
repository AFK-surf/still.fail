///|
test "two old views measured in turn remain placed and readable when the first is measured again" {
  let t = Tester::new(fn(_) { }, w=240.0, h=200.0, stable=false)
  t.check_looks(false)
  let first : Ref[@view.View?] = Ref(None)
  let second : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.layout_box(Is(0), fn(l, _) {
      let a = l.child("first", fn(node) {
        first.val = Some(node)
        old(node, natural=true, fn(c) {
          c.box(h=Px(30.0), bg=0x112233ffL, fn() { c.text("first") |> ignore }) |> ignore
        }) |> ignore
      })
      let b = l.child("second", fn(node) {
        second.val = Some(node)
        old(node, natural=true, fn(c) {
          c.box(h=Px(20.0), bg=0x445566ffL, fn() { c.text("second") |> ignore }) |> ignore
        }) |> ignore
      })
      l.measure(a, 200.0) |> ignore
      l.measure(b, 120.0) |> ignore
      l.measure(a, 160.0) |> ignore
      l.place(a, 0.0, 0.0)
      l.place(b, 0.0, 30.0)
    }) |> ignore
  })
  t.frame(ms=16.0)
  assert_eq((first.val.unwrap().rect().3, second.val.unwrap().rect().3), (30.0, 20.0))
  let c = g()
  for at in 0..<c.count {
    let seen : Set[Int] = Set::new()
    let mut child = c.nodes[at].first
    while child >= 0 {
      assert_true(child < c.count && !seen.contains(child), msg="invalid child link under \{at}: \{child}")
      seen.add(child)
      assert_eq(c.nodes[child].parent, at, msg="child \{child} under \{at}")
      child = c.nodes[child].next
    }
  }
  let first_id = first.val.unwrap().id()
  t.frame(ms=16.0)
  assert_eq(first.val.unwrap().id(), first_id)
}
