// A theme reveal over the window's retained tree, not just an old view.

///|
test "a theme change reveals the new retained tree over the previous frame" {
  let dark = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(By(fn() { if dark.get() { 0x111111FFL } else { 0xEEEEEEFFL } })) |> ignore
    })
    |> ignore
  })
  t.frame()
  g().reveal_from(100.0, 50.0, dark=fn() { dark.get() })
  dark.set(true)
  t.frame()
  t.run_for(reveal_ms / 4.0)
  assert_true(reveal_spreading())
  let rects = t.drawn_instances().filter(fn(a) { a[5] == 0.0 })
  let light = 238.0 / 255.0
  let night = 17.0 / 255.0
  assert_true(rects.iter().any(fn(a) { (a[8] - light).abs() < 0.002 }), msg="the previous light tree remains under the reveal")
  assert_true(rects.iter().any(fn(a) {
    (a[8] - night).abs() < 0.002 && a[24] > 0.0 && a[24] == a[25] && (a[18] - a[16] - 2.0 * a[24]).abs() < 0.01
  }), msg="the new dark tree is cut to the growing circle")
  t.run_for(reveal_ms)
  t.frame()
  assert_false(reveal_spreading(), msg="the saved frame is let go at the end")
}

///|
test "a retained overlay stays over both themes and takes a press outside the reveal" {
  let dark = @signals.signal(false)
  let open = @signals.signal(false)
  let presses = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(By(fn() { if dark.get() { 0x111111FFL } else { 0xEEEEEEFFL } })) |> ignore
    })
    |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      layer
      .over(Is(true))
      .stacked(Is(1))
      .offset(Is((340.0, 240.0)))
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .ground(Is(0x2244CCFFL))
      .presses(Is(true))
      .on_press(fn() { presses.val += 1 })
      |> ignore
    })
  })
  t.frame()
  g().reveal_from(20.0, 20.0, dark=fn() { dark.get() })
  dark.set(true)
  open.set(true)
  t.frame()
  t.run_for(reveal_ms / 4.0)
  let blue = t.drawn_instances().filter(fn(a) {
    a[5] == 0.0 && (a[8] - 34.0 / 255.0).abs() < 0.002 && (a[10] - 204.0 / 255.0).abs() < 0.002
  })
  assert_eq(blue.length(), 1)
  assert_eq((blue[0][24], blue[0][25], blue[0][26], blue[0][27]), (0.0, 0.0, 0.0, 0.0), msg="the overlay is not cut to the circle")
  t.tap(360.0, 260.0)
  assert_eq(presses.val, 1, msg="the overlay is still interactive")
}
