// Right-to-left lines, words of joining scripts drawn whole, ligatures: over the fake host (Latin and Hebrew 5 px
// wide at size 10, a cluster per grapheme, U+E000 a ligature's second letter).

///|
fn one_rich(s : String, w? : Double = 300.0) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.column(w=Px(w), fn() { c.rich([@ui.plain(s)], size=10.0) |> ignore }) |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a right-to-left word in a left-to-right line is drawn reversed, carets and taps following it" {
  // "ab אבג": a, b, space, then alef, bet, gimel from right to left
  let t = one_rich("ab \u{5D0}\u{5D1}\u{5D2}")
  let (lay, _, _) = t.rich_of("ab").unwrap()
  assert_eq(lay.xs, [0.0, 5.0, 10.0, 25.0, 20.0, 15.0])
  assert_eq(lay.lv, [0, 0, 0, 1, 1, 1])
  // before alef: its right edge; after gimel (the end): its left edge
  assert_eq(lay.caret(3).0, 30.0)
  assert_eq(lay.caret(4).0, 25.0)
  assert_eq(lay.caret(6).0, 15.0)
  // a tap on alef's right half is before it, on its left half after it
  assert_eq(lay.offset_at(29.0, 5.0), 3)
  assert_eq(lay.offset_at(26.0, 5.0), 4)
  // past the right end: the line's logical end is at gimel's left, so the nearest is alef's start
  assert_eq(lay.offset_at(40.0, 5.0), 3)
  // a selection over the Hebrew word: one box around it
  assert_eq(lay.rects(3, 6), [(15.0, 0.0, 15.0, 14.0)])
}

///|
test "a right-to-left paragraph keeps its numbers left to right" {
  // "אב 12": the paragraph reads right to left; "12" stays in its own order, left of the Hebrew
  let t = one_rich("\u{5D0}\u{5D1} 12")
  let (lay, _, _) = t.rich_of("12").unwrap()
  assert_eq(lay.lv, [1, 1, 1, 2, 2])
  assert_eq(lay.xs, [20.0, 15.0, 10.0, 0.0, 5.0])
}

///|
test "left-to-right text is left as it was" {
  let t = one_rich("hello world")
  let (lay, _, _) = t.rich_of("hello").unwrap()
  assert_eq(lay.lv, [])
  assert_eq(lay.xs[6], 30.0)
}

///|
test "a word in a joining script is one cluster, drawn whole" {
  // Arabic "salam" then a space and "ok": the word's four letters one piece
  let t = one_rich("\u{633}\u{644}\u{627}\u{645} ok")
  let (lay, _, _) = t.rich_of("ok").unwrap()
  assert_eq(lay.starts, [0, 4, 5, 6])
  assert_eq(lay.lens, [4, 1, 1, 1])
  assert_eq(lay.adv[0], 20.0)
  // three pieces drawn: the word, o, k
  assert_eq(t.drawn_glyphs().length(), 3)
}

///|
test "a ligature is drawn by its first cluster over both, its advance shared" {
  // "a" + U+E000 (the fake host's ligature letter) + "b"
  let t = one_rich("a\u{E000}b")
  let (lay, _, _) = t.rich_of("b").unwrap()
  assert_eq(lay.starts, [0, 1, 2])
  assert_eq(lay.keys[1], -1)
  // a 5 wide, U+E000 10 (not Latin): 7.5 each
  assert_eq(lay.adv, [7.5, 7.5, 5.0])
  assert_eq(t.drawn_glyphs().length(), 2)
}

///|
test "the plain text path reorders a right-to-left word too" {
  let t = @ui.Tester::new(
    fn(c) { c.text("ab \u{5D0}\u{5D1}", size=10.0) |> ignore },
    w=300.0,
    h=300.0,
  )
  let xs = t.drawn_glyphs().map(fn(g) { g.0 })
  // a, b, then alef right of bet
  assert_eq(xs.length(), 4)
  assert_eq(xs[0] < xs[1], true)
  assert_eq(xs[2] > xs[3], true)
  assert_eq(xs[3] > xs[1], true)
}

///|
test "brackets reading right to left are drawn mirrored" {
  // "א(ב)": a right-to-left paragraph; "(" is drawn as ")" and ")" as "(" (the fake host's key is the character)
  let t = one_rich("\u{5D0}(\u{5D1})")
  let (lay, _, _) = t.rich_of("(").unwrap()
  assert_eq(lay.keys[1], 0x29)
  assert_eq(lay.keys[3], 0x28)
  // left to right they are left alone
  let t2 = one_rich("a(b)")
  let (lay2, _, _) = t2.rich_of("(").unwrap()
  assert_eq(lay2.keys[1], 0x28)
}
