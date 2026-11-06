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
