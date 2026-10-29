///|
/// The grounds drawn now in `colour`'s hue (its opacity aside).
fn grounds_in(t : @ui.Tester, colour : Int64) -> Array[(Double, Double, Double, Double, Int64)] {
  t.drawn_rects().filter(fn(r) { r.4 >> 8 == colour >> 8 && (r.4 & 0xFFL) != 0L })
}

///|
test "a passage found in words, its spaces and line breaks aside; none where it is not" {
  let text = "先说结论：只建屏幕上看得见的行，其余的行按估计的高度占位。\n做了什么"
  assert_eq(@sf.find_passage(text, "其余的行按估计的高度占位"), Some((16, 28)))
  // its line break and spaces as one space, either side
  assert_eq(@sf.find_passage("one two\nthree", "two   three"), Some((4, 13)))
  assert_eq(@sf.find_passage("one two\nthree", " two\n\nthree "), Some((4, 13)))
  // a letter in two code units (an emoji) kept whole
  assert_eq(@sf.find_passage("看 🎉 这里", "🎉 这里"), Some((2, 7)))
  assert_eq(@sf.find_passage(text, "没有这一段"), None)
  assert_eq(@sf.find_passage(text, " \n "), None)
}

///|
test "a quote's card pressed: the list goes to the message it quotes, and only the passage it quotes is lit there" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  let quote = t.words().filter(fn(w) { w.0.has_prefix("Claude") && w.0.contains("其余的行按估计的高度占位") })
  let (_, qx, qy, qw, qh, _) = quote[0]
  t.tap(qx + qw / 2.0, qy + qh / 2.0)
  // (the middle of its hold, from when it began)
  let held = flash_rest() - flash_ms + (flash_in_ms + flash_held_ms) / 2.0
  if held > t.time() {
    t.run_for(held - t.time())
  }
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_eq(rd.flash, "ts3")
  let p = @sf.theme().p
  // no band across the list: the message is not lit whole
  assert_eq(grounds_in(t, p.accent_bg).length(), 0)
  // the passage's lines on the accent's ground, as a passage picked is, over the words that have it
  let marks = grounds_in(t, p.accent)
  assert_true(marks.length() >= 1)
  let (wx, wy, ww, wh) = t.rect_of("其余的行按估计的高度占位").unwrap()
  for m in marks {
    let (mx, my, mw, mh, colour) = m
    assert_true(mx >= wx - 0.5 && mx + mw <= wx + ww + 0.5)
    assert_true(my >= wy - 0.5 && my + mh <= wy + wh + 0.5)
    // (narrower than the words' paragraph: the passage, not the whole of it)
    assert_true(mw < ww - 1.0 || marks.length() > 1)
    assert_true(((colour & 0xFFL).to_double() / 255.0 - @sfbase.picked_alpha).abs() < 0.02)
  }
  // a ground a line, round at the passage's two ends alone: its first line's start, its last line's end (here it runs
  // on over two lines, square where it does)
  let lines = t
    .drawn_rect_corners()
    .filter(fn(r) { r.4 >> 8 == p.accent >> 8 && (r.4 & 0xFFL) != 0L })
    .map(fn(r) { r.5 })
  assert_eq(lines.length(), 2)
  let round = @sf.ui_theme().corner(Md)
  assert_eq(lines[0], (round, 0.0, 0.0, round))
  assert_eq(lines[1], (0.0, round, round, 0.0))
  // then gone, nothing of it after
  t.run_for(flash_ms)
  t.draw()
  assert_eq(grounds_in(t, p.accent).length(), 0)
}
