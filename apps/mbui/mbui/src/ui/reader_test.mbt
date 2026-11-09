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
  // every page shows something, and the pages hold all the text once
  let all = StringBuilder()
  for k in 0..<n {
    let t = pages.text_of(k)
    all.write_string(t)
  }
  let plain = StringBuilder()
  for b in blocks {
    match b {
      Para(s) | Heading(s) => plain.write_string(s)
      _ => ()
    }
  }
  assert_eq(all.to_string().replace_all(old="\n", new=""), plain.to_string())
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
