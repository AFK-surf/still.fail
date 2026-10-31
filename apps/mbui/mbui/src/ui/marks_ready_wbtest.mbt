// Marks drawn onto a picture by the host (draw_marks): whether it is drawn read as often as asked, its PNG taken once,
// by what asks MarkedImage::made.

///|
test "marks drawn: ready read again and again takes nothing; made takes the PNG once, as the host said it, then none" {
  let t = Tester::new(fn(_c) {  }, w=100.0, h=100.0)
  t.marks_by_hand()
  t.marks_make(b"PNG-1")
  let m = draw_marks(b"image", "[]").unwrap()
  assert_true(!m.ready(), msg="not drawn yet")
  t.marks_answer(m.id())
  assert_true(m.ready(), msg="drawn, read once")
  assert_true(m.ready(), msg="read again: still there")
  assert_eq(m.made(), Some(b"PNG-1"), msg="taken")
  assert_true(!m.ready(), msg="taken: no more")
}
