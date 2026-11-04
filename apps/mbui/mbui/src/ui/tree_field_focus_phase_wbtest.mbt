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

///|
test "a field requested while its tree is made under a modal is the modal's return target" {
  let open = @signals.signal(true)
  let page = Field::new()
  let t = Tester::new(fn(_) { }, w=200.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    field(root, page, placeholder="Page") |> ignore
    page.focus()
    root.show(fn() { open.get() }, fn(layer) {
      layer.over(Is(true)).stacked(Is(2)).modal(Is(true)) |> ignore
      let stop = layer.box(fn(b) {
        b.width(Is(Some(120.0))).height(Is(Some(40.0))).focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="Modal")))) |> ignore
      })
      layer.focus_opens(stop) |> ignore
    })
  })
  t.frame(ms=16.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Modal"))
  open.set(false)
  t.frame(ms=16.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Page"))
}
