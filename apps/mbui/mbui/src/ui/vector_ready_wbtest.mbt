// Renderer availability is an outside event, independent of frame count.
///|
test "a pending SVG renderer never falls back to the host SVG decoder and wakes on its ready message" {
  let calls = Ref(0)
  set_vector_pictures(fn(_, _) {
    calls.val += 1
    Some((2, 1, FixedArray::make(8, b'\xFF')))
  })
  set_vector_pictures_ready(None)
  on_message("test.svg", fn(_, _) { set_vector_pictures_ready(Some(true)) })
  let t = Tester::new(fn(c) {
    c.image("mem:waiting-svg", w=Px(100.0), h=Px(50.0), fade=false) |> ignore
  })
  add_image("mem:waiting-svg", b"<svg width='2' height='1'/>")
  t.draw()
  assert_eq(calls.val, 0)
  assert_eq(t.image_loads().length(), 0)
  assert_true(image_awaited("mem:waiting-svg", 200.0))
  t.draw()
  assert_eq(t.image_loads().length(), 0)
  t.post("test.svg", "ready")
  t.draw()
  assert_eq(calls.val, 1)
  assert_eq(t.image_loads().length(), 1)
  assert_false(image_awaited("mem:waiting-svg", 200.0))
  set_vector_pictures(fn(_, _) { None })
}

///|
test "a failed SVG renderer ends waiting and uses the host decode failure path, never raw SVG" {
  let calls = Ref(0)
  set_vector_pictures(fn(_, _) { calls.val += 1; None })
  set_vector_pictures_ready(None)
  let t = Tester::new(fn(c) {
    c.image("mem:failed-svg", w=Px(100.0), h=Px(50.0), fade=false) |> ignore
  }, finish=false)
  add_image("mem:failed-svg", b"<svg width='2' height='1'/>")
  t.draw()
  assert_true(image_awaited("mem:failed-svg", 200.0))
  set_vector_pictures_ready(Some(false))
  t.draw()
  assert_eq(t.image_loads()[0].0, "bytes:0")
  t.finish(1, 1, ok=false)
  t.draw()
  assert_false(image_awaited("mem:failed-svg", 200.0))
  assert_eq(t.failed_images().length(), 1)
  assert_eq(calls.val, 0)
  set_vector_pictures(fn(_, _) { None })
}

///|
test "a picture with its own renderer does not wait for the app renderer" {
  let calls = Ref(0)
  set_vector_pictures(fn(_, _) { calls.val += 1; None })
  set_vector_pictures_ready(None)
  let t = Tester::new(fn(c) {
    c.image("mem:own-svg", w=Px(100.0), h=Px(50.0), fade=false) |> ignore
  })
  add_vector_image("mem:own-svg", b"<svg/>", fn(_, _) { Some((2, 1, FixedArray::make(8, b'\xFF'))) })
  t.draw()
  assert_eq(t.image_loads().length(), 1)
  assert_false(image_awaited("mem:own-svg", 200.0))
  assert_eq(calls.val, 0)
  set_vector_pictures(fn(_, _) { None })
}
