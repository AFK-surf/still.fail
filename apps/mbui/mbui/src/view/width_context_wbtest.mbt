///|
test "a bounded holder's current width and captured state lay out an existing child once" {
  let width = @signals.signal(300.0)
  let inset = @signals.signal(10.0)
  let row : Ref[View?] = Ref(None)
  let leaf : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.width(By(fn() { Some(width.get()) })).height(Is(Some(100.0))) |> ignore
      let context = parent.width_context()
      row.val = Some(parent.box(fn(n) {
        n.width_share(Is(1.0)).height(Is(Some(40.0))) |> ignore
        context.bind(n, By(fn() { inset.get() }), fn(w, p) {
          n.padding(Is((if w <= 700.0 { p } else { p + (w - 700.0) / 2.0 }, 0.0, 0.0, 0.0))) |> ignore
        })
        leaf.val = Some(n.box(fn(c) { c.height(Is(Some(20.0))) |> ignore }))
      }))
    }) |> ignore
  })
  t.frame(1000.0, 200.0, now=0.0) |> ignore
  let id = row.val.unwrap().id()
  assert_eq((leaf.val.unwrap().rect().0, t.work.computes), (10.0, 1))
  width.set(800.0)
  t.frame(1000.0, 200.0, now=10.0) |> ignore
  assert_eq((leaf.val.unwrap().rect().0, t.work.computes), (60.0, 2))
  inset.set(20.0)
  t.frame(1000.0, 200.0, now=20.0) |> ignore
  assert_eq((leaf.val.unwrap().rect().0, t.work.computes), (70.0, 3))
  assert_eq(row.val.unwrap().id(), id)
  t.dispose()
}

///|
test "a lazy child receives its holder's current width before it is first measured" {
  let row : Ref[View?] = Ref(None)
  let leaf : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      let context = parent.width_context()
      parent.layout_box(Is(0), fn(l, _) {
        let child = l.child("row", fn(n) {
          row.val = Some(n)
          n.height(Is(Some(40.0))) |> ignore
          context.bind(n, Is(0), fn(w, _) { n.padding(Is((w / 10.0, 0.0, 0.0, 0.0))) |> ignore })
          leaf.val = Some(n.box(fn(c) { c.height(Is(Some(20.0))) |> ignore }))
        })
        l.measure(child, l.width) |> ignore
        l.place(child, 0.0, 0.0)
      }) |> ignore
    }) |> ignore
  })
  t.frame(1000.0, 200.0, now=0.0) |> ignore
  assert_eq((leaf.val.unwrap().rect().0, t.work.computes), (30.0, 1))
  t.dispose()
}
