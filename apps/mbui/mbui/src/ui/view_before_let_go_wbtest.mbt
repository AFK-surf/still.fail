///|
test "what is done as a node is let go before all else (View::before_let_go): it alive still, drawn where it was" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let seen : Ref[(Bool, (Double, Double, Double, Double))?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(120.0))) |> ignore }) |> ignore
    root.show(fn() { shown.get() }, fn(b) {
      b.width(Is(Some(80.0))).height(Is(Some(40.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      b.before_let_go(fn() { seen.val = Some((b.alive(), b.rect())) }) |> ignore
    })
  })
  t.draw()
  t.frame()
  assert_eq(seen.val, None)
  shown.set(false)
  t.frame()
  assert_eq(seen.val, Some((true, (0.0, 120.0, 80.0, 40.0))))
}
