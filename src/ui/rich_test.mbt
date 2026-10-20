// The fake host makes Latin 5 px wide at size 10 (6 in the code face), CJK
// 10, lines round(1.42 × size) high.

///|
fn rich_view(
  runs : Array[@ui.Run],
  w : Double,
  on_link? : (String) -> Unit = fn(_) {  },
  code_scale? : Double = 1.0,
) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.column(w=Px(w), fn() {
        c.rich(runs, size=10.0, code_scale~, on_link~, pressed_bg=0x11223344L)
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a paragraph of runs wraps as one text: a word across runs stays whole" {
  // "cd" bold and "ef" plain make one word, kept on one line
  let t = rich_view(
    [@ui.plain("ab "), @ui.bold("cd"), @ui.plain("ef 你好世界")],
    30.0,
  )
  assert_eq(t.lines_of("ab"), ["ab ", "cdef ", "你好世", "界"])
}

///|
test "Chinese and Latin mixed across styled runs break where UAX #14 allows" {
  let t = rich_view(
    [
      @ui.plain("这是"),
      @ui.italic("italic"),
      @ui.plain("和"),
      @ui.strike("struck"),
      @ui.plain("，「引用」好"),
    ],
    60.0,
  )
  let lines = t.lines_of("这是")
  // nothing is lost or doubled, a word in a run never splits, the comma
  // stays with the word before it, the opening bracket with the one after
  assert_eq(lines.join(""), "这是italic和struck，「引用」好")
  assert_eq(lines, ["这是italic和", "struck，「引", "用」好"])
}

///|
test "a code run has room either side of its words, on its ground" {
  let t = rich_view([@ui.plain("a "), @ui.code("x"), @ui.plain(" b")], 200.0)
  // the code face's x is 6 wide, and 3 of room either side
  let rs = t.run_rects("x")
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].2, 12.0)
  // its ground is drawn behind it
  let grounds = t
    .drawn_rects()
    .filter(fn(r) { r.4 == 0x7676801FL })
  assert_eq(grounds.length(), 1)
  assert_eq(grounds[0].2, 12.0)
}

///|
test "a larger run makes its line taller; the runs share a baseline" {
  let t = rich_view([@ui.plain("small "), @ui.span("BIG", scale=2.0)], 200.0)
  let (_, _, _, h) = t.rect_of("small").unwrap()
  // the paragraph's lines are 14, the big run's 28
  assert_eq(h, 28.0)
  let glyphs = t.drawn_glyphs()
  // the fake glyphs hang 10 above the baseline: all on one
  let y0 = glyphs[0].1
  assert_true(glyphs.iter().all(fn(g) { g.1 == y0 }))
}

///|
test "a link is tapped, held it shows pressed, and it says where it leads" {
  let went = []
  let t = rich_view(
    [@ui.plain("read "), @ui.link("the docs", "https://example.com/docs"), @ui.plain(" now")],
    200.0,
    on_link=fn(href) { went.push(href) },
  )
  let (x, y, w, h) = t.run_rects("the docs")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x11223344L }))
  t.release(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(went, ["https://example.com/docs"])
  // the words around it lead nowhere
  t.tap_run("now")
  assert_eq(went.length(), 1)
}

///|
test "a link that wraps is one target on each of its lines" {
  let went = []
  let t = rich_view(
    [@ui.plain("go "), @ui.link("one two three", "x://y"), @ui.plain(" end")],
    40.0,
    on_link=fn(href) { went.push(href) },
  )
  let rs = t.run_rects("one two three")
  assert_true(rs.length() >= 2)
  let (x, y, w, h) = rs[rs.length() - 1]
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(went, ["x://y"])
}

///|
test "strikethrough and the layout's offsets, carets and rects" {
  let t = rich_view([@ui.plain("ab"), @ui.strike("cd"), @ui.plain("\nef")], 200.0)
  // the line through "cd": 10 wide
  assert_true(t.drawn_rects().iter().any(fn(r) { r.2 == 10.0 && r.3 == 1.0 }))
  let (rl, _, _) = t.rich_of("ab").unwrap()
  assert_eq(rl.line_count(), 2)
  assert_eq(rl.offset_at(12.0, 3.0), 2)
  assert_eq(rl.offset_at(100.0, 20.0), 7)
  let (x, top, h) = rl.caret(5)
  assert_eq((x, top, h), (0.0, 14.0, 14.0))
  // a selection over the break: a rect on each line
  assert_eq(rl.rects(1, 6), [(5.0, 0.0, 15.0, 14.0), (0.0, 14.0, 5.0, 14.0)])
  assert_eq(rl.run_at(2), 1)
}

///|
test "max_lines: a paragraph cut after that many lines, the last ending in an ellipsis, the runs before kept" {
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(60.0), fn() {
        c.rich(
          [@ui.plain("ab "), @ui.bold("cd"), @ui.plain(" ef gh ij kl mn op")],
          size=10.0,
          max_lines=1,
        )
        |> ignore
        c.rich([@ui.plain("xy "), @ui.bold("zw")], size=10.0, max_lines=1)
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  let lines = t.lines_of("ab")
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix("ab cd ef"))
  assert_true(lines[0].has_suffix("…"))
  // the bold run is where it was
  assert_eq(t.run_rects("cd").length(), 1)
  // what fits is not cut
  assert_eq(t.lines_of("xy"), ["xy zw"])
}

///|
test "the same words in runs whose ranges moved (as many runs): drawn in the runs as they are now" {
  let red = 0xFF0000FFL
  let ink = 0x000000FFL
  let runs = Ref([@ui.span("ab", color=red), @ui.plain("cd")])
  let t = @ui.Tester::new(
    fn(c) {
      // in a box of its own size, laid out as before: only the paragraph's runs change
      c.box(w=Px(200.0), h=Px(40.0), fn() { c.rich(runs.val, size=10.0, color=ink) |> ignore }) |> ignore
    },
    w=300.0,
    h=100.0,
  )
  t.frame()
  let colors = fn() {
    let g = t.drawn_glyphs().copy()
    g.sort_by(fn(a, b) { a.0.compare(b.0) })
    g.map(fn(x) { x.2 })
  }
  assert_eq(colors(), [red, red, ink, ink])
  // the red one word on: still two runs, the same words
  runs.val = [@ui.span("abc", color=red), @ui.plain("d")]
  t.frame()
  assert_eq(colors(), [red, red, red, ink])
  // and back, shorter
  runs.val = [@ui.span("a", color=red), @ui.plain("bcd")]
  t.frame()
  assert_eq(colors(), [red, ink, ink, ink])
}

///|
test "a paragraph cut after its max_lines, drawn again in later frames as it was: its cut kept with its layout" {
  let red = 0xFF0000FFL
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(60.0), fn() {
        c.rich([@ui.plain("ab "), @ui.span("cd", color=red), @ui.plain(" ef gh ij kl mn op")], size=10.0, max_lines=1)
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  let first = t.drawn_glyphs().map(fn(g) { g.2 })
  // frames after: the layout kept, the runs it was cut into with it (the ellipsis a run of its own)
  t.frame()
  t.frame()
  assert_eq(t.drawn_glyphs().map(fn(g) { g.2 }), first)
  assert_eq(first.filter(fn(k) { k == red }).length(), 2)
  assert_true(t.lines_of("ab")[0].has_suffix("…"))
}
