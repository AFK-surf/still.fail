///|
test "faces: a face given marks what names it; what people wrote takes theirs only once one is given" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t)
  // none given: no style changes (the same text records as ever)
  assert_eq(faces_style(true, 0), 0)
  assert_eq(faces_style(false, 5), 0)
  assert_true(face_add(@host.face_text, "/fonts/text.ttf"))
  assert_eq(faces_style(true, 0), @host.style_words)
  assert_eq(faces_style(false, 0), 0)
  assert_true(face_add(5, "/fonts/preview.ttf", weight=400))
  assert_eq(faces_style(false, 5), @host.style_face(5))
  assert_eq(@host.face_of_style(faces_style(true, 5)), 5)
  face_clear(@host.face_text)
  assert_eq(faces_style(true, 0), 0)
  // out of the faces there are
  assert_false(face_add(0, "/fonts/none.ttf"))
  assert_false(face_add(@host.faces_most, "/fonts/none.ttf"))
}

///|
test "faces: a paragraph of what people wrote is shaped in their face's style once it is given, the rest as ever" {
  let words = Ref(true)
  let t = Tester::new(fn(c) { c.rich([span("你好 hello")], words=words.val) |> ignore })
  assert_true(text_cache.fonts.iter().all(fn(f) { (f.style & @host.style_words) == 0 }))
  assert_true(face_add(@host.face_text, "/fonts/text.ttf"))
  // (given: what was shaped before forgotten, shaped again in the face's style)
  assert_eq(text_cache.fonts.length(), 0)
  t.draw()
  assert_true(text_cache.fonts.iter().any(fn(f) { (f.style & @host.style_words) != 0 }))
  words.val = false
  t.draw()
  assert_true(text_cache.fonts.iter().any(fn(f) { (f.style & @host.style_words) == 0 }))
}

///|
test "faces: a Tester starts with none given" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t)
  assert_true(face_add(@host.face_ui, "/fonts/ui.ttf"))
  let t2 = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t2)
  assert_false(face_given(@host.face_ui))
}
