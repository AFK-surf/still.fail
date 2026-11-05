///|
test "a pointer pressed anywhere is told at its event, on a node, an old target and empty room, without frames between" {
  let seen : Array[(Bool, Double)] = []
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.reacts(pointer_pressed, fn(down) { seen.push((down, root.cause_at())) })
    root.box(fn(b) {
      b.width(Is(Some(80.0))).height(Is(Some(40.0))).on_press(fn() { }) |> ignore
    }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
      old(b, fn(c) {
        let id = c.id("old")
        c.box(id~, style=css("w=S20 h=S10"), fn() { }) |> ignore
        c.on_press(id, fn() { })
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  seen.clear()
  let expected : Array[(Bool, Double)] = []
  let held_ms = 17.0
  let between_presses_ms = 19.0
  for x in [20.0, 100.0, 260.0] {
    let at = t.time()
    t.touch_at(0, x, 20.0, at)
    t.advance(held_ms)
    t.touch_at(1, x + 2.0, 20.0, t.time())
    t.touch_at(2, x + 2.0, 20.0, t.time())
    expected.push((true, at))
    expected.push((false, at + held_ms))
    t.advance(between_presses_ms)
  }
  assert_eq(seen, expected)
  assert_false(pointer_pressed())
}
