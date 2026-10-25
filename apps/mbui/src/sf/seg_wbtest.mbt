// The segmented choices (seg.mbt's Seg, the narrow pages'; parts.mbt's segmented, the wide pages'): what they do short
// of room.

///|
test "a filling Seg short of room for equal shares: each option's words whole, the longer ones as wide as they need, the rest sharing what is left, all in its track" {
  let parts = ["Android", "Desktop", "Web", "Station", "Cloud"]
  // a phone 340 wide, the changelog's tabs 16 in from its sides (about.mbt cl_narrow_tabs): 61 a part, less than the
  // longer words need
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { seg(c, "parts", parts, 0, fill=true, height=34.0) |> ignore }) |> ignore
      })
    },
    w=340.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  let mut upto = 16.0
  for words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
    let (x, _, w, _) = t.get(@ui.Radio, label=words).rect
    assert_true(x >= upto - 0.5, msg=words)
    upto = x + w
  }
  assert_true(upto <= 324.5)
  // the short ones more than their words and 8 either side, the long ones that alone
  for words in parts {
    let (_, _, option, _) = t.get(@ui.Radio, label=words).rect
    let (_, _, need, _) = t.rect_of(words).unwrap()
    if words == "Web" || words == "Cloud" {
      assert_true(option > need + 16.5, msg=words)
    } else {
      assert_true((option - need - 16.0).abs() < 0.5, msg=words)
    }
  }
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a filling Seg whose options' words alone come to more than its track: the shorter whole, the longer cut short alike, all in the track, nothing scrolled" {
  let parts = ["Android", "Desktop", "Web", "Station", "Cloud"]
  let chosen = Ref::new(4)
  // 260 wide: 224 in the track for options whose words with the least either side need 243
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() {
          chosen.val = seg(c, "parts", parts, chosen.val, fill=true, height=34.0)
        })
        |> ignore
      })
    },
    w=260.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  let before = option_rects(t, parts)
  // side by side in the track (16 in, 2 inside it), each one's words in it
  let mut upto = 17.5
  for i, words in parts {
    let (x, _, w, _) = before[i]
    assert_true(x >= upto - 0.01, msg=words)
    upto = x + w
    let (wx, _, ww, _) = t.rect_of(words).unwrap()
    assert_true(wx >= x && wx + ww <= x + w + 0.5, msg=words)
  }
  assert_true(upto <= 242.5)
  // (the shorter whole, the longer as wide as each other, cut)
  assert_eq(t.lines_of("Web"), ["Web"])
  assert_eq(t.lines_of("Cloud"), ["Cloud"])
  assert_true(t.lines_of("Android")[0].has_suffix("…"))
  assert_true((before[0].2 - before[1].2).abs() < 0.01 && (before[0].2 - before[3].2).abs() < 0.01)
  assert_eq(t.squeeze_faults(), [])
  // the first tapped: chosen, nothing moved
  t.tap(before[0].0 + before[0].2 / 2.0, before[0].1 + before[0].3 / 2.0)
  t.draw()
  assert_eq(chosen.val, 0)
  assert_eq(option_rects(t, parts), before)
}

///|
test "a filling Seg whose options' words need more than its track on one line: the longer wrapped between its words, all as tall, the track round them" {
  let parts = ["Settings", "Software and devices"]
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { seg(c, "parts", parts, 1, fill=true, height=34.0) |> ignore }) |> ignore
      })
    },
    w=200.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  assert_eq(t.lines_of("Settings"), ["Settings"])
  let lines = t.lines_of("Software and devices")
  assert_true(lines.length() > 1, msg="\{lines}")
  // (broken between its words only)
  assert_eq(lines.join(""), "Software and devices")
  for l in lines[:lines.length() - 1] {
    assert_true(l.has_suffix(" "), msg="\{lines}")
  }
  let (x0, y0, w0, h0) = t.get(@ui.Radio, label="Settings").rect
  let (x1, y1, w1, h1) = t.get(@ui.Radio, label="Software and devices").rect
  assert_true(x0 >= 17.5 && x0 + w0 <= x1 + 0.5 && x1 + w1 <= 182.5)
  assert_eq((y0, h0), (y1, h1))
  assert_true(h1 > 34.0)
  assert_eq(t.squeeze_faults(), [])
}

///|
test "segmented short of room for its equal columns: the longer as wide as its words with their sides, the other the rest; given the room again, equal columns" {
  let parts = ["Settings", "Software and devices"]
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { segmented(c, "parts", parts, 1) |> ignore }) |> ignore
      })
    },
    w=320.0,
    h=200.0,
  )
  t.draw()
  let widths = fn() raise { option_rects(t, parts).map(fn(r) { r.2 }) }
  // (the longer's words with 12 either side, in the theme's size of words at this width)
  let need = fn() { t.rect_of("Software and devices").unwrap().2 + 2.0 * segmented_in }
  for words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
  }
  let short = widths()
  assert_true((short[1] - need()).abs() < 1.0, msg="\{short} \{need()}")
  assert_true(short[0] < short[1])
  let (x0, _, _, _) = t.get(@ui.Radio, label="Settings").rect
  let (x1, _, w1, _) = t.get(@ui.Radio, label="Software and devices").rect
  assert_true(x0 >= 16.0 && x1 + w1 <= 304.5)
  assert_eq(t.squeeze_faults(), [])
  t.resize(600.0, 200.0)
  t.draw()
  let wide = widths()
  assert_true((wide[0] - wide[1]).abs() < 0.5 && (wide[1] - need()).abs() < 1.0, msg="\{wide} \{need()}")
  t.resize(320.0, 200.0)
  t.draw()
  assert_eq(widths(), short)
}

///|
test "option_widths: alike, none narrower than its words and sides; then their sides narrower; then the longest wrapped first, alike; then all wrapped, their sides narrower; then the longer cut short" {
  // words 40, 100 and 60 wide on one line (40, 50 and 60 wrapped: one word), 12 either side, 8 at the least
  let at = fn(room : Double) { option_widths([40.0, 100.0, 60.0], [40.0, 50.0, 60.0], room, 12.0, 8.0) }
  assert_eq(at(450.0), ([150.0, 150.0, 150.0], OneLine))
  // (the longer's 124 its own, the others sharing the rest)
  assert_eq(at(300.0), ([88.0, 124.0, 88.0], OneLine))
  // (their sides 10)
  assert_eq(at(260.0), ([60.0, 120.0, 80.0], OneLine))
  // (the longest wrapped: 64, 74 and 84 at least, alike where they may)
  assert_eq(at(240.0), ([78.0, 78.0, 84.0], Wrapped))
  // (all wrapped and their sides 8: 56, 66 and 76 at least)
  assert_eq(at(210.0), ([67.0, 67.0, 76.0], Wrapped))
  // (cut short: the first whole in its 56, the others alike in what is left)
  let (cut, lie) = at(180.0)
  assert_eq(lie, CutShort)
  assert_eq(cut, [56.0, 62.0, 62.0])
}

///|
/// Where each option is (x, y, w, h), as the semantics tree has them.
fn option_rects(t : @ui.Tester, labels : Array[String]) -> Array[(Double, Double, Double, Double)] raise {
  let out = []
  for words in labels {
    out.push(t.get(@ui.Radio, label=words).rect)
  }
  out
}

///|
/// Where the Seg is: a phone's page, 16 in from its sides.
// kept across runs: a value (no field of it changes)
let seg_test_room : @ui.Style = @ui.css("w=Full px=S4")
