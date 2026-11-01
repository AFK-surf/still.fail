///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 0.000001
}

///|
test "the system's size of words, as Compose sets sp: a factor below 1.03 and past 2, its curve between" {
  // as it is, and just over it: a factor
  assert_true(near(@ui.sp_at(1.0, 15.0), 15.0))
  assert_true(near(@ui.sp_at(1.02, 10.0), 10.2))
  // at 1.3, a table's point, between two points, under the first (from 0), past the last (its factor, 1)
  assert_true(near(@ui.sp_at(1.3, 14.0), 18.8))
  assert_true(near(@ui.sp_at(1.3, 15.0), 19.5))
  assert_true(near(@ui.sp_at(1.3, 4.0), 5.2))
  assert_true(near(@ui.sp_at(1.3, 30.0), 30.0))
  assert_true(near(@ui.sp_at(1.3, 200.0), 200.0))
  // a letter spacing drawn closer: as far, the other way
  assert_true(near(@ui.sp_at(1.3, -4.0), -5.2))
  // between 1 (as it is) and 1.15, two thirds along: 15 → 15 and 17.25
  assert_true(near(@ui.sp_at(1.1, 15.0), 16.5))
  // past 2: the factor
  assert_true(near(@ui.sp_at(2.5, 10.0), 25.0))
}

///|
test "words follow the system's size of words from the next frame, said with their line" {
  let t = @ui.Tester::new(fn(c) {
    // (in a row: as wide as the words)
    c.box(dir=Row, fn() { c.text("Sized words", size=15.0, line=20.0, wrap=false) |> ignore }) |> ignore
  })
  let (_, _, w1, h1) = t.rect_of("Sized words").unwrap()
  assert_true(near(h1, 20.0))
  t.set_font_scale(1.3)
  t.draw()
  let (_, _, w2, h2) = t.rect_of("Sized words").unwrap()
  // the line as Compose sets 20sp at 1.3; the words wider by 19.5 / 15
  assert_true(near(h2, 23.6), msg="\{h2}")
  assert_true((w2 / w1 - 1.3).abs() < 0.02, msg="\{w1} \{w2}")
  // the tape says it, and a Tester drawing the tape again draws by it
  t.start_tape()
  t.frame()
  let tape = t.tape()
  assert_true(tape.contains("\"font\":1.3"), msg=tape)
  t.set_font_scale(1.0)
  t.frame()
  assert_true(near(t.rect_of("Sized words").unwrap().3, 20.0))
}

///|
test "a line in ems follows the drawn size for plain and rich words" {
  let t = @ui.Tester::new(fn(c) {
    c.text("Plain words", size=20.0, line_em=1.7) |> ignore
    c.rich([@ui.plain("Rich words")], size=20.0, line_em=1.7) |> ignore
  })
  t.set_font_scale(1.5)
  t.draw()
  let height = @ui.sp_at(1.5, 20.0) * 1.7
  assert_true(near(t.rect_of("Plain words").unwrap().3, height))
  assert_true(near(t.rect_of("Rich words").unwrap().3, height))
}
