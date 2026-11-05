///|
test "an old target disabled by its holder has no hit rectangle, and has its place again when enabled" {
  let enabled = @signals.signal(true)
  let target = Ref(0)
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("target")
      target.val = id
      c.box(id~, w=Px(80.0), h=Px(60.0), bg=0x3377AAFFL, fn() {  }) |> ignore
      c.clicked(id) |> ignore
    })
    .width(Is(Some(80.0))).height(Is(Some(60.0))).offset(Is((20.0, 30.0)))
    .presses(By(fn() { enabled.get() })) |> ignore
  })
  t.draw()
  let first = t.ctx().rect_of(target.val)
  assert_eq(first, Some((20.0, 30.0, 80.0, 60.0)))
  enabled.set(false)
  t.draw()
  assert_eq(t.ctx().rect_of(target.val), None)
  enabled.set(true)
  t.draw()
  assert_eq(t.ctx().rect_of(target.val), first)
}
