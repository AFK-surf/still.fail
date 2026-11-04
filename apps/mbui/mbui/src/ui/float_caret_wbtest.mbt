// The keyboard's trackpad (iOS's floating cursor: a long press on the space bar) as iOS's own fields have it: a caret
// of its own goes with the finger, not stopping between letters; the field's caret, grey, where it would land; let
// go, the one it drew slides there and is the caret again.

///|
fn float_tester(field : Field) -> Tester {
  let t = Tester::new(
    fn(c) { c.editor("field", font_size=16.0, field~) |> ignore },
    w=300.0,
    h=200.0,
    platform=1,
  )
  t.draw()
  t.tap(4.0, 10.0)
  t.draw()
  t
}

///|
/// The rects drawn last frame in the caret's colour (the default 0x0A84FF): the caret's, the trackpad's.
fn carets_drawn() -> Array[Array[Double]] {
  insts().filter(fn(a) { a[5] == 0.0 && a[8] == 10.0 / 255.0 && a[9] == 132.0 / 255.0 })
}

///|
/// The keyboard's trackpad: begun at (x, y), moved to (x, y) or let go (on_text's, in points).
fn float_at(kind : Int, x : Double, y : Double) -> Unit {
  on_text(kind, "", (x * text_float_unit).to_int(), (y * text_float_unit).to_int())
}

///|
test "the keyboard's trackpad: the caret it draws goes as far as the finger, between letters too; the caret, grey, where it lands" {
  let field = Field::new()
  field.set("hello brave world\nnext one")
  let t = float_tester(field)
  guard carets_drawn() is [c0] else { fail("one caret: \{carets_drawn()}") }
  float_at(text_float_begin, 100.0, 300.0)
  t.draw()
  // a little more than a letter and a half on: the one it draws that far exactly, a little bigger, see-through
  float_at(text_float_move, 113.25, 300.0)
  t.draw()
  guard carets_drawn() is [f] else { fail("only the trackpad's, near the caret: \{carets_drawn()}") }
  assert_eq(f[0] + f[2] / 2.0, c0[0] + c0[2] / 2.0 + 13.25)
  assert_eq(f[2], c0[2] + float_caret_grow_w)
  assert_eq(f[3], c0[3] + float_caret_grow_h)
  assert_true(f[11] < 1.0)
  let landed = field.selection()
  assert_true(landed.0 > 0)
  // past the end of the shorter line under it: the caret, where it lands, drawn too, in grey, at that line's end
  float_at(text_float_move, 200.5, 320.0)
  t.draw()
  let st = g().editors.get(g().focus).unwrap()
  assert_true(st.floating is Some(_))
  assert_eq(carets_drawn().length(), 1)
  let grey = insts().filter(fn(a) { a[5] == 0.0 && a[2] == c0[2] && a[3] == c0[3] && a[8] != 10.0 / 255.0 })
  assert_eq(grey.length(), 1)
  assert_true(grey[0][1] > c0[1])
  assert_eq(field.selection(), (26, 26))
  // (no blinking while it is held: nothing waited for)
  t.run_for(caret_blink_ms * 1.5)
  assert_eq(carets_drawn().length(), 1)
}

///|
test "the keyboard's trackpad: past the words' start and back, the caret turns at once, none of the way past to undo" {
  let field = Field::new()
  field.set("hello brave world")
  let t = float_tester(field)
  t.key(key_end)
  t.draw()
  float_at(text_float_begin, 100.0, 300.0)
  t.draw()
  float_at(text_float_move, -900.0, 300.0)
  t.draw()
  assert_eq(field.selection(), (0, 0))
  // turned back: from as far as it goes (4 short of the words' start) at once, then 30 on from there
  float_at(text_float_move, -880.0, 300.0)
  t.draw()
  let st = g().editors.get(g().focus).unwrap()
  guard st.floating is Some(fc) else { fail("held") }
  assert_eq(fc.x, -4.0)
  float_at(text_float_move, -850.0, 300.0)
  t.draw()
  assert_eq(fc.x, -4.0 + 30.0)
  assert_true(field.selection().0 > 0)
}

///|
test "the keyboard's trackpad let go: the caret it drew slides to where the caret landed, then is the caret, blinking" {
  let field = Field::new()
  field.set("hello brave world\nnext one")
  let t = float_tester(field)
  float_at(text_float_begin, 100.0, 300.0)
  t.draw()
  float_at(text_float_move, 200.5, 320.0)
  t.draw()
  let at = carets_drawn()[0]
  let grey = insts().filter(fn(a) { a[5] == 0.0 && a[2] == caret_w && a[8] != 10.0 / 255.0 })
  assert_eq(grey.length(), 1)
  let sel = field.selection()
  float_at(text_float_end, 0.0, 0.0)
  t.draw()
  // the caret stays where it went
  assert_eq(field.selection(), sel)
  t.run_for(float_caret_back_ms / 2.0)
  guard carets_drawn() is [mid] else { fail("one caret sliding: \{carets_drawn()}") }
  assert_true(mid[0] != at[0])
  assert_true(mid[11] > at[11] && mid[11] < 1.0)
  t.run_for(float_caret_back_ms)
  let st = g().editors.get(g().focus).unwrap()
  assert_true(st.floating is None)
  guard carets_drawn() is [c] else { fail("the caret: \{carets_drawn()}") }
  assert_eq(c[2], caret_w)
  assert_eq(c[11], 1.0)
  // landed where the field's caret was drawn grey as it was let go
  assert_eq((c[0], c[1], c[3]), (grey[0][0], grey[0][1], grey[0][3]))
}
