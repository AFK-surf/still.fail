// Letter spacing and a most of lines (Ctx::text tracking, max_lines; TextStyle's).

///|
/// The x of each glyph drawn in the last frame, left to right.
fn glyph_xs(t : Tester) -> Array[Double] {
  ignore(t)
  let c = g()
  let xs = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      xs.push(c.inst[b])
    }
  }
  xs
}

///|
test "letter spacing: each cluster's advance has it, its piece drawn half of it in, as Android spaces letters" {
  let spaced = Ref(false)
  let t = Tester::new(
    fn(c) {
      c.column(align=AStart, fn() {
        if spaced.val {
          c.text("abcd", tracking=2.0) |> ignore
        } else {
          c.text("abcd") |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  // the fake host's Latin is 7.5 wide at 15
  let (_, _, w0, _) = t.rect_of("abcd").unwrap()
  assert_eq(w0, 30.0)
  let xs0 = glyph_xs(t)
  spaced.val = true
  t.draw()
  let (_, _, w1, _) = t.rect_of("abcd").unwrap()
  assert_eq(w1, 38.0)
  let xs1 = glyph_xs(t)
  assert_eq(xs1.length(), 4)
  for k in 0..<4 {
    assert_eq(xs1[k] - xs0[k], 1.0 + 2.0 * k.to_double())
  }
}

///|
test "letter spacing in ems from a style's token, and wrapping by the spaced widths" {
  let t = Tester::new(
    fn(c) {
      c.column(w=Px(80.0), align=AStart, fn() {
        // Widest: 0.1 em, 1.5 at 15: a letter 9 wide, so "aaaa bbbb" (81) does not fit 80
        c.text("aaaa bbbb", style=text_style(tracking=Widest)) |> ignore
        c.text("cccc dddd", style=text_style(tracking=Exact(-1.5))) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  assert_eq(t.lines_of("aaaa"), ["aaaa ", "bbbb"])
  // 6 a letter: one line of 54
  assert_eq(t.lines_of("cccc"), ["cccc dddd"])
  let (_, _, w, _) = t.rect_of("cccc").unwrap()
  assert_eq(w, 54.0)
}

///|
test "words with letter spacing are shaped with no ligatures, those without as the font makes them" {
  // (the fake host's U+E000 is a ligature's second letter)
  let _ = Tester::new(fn(_) {  }, w=10.0, h=10.0)
  let plain = shape("a\u{E000}b", 15.0, 400)
  assert_eq(plain.keys[1], -1)
  let spaced = shape("a\u{E000}b", 15.0, 400, spacing=1.0)
  assert_true(spaced.keys[1] >= 0)
  assert_eq(spaced.pad, 0.5)
  // and each in a cache of its own
  assert_eq(shape("a\u{E000}b", 15.0, 400).keys[1], -1)
}

///|
test "max_lines: wrapped words cut after that many lines, the last ending in an ellipsis, the box as high as they" {
  let t = Tester::new(
    fn(c) {
      c.column(w=Px(80.0), align=AStart, fn() {
        c.text("one two three four five six seven", line=20.0, max_lines=2) |> ignore
        c.text("short", line=20.0, max_lines=2) |> ignore
        c.text("eight nine ten eleven twelve", style=text_style(max_lines=1)) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  // 7.5 a letter: "one two " fits 80; the second line has what follows up to what fits with the dots (9 and the dots)
  assert_eq(t.lines_of("one two"), ["one two ", "three fou…"])
  let (_, _, _, h) = t.rect_of("one two").unwrap()
  assert_eq(h, 40.0)
  assert_eq(t.lines_of("short"), ["short"])
  assert_eq(t.lines_of("eight"), ["eight nin…"])
}

///|
test "max_lines: a line break ends the last line where it is, the dots after it" {
  let t = Tester::new(
    fn(c) {
      c.column(w=Px(200.0), align=AStart, fn() {
        c.text("first\nsecond\nthird", max_lines=2) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  assert_eq(t.lines_of("first"), ["first\n", "second…"])
}

///|
test "census: words' letter spacing is part of their size" {
  let t = Tester::new(
    fn(c) {
      c.column(fn() {
        c.text("a", line=20.0) |> ignore
        c.text("b", line=20.0, tracking=-0.6) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  assert_eq(t.census().text, ["15/20", "15/20 -0.6"])
}

///|
test "letter spacing in rich text: every run's clusters, in the code face too" {
  let spaced = Ref(false)
  let t = Tester::new(
    fn(c) {
      c.column(align=AStart, fn() {
        c.rich([plain("ab"), span("cd", mono=true)], tracking=if spaced.val { 2.0 } else { 0.0 }) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  let (_, _, w0, _) = t.rect_of("abcd").unwrap()
  let xs0 = glyph_xs(t)
  spaced.val = true
  t.draw()
  let (_, _, w1, _) = t.rect_of("abcd").unwrap()
  assert_eq(w1 - w0, 8.0)
  let xs1 = glyph_xs(t)
  assert_eq(xs1.length(), 4)
  for k in 0..<4 {
    assert_eq(xs1[k] - xs0[k], 1.0 + 2.0 * k.to_double())
  }
}

///|
test "words with letter spacing are copied as they were written: what is shaped with no ligatures stays the host's" {
  // (U+E000: the fake host's ligature's second letter, made none by the spacing)
  let words = "office fi\u{E000}les"
  let t = Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), fn() {
        c.selectable(fn() { c.rich([plain(words)], tracking=1.0) |> ignore })
        c.text(words, tracking=1.0) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (_, y, _, h) = t.rect_of(words).unwrap()
  t.drag(1.0, y + h / 2.0, 390.0, y + h / 2.0)
  assert_eq(t.ctx().selected_text(), words)
  t.key(13, mods=8)
  assert_eq(t.clipboard(), words)
  assert_false(t.clipboard().contains("\u{200C}"))
  // and the plain text's lines, as shown and read out
  assert_eq(t.lines_of("office").join(""), words)
}
