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

///|
test "the pager turns on a tap at either side, a drag, and the arrow keys" {
  // paginated in the first frame, once the tester's host is in place
  let cut : Ref[@ui.Pages?] = { val: None }
  let index = [0]
  let rest = Ref(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      let pages = match cut.val {
        Some(p) => p
        None => {
          let p = @ui.paginate(chapter(), 300.0, 500.0)
          cut.val = Some(p)
          p
        }
      }
      index[0] = c.pager("book", pages.count(), index[0], fn(i) {
        c.page(pages, i) |> ignore
      })
      rest.val = c.pager_rest("book")
    },
    w=300.0,
    h=500.0,
  )
  t.tap(280.0, 250.0)
  assert_eq(index[0], 1)
  // the turned-to page slid into place (its slide at rest), its neighbours beside it
  t.run_for(rest.val - t.time())
  inspect(
    t.dump(),
    content=(
      #|col 0,0 300x500
      #|  row 0,0 300x500
      #|    col -300,0 300x500 item=0
      #|      col -300,0 300x500
      #|    col 0,0 300x500 item=1
      #|      col 0,0 300x500
      #|    col 300,0 300x500 item=2
      #|      col 300,0 300x500
      #|
    ),
  )
  t.tap(20.0, 250.0)
  assert_eq(index[0], 0)
  // a tap in the middle does nothing
  t.tap(150.0, 250.0)
  assert_eq(index[0], 0)
  // dragged left past a third: the next page, which slides into place
  t.drag(250.0, 250.0, 120.0, 250.0)
  t.run_for(rest.val - t.time())
  assert_eq(index[0], 1)
  // a short drag springs back
  t.drag(150.0, 250.0, 120.0, 250.0, steps=30)
  t.run_for(rest.val - t.time())
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
  t.run_for(rest.val - t.time())
  t.assert_idle()
}

///|
/// A pager over three blank pages, its index kept in `index`.
fn blank_pager(key : String, index : Array[Int], rest? : Ref[Double] = Ref(0.0)) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      index[0] = c.pager(key, 3, index[0], fn(_) {  })
      rest.val = c.pager_rest(key)
    },
    w=300.0,
    h=500.0,
  )
}

///|
test "a turned page slides by the clock: where it is at 120 ms is the same in one frame or in seven" {
  // a moment mid-slide (the slide is at rest in about 200 ms)
  let mid_slide = 120.0
  let a = [0]
  let one = blank_pager("one", a)
  one.tap(280.0, 250.0)
  one.frame(ms=mid_slide)
  let at_once = one.dump()
  let b = [0]
  let rest = Ref(0.0)
  let seven = blank_pager("seven", b, rest~)
  seven.tap(280.0, 250.0)
  seven.run_for(mid_slide)
  assert_eq(seven.dump(), at_once)
  // on its way still, then at rest, and no frame after
  assert_true(at_once.contains("item=1") && !at_once.contains("col 0,0 300x500 item=1"))
  // to when its slide is at rest (the pager's own, not whatever else moves)
  seven.run_for(rest.val - seven.time())
  seven.assert_idle()
}
