///|
test "a retained editor is found by its changing hint as an old editor is, even with a draft in it" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0)
  let hint = @signals.signal("Write a message")
  let f = Field::new()
  let visible = @signals.signal(true)
  set_view_app(fn(root) {
    root.show(fn() { visible.get() }, fn(p) {
      field(p, f, placeholder_by=fn() { hint.get() }) |> ignore
    })
  })
  t.draw()
  let at = t.find("message").unwrap()
  assert_eq(t.find_last("message"), Some(at))
  assert_true(t.rect_of("message") is Some(_))
  assert_eq(t.words().filter(fn(w) { w.0 == "Write a message" }).length(), 1)
  t.tap(at.0, at.1)
  t.type_text("a draft")
  assert_true(t.get(TextField, label="Write a message").focused)
  assert_true(t.find("message") is Some(_))
  hint.set("Another hint")
  t.draw()
  assert_true(t.find("message") is None)
  assert_true(t.find("Another hint") is Some(_))
  visible.set(false)
  t.draw()
  assert_true(t.find("Another hint") is None)
}

///|
test "a field drawn off during a layout change is found where it takes input, as an old field is" {
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  let f = Field::new()
  set_view_app(fn(root) {
    root.offset(Is((10.0, 20.0))).drawn_off(Is((40.0, 50.0))) |> ignore
    field(root, f, placeholder="Write here").drawn_off(Is((5.0, 6.0))) |> ignore
  })
  t.draw()
  let rect = t.get(TextField, label="Write here").rect
  let at = (rect.0 + rect.2 / 2.0, rect.1 + rect.3 / 2.0)
  assert_eq(t.find("Write here"), Some(at))
  assert_eq(t.find_last("Write here"), Some(at))
  assert_eq(t.rect_of("Write here"), Some(rect))
  assert_eq(t.locate("Write here"), [at])
  assert_eq(t.reachable("Write here"), [at])
  t.tap_text("Write here")
  t.type_text("a draft")
  assert_eq(f.text(), "a draft")
}

///|
test "a retained picture is found by its source and takes input where its tile lies" {
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  let source = @signals.signal("mem:first")
  let presses = Ref(0)
  set_view_app(fn(root) {
    root.offset(Is((20.0, 30.0))).drawn_off(Is((40.0, 50.0))) |> ignore
    root.box(fn(tile) {
      tile.width(Is(Some(80.0))).height(Is(Some(60.0)))
      .image(By(fn() { Some((source.get(), "", 160)) }))
      .presses(Is(true)).on_press(fn() { presses.val += 1 }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(t.locate("img:mem:first"), [(60.0, 60.0)])
  assert_eq(t.reachable("img:mem:first"), [(60.0, 60.0)])
  let at = t.reachable("img:mem:first")[0]
  t.tap(at.0, at.1)
  assert_eq(presses.val, 1)
  source.set("mem:next")
  t.draw()
  assert_eq(t.locate("img:mem:first"), [])
  assert_eq(t.locate("img:mem:next"), [(60.0, 60.0)])
}
