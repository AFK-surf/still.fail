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
