///|
let sample : String =
  #|## 今天的进度
  #|
  #|改好了 **布局** 和 *动画*，见 [说明](https://example.com/notes)。
  #|
  #|- 第一项，`inline code`
  #|- 第二项
  #|  1. nested one
  #|- [x] 做完的事
  #|
  #|> 引用里的一句话
  #|
  #|```sh
  #|moon test
  #|```

///|
test "a message's Markdown: its blocks, their margins collapsed, links and copy" {
  let went = []
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.column(w=Fill(1.0), pad=16.0, fn() {
        @sf.markdown(c, sample, on_link=fn(h) { went.push(h) }) |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
    // (a phone's: its words a finger's size)
    platform=2,
  )
  // the heading first, its top margin dropped
  let (_, hy, _, _) = t.rect_of("今天的进度").unwrap()
  assert_eq(hy, 16.0)
  // the paragraph 6 below the heading's bottom: the heading's margin under it, a paragraph none above (the web's
  // .markdown h2 14 0 6, p 0 0 8, on every screen)
  let (_, hy2, _, hh) = t.rect_of("今天的进度").unwrap()
  let (_, py, _, ph) = t.rect_of("改好了").unwrap()
  assert_eq(py - (hy2 + hh), 6.0)
  // the list 8 below the paragraph: the paragraph's margin under it, a list none above
  let (_, ly, _, _) = t.rect_of("第一项").unwrap()
  assert_eq(ly - (py + ph), 8.0)
  // a tight list's items follow each other with no gap
  let (_, y1, _, h1) = t.rect_of("第一项").unwrap()
  let (_, y2, _, _) = t.rect_of("第二项").unwrap()
  assert_eq(y2, y1 + h1)
  assert_true(t.rect_of("nested one") is Some(_))
  assert_true(t.rect_of("引用里的一句话") is Some(_))
  t.tap_run("说明")
  assert_eq(went, ["https://example.com/notes"])
  t.tap_text("复制")
  assert_eq(t.clipboard(), "moon test")
  assert_true(t.rect_of("已复制") is Some(_))
}

///|
test "a table's cell of only the message's images: them side by side, 160 wide at most, not their names" {
  let drawn : Array[(String, Double)] = []
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      drawn.clear()
      c.column(w=Fill(1.0), pad=16.0, fn() {
        @sf.markdown(
          c,
          "| 网页 | 手机网页 |\n|---|---|\n| ![](web%2Dfolded.png) | ![](phone.png) |\n",
          files=fn(name) {
            // a wide one and a tall one
            let r = if name == "web-folded.png" { 2.0 } else { 0.5 }
            Some({ draw: fn() {  }, image: Some((r, fn(w) { drawn.push((name, w)) })) })
          },
        )
        |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  assert_eq(drawn, [("web-folded.png", 160.0), ("phone.png", 120.0)])
  assert_true(t.find("web") is None)
  assert_true(t.find("网页") is Some(_))
}

///|
test "a paragraph of only the message's images: side by side as one row's height, onto the next row when they don't fit" {
  let text = Ref("")
  let drawn : Array[(String, Double)] = []
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      drawn.clear()
      c.column(w=Fill(1.0), pad=16.0, fn() {
        @sf.markdown(c, text.val, files=fn(name) {
          // a.png and b.png a little taller than wide, the wide ones twice as wide as high
          let r = if name.has_prefix("wide") { 2.0 } else { 0.64 }
          Some({
            draw: fn() {  },
            image: Some(
              (
                r,
                fn(w) {
                  drawn.push((name, w))
                  c.box(w=Px(w), h=Px(w / r), fn() { c.text(name, wrap=false) |> ignore }) |> ignore
                },
              ),
            ),
          })
        })
        |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  text.val = "左边是新做法，右边是现在的：\n\n![](a.png) ![](b.png)\n"
  t.draw()
  t.draw()
  // both on one row, 200 high (the most a row is): as wide as that makes them, 8 apart
  assert_eq(drawn, [("a.png", 128.0), ("b.png", 128.0)])
  let (ax, ay, _, _) = t.rect_of("a.png").unwrap()
  let (bx, by, _, _) = t.rect_of("b.png").unwrap()
  assert_eq(by, ay)
  assert_eq(bx, ax + 128.0 + 8.0)
  // two wide ones (240 each at 120 high) don't fit the message's 358 side by side: each a row of its own, as wide as it
  text.val = "![](wide1.png) ![](wide2.png)"
  t.frame()
  t.frame()
  assert_eq(drawn, [("wide1.png", 358.0), ("wide2.png", 358.0)])
  let (_, y1, _, _) = t.rect_of("wide1.png").unwrap()
  let (_, y2, _, _) = t.rect_of("wide2.png").unwrap()
  assert_eq(y2, y1 + 179.0 + 8.0)
}

///|
test "a table too wide for the message: its columns 14em, not squeezed; scrolled out over the page's margin to its end, its key's in line with the words" {
  let long = "a long cell of words that would wrap to a word or two if squeezed into the message"
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.column(w=Fill(1.0), pad=16.0, fn() {
        @sf.markdown(c, "| 一 | 二 | 三 |\n|---|---|---|\n| one \{long} | two \{long} | three \{long} |\n", bleed=16.0)
        |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  t.draw()
  let column = 14.0 * 13.0 + 24.0
  let (x1, y) = t.drawn_of("one a long").unwrap()
  let (x2, _) = t.drawn_of("two a long").unwrap()
  let (x3, _) = t.drawn_of("three a long").unwrap()
  // at rest its first words in line with the message's (16 in: no card, no room before them); each column 14em of its
  // words (13) and its cells' 12 between them, though the three are wider than the message
  assert_eq(x1, 16.0)
  assert_eq(x2 - x1, column)
  assert_eq(x3 - x2, column)
  // dragged to its end: its key's room in line with the words' right edge (16 in from the right)
  for _ in 0..<4 {
    t.drag(370.0, y + 5.0, 20.0, y + 5.0)
    t.draw()
  }
  t.frame()
  let (x3_end, _) = t.drawn_of("three a long").unwrap()
  // (its last words its end, nothing after them; its copy key past it: 6, 32, 6)
  assert_eq(x3_end + column - 24.0, 390.0 - 16.0 - 44.0)
  // what went left shows out to the screen's edge, not cut at the words' margin
  let (shown, _, _, _) = t.shown_of("two a long").unwrap()
  assert_eq(shown, 0.0)
}

///|
test "an image the app cannot draw reads as its file's name, decoded" {
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      @sf.markdown(c, "见 ![](web%2Dfolded%2D2%2Epng)") |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  assert_true(t.find("web-folded-2.png") is Some(_))
}
