// What the viewer's two fields do, whatever draws them (an old view's editor or the window's tree): the words being
// written on the picture as it marks (marks_writing, "marks/write") and a box's note (marks_foot_node, "marks/note").
// Each by what a person sees and what the system is told: the words typed drawn, the keyboard told the words and
// where the caret is drawn, a press in them putting the caret there, Enter, the keyboard put away.

///|
/// Marking on a phone, words begun where a finger lifts a third across and down the picture: the tester, where.
fn words_begun() -> (@ui.Tester, Double, Double) raise {
  let t = preview_tester("image", w=390.0, platform=2)
  marks_start()
  t.draw()
  let v = viewer.get().unwrap()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  marking.tool = Words
  t.touch(0, px, py)
  t.touch(2, px, py)
  t.draw()
  assert_true(marking.writing is Some(_), msg="words begun")
  (t, px, py)
}

///|
test "marks' fields: words typed on the picture drawn there; the keyboard told them, its caret after them inside their field" {
  let (t, px, py) = words_begun()
  t.type_text("标注")
  assert_true(t.text_runs().iter().any(fn(r) { r.text.contains("标注") }), msg="the words typed drawn: \{t.text_runs()}")
  assert_eq(t.ime(), (true, "标注", 2, 2), msg="the keyboard told the words, the caret after them")
  let (fx, fy, fw, fh) = t.get(TextField, label=pv("android-chat.marks.write")).rect
  let (x, y, _, h) = t.ime_rect()
  assert_true(x > fx && x <= fx + fw && y >= fy && y + h <= fy + fh + 0.5, msg="the caret told inside its field: \{(x, y, h)} in \{(fx, fy, fw, fh)}")
  // (words begun with their line's middle where the finger lifts: their top 0.65 of their size over it)
  assert_true(
    (fx - px).abs() < 0.5 && (fy - (py - 0.65 * @sfbase.mark_text)).abs() < 0.5,
    msg="its field where the words were begun: \{(fx, fy)} at \{(px, py)}",
  )
  marks_leave()
}

///|
test "marks' fields: words on the picture, a press at their start: the caret put there, told so" {
  let (t, _, _) = words_begun()
  t.type_text("abcd")
  let (fx, fy, _, fh) = t.get(TextField, label=pv("android-chat.marks.write")).rect
  t.touch(0, fx + 1.0, fy + fh / 2.0)
  t.touch(2, fx + 1.0, fy + fh / 2.0)
  t.draw()
  assert_eq(t.ime(), (true, "abcd", 0, 0), msg="the caret at their start: \{t.ime()}")
  marks_leave()
}

///|
test "marks' fields: words on the picture, Enter: put down as a mark of those words, the keyboard let go" {
  let (t, _, _) = words_begun()
  t.type_text("标注")
  t.enter()
  assert_true(marking.writing is None, msg="no longer written")
  assert_true(marking.shapes.iter().any(fn(s) { s.kind == "words" && s.text == "标注" }), msg="a mark of the words")
  assert_true(!t.ime().0, msg="the keyboard let go")
  marks_leave()
}

///|
test "marks' fields: words on the picture, the keyboard put away by the person: the field let go of, the keyboard told so" {
  let (t, _, _) = words_begun()
  t.type_text("标注")
  t.keyboard_gone()
  assert_true(!t.ime().0, msg="the keyboard told no field has it")
  marks_leave()
}

///|
test "marks' fields: a box's note, a line written and Enter: a new line in it, the caret told a line lower in it, the field taller" {
  let (t, _, _, _) = wide_box_noted("")
  // (the note come in, wherever it comes in from)
  t.run_for(note_pop_ms)
  let label = pv("android-chat.annotate.write")
  t.type_text("一")
  let (_, fy1, _, h1) = t.get(TextField, label~).rect
  let (_, y1, _, _) = t.ime_rect()
  t.enter()
  t.type_text("二")
  assert_eq(marking.note_field.text(), "一\n二", msg="a new line, not done")
  let (_, fy2, _, h2) = t.get(TextField, label~).rect
  let (_, y2, _, _) = t.ime_rect()
  // (in the field: it grows up from its foot, its top higher as the caret goes a line down in it)
  assert_true(y2 - fy2 >= y1 - fy1 + 20.0, msg="the caret told a line lower in it: \{y1 - fy1} then \{y2 - fy2}")
  assert_true(h2 >= h1 + 20.0, msg="the field a line taller: \{h1} then \{h2}")
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "二" }), msg="the second line drawn: \{t.text_runs()}")
  marks_leave()
}

///|
test "marks' fields: a box's note, a press at its start: the caret put there, told so" {
  let (t, _, _, _) = wide_box_noted("")
  // (the note come in, wherever it comes in from)
  t.run_for(note_pop_ms)
  t.type_text("abcd")
  let (fx, fy, _, fh) = t.get(TextField, label=pv("android-chat.annotate.write")).rect
  t.touch(0, fx + 1.0, fy + fh / 2.0)
  t.touch(2, fx + 1.0, fy + fh / 2.0)
  t.draw()
  assert_eq(t.ime(), (true, "abcd", 0, 0), msg="the caret at its start: \{t.ime()}, pressed at \{(fx + 1.0, fy + fh / 2.0)}")
  marks_leave()
}
