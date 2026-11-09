// Each frame asks the host once for the generation shared by text and frame state.

///|
test "a changing old-view frame asks the host its glyph generation once" {
  let value = @signals.signal(0)
  let t = Tester::new(fn(c) { c.text("行 \{value.get()}") |> ignore }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  t.draw()
  let asked = []
  for i in 1..=3 {
    let before = t.fake.generation_asks
    value.set(i)
    t.draw()
    asked.push(t.fake.generation_asks - before)
  }
  assert_eq(asked, [1, 1, 1])
}

///|
test "a face installed between the frame's two readers moves the generation on at once" {
  let t = Tester::new(fn(c) { c.text("face") |> ignore })
  t.fake.generation_on_face_add.val = true
  // Exercise the first-frame environment path again, with a host that advances on the face add.
  faces_env_read.val = false
  t.set_env("MBUI_FACES", "1:/fonts/ui.ttf")
  t.draw()
  assert_true(face_given(1))
  assert_eq(t.fake.generation, 1)
  assert_eq(text_cache.generation, 1)
  // A later host-side atlas loss is read again at the next frame.
  t.glyphs_moved_on()
  t.draw()
  assert_eq(text_cache.generation, 2)
}

///|
test "an offscreen frame observes a host glyph generation change" {
  let view = fn(c : Ctx) { c.text("offscreen") |> ignore }
  let t = Tester::new(view)
  frame_offscreen(view, 390.0, 844.0, 1.0, 100.0) |> ignore
  t.glyphs_moved_on()
  frame_offscreen(view, 390.0, 844.0, 1.0, 116.0) |> ignore
  assert_eq(text_cache.generation, t.fake.generation)
}
