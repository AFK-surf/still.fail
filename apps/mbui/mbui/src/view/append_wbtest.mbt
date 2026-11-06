///|
test "a slot laid out beside its anchor does not add boxes to its holder's layout" {
  let row : Ref[View?] = Ref(None)
  let slot : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.box(fn(r) {
      row.val = Some(r)
      r.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
      let anchor = r.box(fn(v) { v.width(Is(Some(20.0))).height(Is(Some(20.0))) |> ignore })
      r.show(fn() { true }, fn(v) { slot.val = v.parent() })
      slot.val.unwrap().beside(anchor.id(), as_wide=true) |> ignore
    }) |> ignore
  })
  let r = row.val.unwrap()
  assert_eq(tree.nodes[r.at].flex.children.length(), 1)
  slot.val.unwrap().box(fn(v) { v.width(Is(Some(20.0))) |> ignore }) |> ignore
  assert_eq(tree.nodes[r.at].flex.children.length(), 1)
  tree.dispose()
}

///|
test "a root box made by a synchronous host keeps its order with the box being added" {
  let t = Tree::new(fn(root) { root.row(Is(true)).height(Is(Some(20.0))) |> ignore })
  t.frame(300.0, 100.0, now=0.0) |> ignore
  let calls = Ref(0)
  let added : Ref[View?] = Ref(None)
  t.on_due(fn() {
    calls.val += 1
    if calls.val == 1 {
      t.frame(300.0, 100.0, now=0.0) |> ignore
    } else if calls.val == 2 {
      added.val = Some(t.root().box(fn(v) {
        v.width(Is(Some(30.0))).height(Is(Some(20.0))) |> ignore
      }))
    }
  })
  let first = t.root().box(fn(v) { v.width(Is(Some(20.0))).height(Is(Some(20.0))) |> ignore })
  t.frame(300.0, 100.0, now=1.0) |> ignore
  assert_true(calls.val >= 2)
  assert_eq(first.rect().0, 0.0)
  assert_eq(added.val.unwrap().rect().0, 20.0)
  t.dispose()
}
