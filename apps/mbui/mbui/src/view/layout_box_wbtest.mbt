///|
test "a custom parent measures the composer before laying out its list in one pass" {
  let composing = @signals.signal(40.0, same=fn(a, b) { a == b })
  let layouts = Ref(0)
  let footer : Ref[View?] = Ref(None)
  let row : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    let composer = root.box(fn(n) {
      footer.val = Some(n)
      n.height(By(fn() { Some(composing.get()) })).ground(Is(0x112233ffL)) |> ignore
    })
    let list = root.box(fn(n) {
      n.layout_box(Is(0), fn(l, _) {
        layouts.val += 1
        let last = l.child("last", fn(n) { row.val = Some(n); n.height(Is(Some(20.0))).ground(Is(0x223344ffL)) |> ignore })
        let size = l.measure(last, l.width)
        l.place(last, 0.0, l.height - size.1)
      }) |> ignore
    })
    root.layout_box(Is(0), fn(l, _) {
      let size = l.measure(composer, l.width)
      l.measure(list, l.width, height=l.height - size.1) |> ignore
      l.place(list, 0.0, 0.0)
      l.place(composer, 0.0, l.height - size.1)
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  assert_eq((t.work.computes, layouts.val), (1, 1))
  assert_eq(t.nodes[row.val.unwrap().at].flex.top, 240.0)
  assert_eq(t.nodes[footer.val.unwrap().at].flex.top, 260.0)
  composing.set(80.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq((t.work.computes, layouts.val), (2, 2))
  assert_eq(t.nodes[row.val.unwrap().at].flex.top, 200.0)
  assert_eq(t.nodes[footer.val.unwrap().at].flex.top, 220.0)
  t.dispose()
}

///|
test "a lazy child keeps its identity and measurements while scrolling, and only leaves when omitted" {
  let offset = @signals.signal(0.0, same=fn(a, b) { a == b })
  let height = @signals.signal(20.0, same=fn(a, b) { a == b })
  let counts = [0, 0]
  let built = Ref(0)
  let dropped = Ref(0)
  let first : Ref[View?] = Ref(None)
  let hidden : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.layout_box(By(fn() { offset.get() }), fn(l, off) {
      if off < 50.0 {
        let a = l.child("a", fn(n) {
          first.val = Some(n)
          built.val += 1
          n.measured(By(fn() { height.get() }), fn(h, w) { counts[0] += 1; (w.unwrap_or(20.0), h) })
          .ground(Is(0x112233ffL)) |> ignore
          n.owns(fn() { dropped.val += 1 }) |> ignore
        })
        l.measure(a, l.width) |> ignore
        l.place(a, 0.0, off)
      }
      let b = l.child("b", fn(n) {
        hidden.val = Some(n)
        n.measured(Is(0), fn(_, w) { counts[1] += 1; (w.unwrap_or(20.0), 20.0) })
        .ground(Is(0x223344ffL)) |> ignore
      })
      l.measure(b, l.width) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let id = first.val.unwrap().id()
  let measured = counts.copy()
  assert_true(hidden.val.unwrap().alive())
  assert_true(t.out_at(hidden.val.unwrap().at), msg="kept without placing is neither drawn nor hit")
  offset.set(10.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(first.val.unwrap().id(), id)
  assert_eq(counts, measured, msg="scrolling reused both clean subtrees")
  height.set(30.0)
  t.frame(200.0, 300.0, now=20.0) |> ignore
  assert_true(counts[0] > measured[0])
  assert_eq(counts[1], measured[1], msg="one child's content did not remeasure the other")
  offset.set(60.0)
  t.frame(200.0, 300.0, now=30.0) |> ignore
  assert_false(first.val.unwrap().alive())
  assert_eq((built.val, dropped.val), (1, 1))
  offset.set(0.0)
  t.frame(200.0, 300.0, now=40.0) |> ignore
  assert_true(first.val.unwrap().id() != id, msg="an omitted key does not resurrect its released node")
  assert_eq(built.val, 2)
  t.dispose()
}

///|
test "panic a lazy layout cannot change its sibling" {
  let t = Tree::new(fn(root) {
    let sibling = root.box(fn(n) { n.height(Is(Some(20.0))) |> ignore })
    root.box(fn(n) {
      n.width(Is(Some(100.0))).height(Is(Some(100.0)))
      .layout_box(Is(0), fn(_, _) { sibling.height(Is(Some(30.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}

///|
test "reordering lazy children changes their paint order without rebuilding either" {
  let reverse = @signals.signal(false, same=fn(a, b) { a == b })
  let built = Ref(0)
  let t = Tree::new(fn(root) {
    root.layout_box(By(fn() { reverse.get() }), fn(l, rev) {
      let keys = if rev { ["b", "a"] } else { ["a", "b"] }
      for k in keys {
        let child = l.child(k, fn(n) {
          built.val += 1
          n.height(Is(Some(20.0))).ground(Is(if k == "a" { 0x112233ffL } else { 0x223344ffL })) |> ignore
        })
        l.measure(child, l.width) |> ignore
        l.place(child, 0.0, 0.0)
      }
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let before = t.root().kids().map(fn(n) { n.id() })
  reverse.set(true)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(t.root().kids().map(fn(n) { n.id() }), [before[1], before[0]])
  assert_eq(built.val, 2)
  t.dispose()
}

///|
test "panic a lazily created component's first reaction cannot dirty a sibling" {
  let value = @signals.signal(30.0)
  let t = Tree::new(fn(root) {
    let sibling = root.box(fn(n) { n.height(Is(Some(20.0))) |> ignore })
    root.box(fn(n) {
      n.width(Is(Some(100.0))).height(Is(Some(100.0)))
      .layout_box(Is(0), fn(l, _) {
        l.child("a", fn(child) {
          child.reacts(fn() { value.get() }, fn(v) { sibling.height(Is(Some(v))) |> ignore })
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}
