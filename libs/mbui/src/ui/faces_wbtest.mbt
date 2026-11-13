///|
test "faces: a face given marks what names it; what people wrote takes theirs only once one is given" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t)
  // none given: no style changes (the same text records as ever)
  assert_eq(faces_style(true, 0), 0)
  assert_eq(faces_style(false, 5), 0)
  assert_true(face_add(@hostapi.face_text, "/fonts/text.ttf"))
  assert_eq(faces_style(true, 0), @hostapi.style_words)
  assert_eq(faces_style(false, 0), 0)
  assert_true(face_add(5, "/fonts/preview.ttf", weight=400))
  assert_eq(faces_style(false, 5), @hostapi.style_face(5))
  assert_eq(@hostapi.face_of_style(faces_style(true, 5)), 5)
  face_clear(@hostapi.face_text)
  assert_eq(faces_style(true, 0), 0)
  // out of the faces there are
  assert_false(face_add(0, "/fonts/none.ttf"))
  assert_false(face_add(@hostapi.faces_most, "/fonts/none.ttf"))
}

///|
test "faces: a paragraph of what people wrote is shaped in their face's style once it is given, the rest as ever" {
  let words = Ref(true)
  let t = Tester::new(fn(c) { c.rich([span("你好 hello")], words=words.val) |> ignore })
  assert_true(text_cache.fonts.iter().all(fn(f) { (f.style & @hostapi.style_words) == 0 }))
  assert_true(face_add(@hostapi.face_text, "/fonts/text.ttf"))
  // (given: what was shaped before forgotten, shaped again in the face's style)
  assert_eq(text_cache.fonts.length(), 0)
  t.draw()
  assert_true(text_cache.fonts.iter().any(fn(f) { (f.style & @hostapi.style_words) != 0 }))
  words.val = false
  t.draw()
  assert_true(text_cache.fonts.iter().any(fn(f) { (f.style & @hostapi.style_words) == 0 }))
}

///|
test "faces: a Tester starts with none given" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t)
  assert_true(face_add(@hostapi.face_ui, "/fonts/ui.ttf"))
  let t2 = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t2)
  assert_false(face_given(@hostapi.face_ui))
}

///|
test "faces: a face given as its file's bytes is given as one from a path; none for no bytes" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore })
  ignore(t)
  assert_true(face_add_bytes(@hostapi.face_code, b"\x00\x01\x00\x00"))
  assert_true(face_given(@hostapi.face_code))
  assert_false(face_add_bytes(@hostapi.face_ui, b""))
  assert_false(face_given(@hostapi.face_ui))
}

///|
test "faces: words laid out before the app's face is given are laid out again in it, nothing else of them changed" {
  // (a settings page's rows, laid out in the system's face, then the face chosen: its words kept their old widths, the
  // new face's letters drawn where the old one's went)
  let shown = Ref(true)
  let t = Tester::new(fn(c) {
    if shown.val {
      c.box(dir=Row, fn() { c.text("lin@example.com", size=14.0, wrap=false) |> ignore }) |> ignore
    }
  })
  t.ui_face_wider(0.1)
  let w0 = t.rect_of("lin@example.com").unwrap().2
  assert_true(face_add(@hostapi.face_ui, "/fonts/ui.ttf"))
  t.draw()
  // each of its 15 letters a tenth of 14 wider
  assert_true((t.rect_of("lin@example.com").unwrap().2 - (w0 + 15.0 * 1.4)).abs() < 0.001)
  // away while the face goes back to the system's, and shown again: in the system's again
  shown.val = false
  t.draw()
  face_clear(@hostapi.face_ui)
  shown.val = true
  t.draw()
  assert_eq(t.rect_of("lin@example.com").unwrap().2, w0)
}

///|
test "faces: words laid out while a face given is on its way are laid out again in it once the host has it" {
  // (a page's face is loaded after it is given: given as the words are built (the share card's, share_face_given), they
  // are laid out in the place's face till it is in; when it is (the host's glyphs moved on, before the next frame or
  // later) they kept those widths, the face's letters drawn where the place's went: 「s till.fa il」)
  let give = Ref(false)
  let t = Tester::new(fn(c) {
    if give.val && !face_given(@hostapi.face_ui) {
      face_add(@hostapi.face_ui, "/fonts/ui.ttf") |> ignore
    }
    c.box(dir=Row, fn() {
      c.text("lin@example.com", size=14.0, wrap=false) |> ignore
      c.rich([span("space.blog")]) |> ignore
    })
    |> ignore
  })
  let w0 = t.rect_of("lin@example.com").unwrap().2
  // given as it is built, on its way: measured as the system's
  give.val = true
  t.draw()
  assert_true(face_given(@hostapi.face_ui))
  assert_eq(t.rect_of("lin@example.com").unwrap().2, w0)
  let shaped = words_shaped_in.untracked()
  // in before the next frame: a tenth of 14 wider a letter
  t.ui_face_wider(0.1)
  t.glyphs_moved_on()
  t.draw()
  assert_true((t.rect_of("lin@example.com").unwrap().2 - (w0 + 15.0 * 1.4)).abs() < 0.001)
  // (a paragraph's kept layout too: its runs said with the faces as they are now)
  assert_eq(words_shaped_in.untracked(), shaped + 1)
  // nothing moved on since: kept as laid out
  t.draw()
  assert_eq(words_shaped_in.untracked(), shaped + 1)
}
