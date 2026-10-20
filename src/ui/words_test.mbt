// Selection's support (words.mbt), a link held (rich.mbt), a URL handed to the system. The fake host makes Latin 5 px wide at size 10, CJK 10, lines round(1.42 × size) high.

///|
/// Two paragraphs in a box marked as words (`key` "w"), the passage `a` until `b` selected.
fn words_view(sel : Ref[(Int, Int)]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let b = c.column(w=Px(200.0), fn() {
        c.rich([@ui.plain("hello world")], size=10.0) |> ignore
        c.rich([@ui.plain("你好世界")], size=10.0) |> ignore
      })
      c.words(b, "w", a=sel.val.0, b=sel.val.1, color=0x11223344L)
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "words: the paragraphs in a box as one text, a paragraph to a line" {
  let sel = Ref::new((0, 0))
  let t = words_view(sel)
  t.frame()
  let w = t.ctx().words_of("w").unwrap()
  assert_eq(w.text, "hello world\n你好世界")
  assert_eq(w.pieces.length(), 2)
  assert_eq(w.slice(6, 14), "world\n你好")
}

///|
test "words: offsets from a point, past a paragraph's end the next one's start, past all their end" {
  let sel = Ref::new((0, 0))
  let t = words_view(sel)
  t.frame()
  let w = t.ctx().words_of("w").unwrap()
  let p0 = w.pieces[0]
  let p1 = w.pieces[1]
  // on the first line, between "hello" and " " (5 × 5 px)
  assert_eq(w.offset_at(p0.x + 25.0, p0.y + 2.0), 5)
  // the second paragraph's second character
  assert_eq(w.offset_at(p1.x + 12.0, p1.y + 2.0), 12 + 1)
  // above all of it: the first's start; under it: the end
  assert_eq(w.offset_at(0.0, -10.0), 0)
  assert_eq(w.offset_at(0.0, 290.0), w.text.length())
}

///|
test "words: a range's rects cross paragraphs, a line each" {
  let sel = Ref::new((0, 0))
  let t = words_view(sel)
  t.frame()
  let w = t.ctx().words_of("w").unwrap()
  let rs = w.rects(6, 14)
  assert_eq(rs.length(), 2)
  // "world" is 25 wide from 30 in; "你好" 20 from the second's start
  assert_eq(rs[0].2, 25.0)
  assert_eq(rs[1].2, 20.0)
  assert_eq(rs[1].0, w.pieces[1].x)
}

///|
test "words: the selection is drawn behind each paragraph it covers" {
  let sel = Ref::new((6, 14))
  let t = words_view(sel)
  t.frame()
  let grounds = t.drawn_rects().filter(fn(r) { r.4 == 0x11223344L })
  assert_eq(grounds.length(), 2)
  sel.val = (0, 0)
  t.frame()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x11223344L }).length(), 0)
}

///|
test "words: a word as a phone picks one (the host's own boundaries where it has none: letters together, Han alone)" {
  assert_eq(@ui.word_at("hello world", 2), (0, 5))
  assert_eq(@ui.word_at("hello world", 5), (5, 6))
  assert_eq(@ui.word_at("改 v2_beta 了", 4), (2, 9))
  assert_eq(@ui.word_at("你好世界", 2), (2, 3))
  assert_eq(@ui.word_at("", 0), (0, 0))
}

///|
test "words: a box not built this frame is forgotten" {
  let on = Ref::new(true)
  let t = @ui.Tester::new(
    fn(c) {
      if on.val {
        let b = c.column(fn() { c.rich([@ui.plain("abc")], size=10.0) |> ignore })
        c.words(b, "gone")
      }
    },
    w=300.0,
    h=300.0,
  )
  t.frame()
  assert_true(t.ctx().words_of("gone") is Some(_))
  on.val = false
  t.frame()
  assert_true(t.ctx().words_of("gone") is None)
}

///|
test "words: moved (a page sliding in to its place): the frame built again, what was placed from them placed where they are" {
  let dx = Ref::new(0.0)
  let placed = Ref::new(-1.0)
  let t = @ui.Tester::new(
    fn(c) {
      match c.words_of("m") {
        Some(w) => placed.val = w.pieces[0].x
        None => ()
      }
      let b = c.box(tx=dx.val, fn() { c.rich([@ui.plain("abc")], size=10.0) |> ignore })
      c.words(b, "m")
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  let x0 = t.ctx().words_of("m").unwrap().pieces[0].x
  dx.val = 10.5
  // one frame: built from where they were, laid out further on, built again in it from where they are now (no frame
  // drawn with them as they were)
  t.frame(ms=0.0)
  assert_eq(placed.val, x0 + 10.5)
  t.assert_idle()
}

///|
test "a press taken by the app is no tap of what it went down on, and scrolls nothing" {
  let taps = Ref::new(0)
  let take = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      let id = c.id("b")
      if c.clicked(id) {
        taps.val += 1
      }
      if take.val && c.pressed(id) {
        c.take_press()
      }
      c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.tap(50.0, 20.0)
  t.draw()
  assert_eq(taps.val, 1)
  take.val = true
  t.press_at(50.0, 20.0)
  t.release(50.0, 20.0)
  t.draw()
  assert_eq(taps.val, 1)
}

///|
test "a link held still a long press's time: its hold told once, with where it leads and its piece of line; no tap" {
  let held : Array[(String, (Double, Double, Double, Double))] = []
  let tapped : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(200.0), fn() {
        c.rich(
          [@ui.plain("see "), @ui.link("docs", "https://example.com/d")],
          size=10.0,
          on_link=fn(h) { tapped.push(h) },
          on_link_hold=Some(fn(h, r) { held.push((h, r)) }),
        )
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.frame()
  let (x, y, w, h) = t.run_rects("docs")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq(held.length(), 1)
  assert_eq(held[0].0, "https://example.com/d")
  assert_eq((held[0].1).2, w)
  assert_eq(tapped.length(), 0)
  // a quick tap is the link's
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq(tapped, ["https://example.com/d"])
  assert_eq(held.length(), 1)
}

///|
test "a URL handed to the system (the fake host keeps it)" {
  let t = @ui.Tester::new(fn(c) { ignore(c) }, w=100.0, h=100.0)
  t.frame()
  assert_true(t.ctx().open_url("https://still.fail/x"))
  assert_eq(t.opened(), ["https://still.fail/x"])
}

///|
test "words: under a Tester over a host's kept text, the host's own word as it said it; one it did not say is told" {
  // the host found 中文分词 a word of four (a dictionary's), where this one's own takes a Han character alone
  let kept = "TEXTREC {\"wa\":[\"中文分词很好\",1],\"r\":[0,4]}"
  // (a page of no words: what is asked of the host's text is the word alone)
  let t = @ui.Tester::new(fn(c) { c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }, text=kept)
  t.draw()
  assert_eq(@ui.word_at("中文分词很好", 1), (0, 4))
  assert_eq(t.text_missing(), [])
  // not kept: none made up in its place, and the test is told what its host was not asked
  ignore(@ui.word_at("中文分词很好", 5))
  assert_true(t.text_missing().iter().any(fn(m) { m.contains("wa|") }))
}
