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
  )
  // the heading first, its top margin dropped
  let (_, hy, _, _) = t.rect_of("今天的进度").unwrap()
  assert_eq(hy, 16.0)
  // the paragraph 14 below the heading's bottom (the larger margin: the
  // paragraph's own, its size 15)
  let (_, hy2, _, hh) = t.rect_of("今天的进度").unwrap()
  let (_, py, _, _) = t.rect_of("改好了").unwrap()
  assert_eq(py - (hy2 + hh), 15.0)
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
          cell_files=fn(name) {
            // a wide one and a tall one
            let r = if name == "web-folded.png" { 2.0 } else { 0.5 }
            Some((r, fn(w) { drawn.push((name, w)) }))
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
