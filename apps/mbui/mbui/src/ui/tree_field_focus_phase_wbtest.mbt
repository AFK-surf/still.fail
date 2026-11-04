// Focus requested while the window's tree is being made belongs to that attachment, before its first layout.

///|
test "fields asked for focus while a tree is made receive it in request order before the first layout" {
  let first = Field::new()
  let last = Field::new()
  let t = Tester::new(fn(_) { }, w=200.0, h=300.0, stable=false)
  let nodes : Array[@view.View] = []
  set_view_app(fn(root) {
    first.focus()
    nodes.push(field(root, first, placeholder="First"))
    nodes.push(field(root, last, placeholder="Last"))
    last.focus()
    root.box(fn(n) {
      n.height(By(fn() { Some(if nodes[1].focused() { 80.0 } else { 20.0 }) }))
      .ground(Is(0x13579bffL)) |> ignore
    }) |> ignore
  })
  assert_false(nodes[0].focused())
  assert_true(nodes[1].focused(), msg="the tree's attachment delivers the request without geometry")
  assert_eq(g().focus, tree_said_id(nodes[1].id()))
  t.frame(ms=16.0)
  assert_eq(view_tree().unwrap().work().computes, 1)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.3 == 80.0 && r.4 == 0x13579bffL }))
}
