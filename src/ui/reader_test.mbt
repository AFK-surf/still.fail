///|
fn chapter() -> Array[@ui.Block] {
  let out : Array[@ui.Block] = [Heading("第一章 测试")]
  for i in 0..<40 {
    out.push(
      Para(
        "第\{i}段：这一段是排版测试用的文字，中文和 English words 混在一起，用来检查换行、缩进和两端对齐是否正确。",
      ),
    )
    if i == 10 {
      out.push(Picture("map.png", 1200.0, 800.0))
    }
    if i == 20 {
      out.push(Rule)
    }
  }
  out
}

///|
test "a chapter cut into pages: every position on exactly one page, in order" {
  let t = @ui.Tester::new(fn(_) {  }, w=390.0, h=844.0)
  ignore(t)
  let blocks = chapter()
  let pages = @ui.paginate(blocks, 390.0, 700.0)
  let n = pages.count()
  assert_true(n > 3)
  // offsets count text in UTF-16 units, a picture or a rule as 1
  let mut total = 0
  for b in blocks {
    total = total +
      (match b {
        Para(s) | Heading(s) => s.length()
        _ => 1
      })
  }
  assert_eq(pages.length, total)
  assert_eq(pages.pages[0].start, 0)
  assert_eq(pages.pages[n - 1].end, total)
  for k in 0..<(n - 1) {
    assert_eq(pages.pages[k].end, pages.pages[k + 1].start)
    assert_true(pages.pages[k].start < pages.pages[k].end)
  }
  // the page of a position is the one holding it
  for k in 0..<n {
    let p = pages.pages[k]
    assert_eq(pages.page_of(p.start), k)
    assert_eq(pages.page_of(p.end - 1), k)
  }
  assert_true(pages.text_of(0).has_prefix("第一章 测试\n第0段"))
}

///|
test "pages fit: smaller pages make more of them, the same text in the same order" {
  let t = @ui.Tester::new(fn(_) {  }, w=390.0, h=844.0)
  ignore(t)
  let big = @ui.paginate(chapter(), 390.0, 800.0)
  let small = @ui.paginate(chapter(), 390.0, 400.0)
  assert_true(small.count() > big.count())
  let all = fn(p : @ui.Pages) {
    let sb = StringBuilder()
    for k in 0..<p.count() {
      sb.write_string(p.text_of(k))
      sb.write_char('\n')
    }
    sb.to_string()
  }
  assert_eq(all(big), all(small))
}

///|
test "the pager turns on a tap at either side, a drag, and the arrow keys" {
  let pages = @ui.paginate(chapter(), 300.0, 500.0)
  let index = [0]
  let t = @ui.Tester::new(
    fn(c) {
      index[0] = c.pager("book", pages.count(), index[0], fn(i) {
        c.page(pages, i) |> ignore
      })
    },
    w=300.0,
    h=500.0,
  )
  t.tap(280.0, 250.0)
  assert_eq(index[0], 1)
  t.tap(20.0, 250.0)
  assert_eq(index[0], 0)
  // a tap in the middle does nothing
  t.tap(150.0, 250.0)
  assert_eq(index[0], 0)
  // dragged left past a third: the next page, which slides into place
  t.drag(250.0, 250.0, 120.0, 250.0)
  t.settle() |> ignore
  assert_eq(index[0], 1)
  // a short drag springs back
  t.drag(150.0, 250.0, 120.0, 250.0, steps=30)
  t.settle() |> ignore
  assert_eq(index[0], 1)
  // nothing before the first page
  t.tap(20.0, 250.0)
  t.tap(20.0, 250.0)
  assert_eq(index[0], 0)
  t.move(150.0, 250.0)
  t.press("Right")
  t.press("Right")
  assert_eq(index[0], 2)
  t.press("Left")
  assert_eq(index[0], 1)
}
