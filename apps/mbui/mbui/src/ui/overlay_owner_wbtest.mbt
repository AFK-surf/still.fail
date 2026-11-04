///|
test "an old view's portalled overlay keeps its owner while pointed at or focused outside the owner's box" {
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let seen : Array[Bool] = []
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, native=Mouse, pointing=Mouse)
  set_view_app(fn(root) {
    let island = old(root, fn(c) {
      c.text("owner") |> ignore
      if open.get() {
        c.overlay("child", initial_focus=0, fn() {
          let id = c.id("action")
          let b = c.box(tx=150.0, ty=50.0, w=Px(60.0), h=Px(44.0), id~, fn() { c.text("action") |> ignore })
          c.focusable(id, node=b)
          c.semantics(b, Button, id~, label="action")
        }) |> ignore
      }
    }).width(Is(Some(80.0))).height(Is(Some(30.0)))
    root.reacts(fn() { old_overlay_in_use(island) }, fn(on) { seen.push(on) })
  })
  t.draw()
  let (x, y) = t.find("action").unwrap()
  assert_true(x > 80.0 && y > 30.0, msg="the portal is outside its owner's box")
  t.move(x, y)
  assert_eq(seen.last(), Some(true))
  t.move(260.0, 140.0)
  assert_eq(seen.last(), Some(false))
  t.tab()
  assert_eq(seen.last(), Some(true), msg="keyboard focus keeps the owner too")
  open.set(false)
  t.draw()
  assert_eq(seen.last(), Some(false), msg="the removed overlay keeps nothing")
}
