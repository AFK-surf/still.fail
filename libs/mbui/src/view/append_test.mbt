///|
test "children shown before and after existing siblings keep their layout and input order" {
  let middle = @signals.signal(false)
  let end = @signals.signal(false)
  let chosen = Ref(0)
  let a : Ref[@view.View?] = Ref(None)
  let b : Ref[@view.View?] = Ref(None)
  let c : Ref[@view.View?] = Ref(None)
  let d : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
      a.val = Some(row.box(fn(v) {
        v.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = 1 }) |> ignore
      }))
      row.show(fn() { middle.get() }, fn(v) {
        b.val = Some(v)
        v.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = 2 }) |> ignore
      })
      c.val = Some(row.box(fn(v) {
        v.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = 3 }) |> ignore
      }))
      row.show(fn() { end.get() }, fn(v) {
        d.val = Some(v)
        v.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = 4 }) |> ignore
      })
    }) |> ignore
  })
  t.frame(300.0, 100.0, now=0.0) |> ignore
  assert_eq(a.val.unwrap().rect().0, 0.0)
  assert_eq(c.val.unwrap().rect().0, 20.0)
  t.event(1.0, fn() {
    middle.set(true)
    end.set(true)
  })
  t.frame(300.0, 100.0, now=1.0) |> ignore
  assert_eq(b.val.unwrap().rect().0, 20.0)
  assert_eq(c.val.unwrap().rect().0, 40.0)
  assert_eq(d.val.unwrap().rect().0, 60.0)
  for (x, target) in [(10.0, 1), (30.0, 2), (50.0, 3), (70.0, 4)] {
    assert_true(t.press(x, 10.0))
    assert_eq(chosen.val, target)
  }
  t.event(2.0, fn() {
    middle.set(false)
    end.set(false)
  })
  t.frame(300.0, 100.0, now=2.0) |> ignore
  assert_eq(c.val.unwrap().rect().0, 20.0)
  t.dispose()
}
