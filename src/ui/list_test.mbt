// Ported from mygo's ui/list_test.go: the behaviours of a virtualized list
// of rows of different heights that its tests pin down, on this list.

///|
/// The height of row i of lists of rows of varied heights (mygo's varied).
fn varied(i : Int) -> Double {
  (20 + i * 7 % 45).to_double()
}

///|
fn boxes(
  count : () -> Int,
  height : (Int) -> Double,
  stick_end? : Bool = false,
) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.list(
      "list",
      count(),
      40.0,
      fn(i) {
        c.box(h=Px(height(i)), fn() { c.text("Row \{i}", wrap=false) |> ignore })
        |> ignore
      },
      stick_end~,
    )
    |> ignore
  }
}

///|
fn y_of(t : @ui.Tester, item : Int) -> Double {
  let (_, y, _, _) = t.row(item).unwrap()
  y
}

///|
fn bottom_of(t : @ui.Tester, item : Int) -> Double {
  let (_, y, _, h) = t.row(item).unwrap()
  y + h
}

///|
test "list: rows of varied heights move by exactly what the wheel scrolls" {
  let t = @ui.Tester::new(boxes(fn() { 10000 }, varied), w=300.0, h=400.0)
  let (first, last) = t.visible()
  assert_true(first == 0 && last >= 10)
  t.check_rows(0.0, 400.0)
  let y5 = y_of(t, 5)
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 37.5)
  assert_eq(y_of(t, 5), y5 - 37.5)
  t.check_rows(0.0, 400.0)
  // far down, then back up through rows measured on the way
  for _ in 0..<200 {
    t.wheel(100.0, 100.0, 300.0)
  }
  t.check_rows(0.0, 400.0)
  for _ in 0..<401 {
    t.wheel(100.0, 100.0, -150.0)
    t.check_rows(0.0, 400.0)
  }
  assert_eq(t.visible().0, 0)
  assert_eq(y_of(t, 0), 0.0)
}

///|
test "list: rows far smaller than the estimate fill the first frame" {
  let frames = [0]
  let view = boxes(fn() { 1000 }, fn(_) { 3.0 })
  let t = @ui.Tester::new(
    fn(c) {
      frames[0] = frames[0] + 1
      view(c)
    },
    w=300.0,
    h=400.0,
  )
  let (first, last) = t.visible()
  assert_true(first == 0 && last >= 133)
  t.check_rows(0.0, 400.0)
  // the first frame lays them out, and builds the view again in it over the rows in view as they are now told (what
  // it read of them first was from before they were laid out)
  assert_eq(frames[0], 2)
  assert_eq(t.ctx().frame_number(), 1)
}

///|
test "list: rows above that change size don't move the rows in view" {
  let grow = [0.0]
  let t = @ui.Tester::new(
    boxes(fn() { 1000 }, fn(i) { if i < 40 { 30.0 + grow[0] } else { 30.0 } }),
    w=300.0,
    h=400.0,
  )
  t.scroll_to(45)
  t.frame()
  let before = t.row(50).unwrap()
  grow[0] = 25.0
  t.frame()
  assert_eq(t.row(50).unwrap(), before)
  // scrolled back up through them, the list reaches its start exactly
  t.move(100.0, 100.0)
  for _ in 0..<100 {
    t.wheel(100.0, 100.0, -40.0)
    t.check_rows(0.0, 400.0)
  }
  assert_eq(y_of(t, 0), 0.0)
}

///|
test "list: sticking to its end, it follows new rows until scrolled away" {
  let n = [5]
  let t = @ui.Tester::new(
    boxes(fn() { n[0] }, varied, stick_end=true),
    w=300.0,
    h=400.0,
  )
  // few rows fit, from the top
  assert_eq(y_of(t, 0), 0.0)
  assert_true(t.at_end())
  // as rows come, the list follows the end
  for _ in 0..<40 {
    n[0] = n[0] + 1
    t.draw()
    if n[0] > 12 {
      assert_eq(bottom_of(t, n[0] - 1), 400.0)
    }
  }
  // scrolled away from the end, it stays where it is
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, -100.0)
  let r = t.row(n[0] - 10).unwrap()
  n[0] = n[0] + 3
  t.frame()
  assert_eq(t.row(n[0] - 13).unwrap(), r)
  assert_true(!t.at_end())
  // back at the end, it follows again
  t.scroll_to_end()
  t.frame()
  n[0] = n[0] + 1
  t.frame()
  assert_eq(bottom_of(t, n[0] - 1), 400.0)
  assert_true(t.at_end())
  // the wheel to the end
  t.wheel(100.0, 100.0, 1.0e6)
  assert_true(t.at_end())
}

///|
test "list: sticking to its end, the first frame shows the end" {
  let t = @ui.Tester::new(
    boxes(fn() { 1000 }, varied, stick_end=true),
    w=300.0,
    h=400.0,
  )
  assert_eq(bottom_of(t, 999), 400.0)
  assert_true(t.at_end())
  t.check_rows(0.0, 400.0)
}

///|
test "list: rows going away leave no space after the last" {
  let n = [1000]
  let t = @ui.Tester::new(boxes(fn() { n[0] }, fn(_) { 30.0 }), w=300.0, h=400.0)
  t.scroll_to_end()
  t.frame()
  n[0] = 20
  t.frame()
  assert_eq(bottom_of(t, 19), 400.0)
  t.check_rows(0.0, 400.0)
  n[0] = 5
  t.frame()
  assert_eq(y_of(t, 0), 0.0)
  n[0] = 0
  t.frame()
  assert_eq(t.visible(), (-1, -1))
  assert_true(t.at_end())
}

///|
test "list: the row at the top stays there as the width changes" {
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        1000,
        40.0,
        fn(i) {
          let words = StringBuilder()
          for _ in 0..=(i % 7) {
            words.write_string("words that wrap ")
          }
          c.text("Row \{i} \{words}") |> ignore
        },
      )
      |> ignore
    },
    w=400.0,
    h=400.0,
  )
  t.scroll_to(500)
  t.frame()
  for w in [300.0, 220.0, 500.0, 400.0] {
    t.resize(w, 400.0)
    let (_, y, rw, _) = t.row(500).unwrap()
    assert_eq((y, rw), (0.0, w))
    t.check_rows(0.0, 400.0)
  }
}

///|
test "list: End shows the end, though the last rows are taller than estimated" {
  let t = @ui.Tester::new(
    boxes(fn() { 2000 }, fn(i) { if i >= 1000 { 100.0 } else { 20.0 } }),
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  t.press("End")
  assert_true(t.at_end())
  assert_eq(bottom_of(t, 1999), 400.0)
  t.press("Home")
  assert_eq(y_of(t, 0), 0.0)
  t.press("End")
  assert_eq(bottom_of(t, 1999), 400.0)
}

///|
test "list: scrolling up into rows never measured moves by exactly the step" {
  // a chat read upward from its end: every fifth row is ten times as tall
  let t = @ui.Tester::new(
    boxes(fn() { 5000 }, fn(i) { if i % 5 == 0 { 240.0 } else { 24.0 } }, stick_end=true),
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  for step in [-120.0, -200.0, -120.0, -37.0, -200.0, -120.0, -200.0, -5.0, -300.0, -120.0] {
    let first = t.visible().0
    let before = y_of(t, first)
    t.wheel(100.0, 100.0, step)
    assert_eq(y_of(t, first), before - step)
    t.check_rows(0.0, 400.0)
  }
  // Page Up keeps a line of the page before
  for _ in 0..<5 {
    let first = t.visible().0
    let before = y_of(t, first)
    t.press("PageUp")
    assert_eq(y_of(t, first), before + 360.0)
  }
}

///|
test "list: rows come in above what is in view, which stays where it is" {
  let n = [100]
  let first = [0]
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        n[0],
        40.0,
        fn(i) {
          let k = i - first[0]
          c.box(h=Px(varied(k + 1000)), fn() { c.text("Row \{k}", wrap=false) |> ignore })
          |> ignore
        },
      )
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 1000.0)
  let (a, _) = t.visible()
  let shown = t.find("Row \{a + 1}").unwrap().1
  // twenty rows come in before the first
  n[0] = 120
  first[0] = 20
  t.ctx().list_moved("list", 0, 20)
  t.frame()
  assert_eq(t.find("Row \{a + 1}").unwrap().1, shown)
  assert_eq(t.visible().0, a + 20)
}

///|
test "list: rows come in under a spinner at the top: the first row under it stays" {
  let n = [50]
  let first = [1]
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        n[0],
        40.0,
        fn(i) {
          if i == 0 {
            c.box(h=Px(30.0), fn() { c.text("spinner", wrap=false) |> ignore }) |> ignore
          } else {
            let k = i - first[0]
            c.box(h=Px(50.0), fn() { c.text("Row \{k}", wrap=false) |> ignore }) |> ignore
          }
        },
      )
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  assert_eq(t.visible().0, 0)
  let y0 = t.find("Row 0").unwrap().1
  n[0] = 60
  first[0] = 11
  t.ctx().list_moved("list", 1, 10)
  t.frame()
  assert_eq(t.find("Row 0").unwrap().1, y0)
  assert_true(t.find("spinner") is None)
}

///|
test "list: back to its end, gliding, then at its end" {
  let t = @ui.Tester::new(boxes(fn() { 200 }, varied, stick_end=true), w=300.0, h=400.0)
  assert_true(t.at_end())
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, -300.0)
  assert_true(!t.at_end())
  let info = t.ctx().list_info("list").unwrap()
  assert_true(info.below > 250.0)
  t.ctx().list_to_end("list")
  t.draw()
  // on its way, not there at once: its way said as it sets out, at its end by a time of its own
  assert_true(!t.at_end())
  let rest = t.ctx().list_rest("list")
  assert_true(rest > t.time() && rest < @double.infinity)
  let was = t.list_offset()
  t.run_for(@ui.list_glide_ms)
  // on its way: further down, not at its end
  assert_true(t.list_offset() > was)
  assert_true(!t.at_end())
  t.run_for(rest - t.time())
  assert_true(t.at_end())
  assert_true(t.ctx().list_info("list").unwrap().below.abs() < 0.5)
  t.assert_idle()
  // far from it, the way at once
  t.wheel(100.0, 100.0, -3000.0)
  t.ctx().list_to_end("list")
  t.draw()
  assert_true(t.at_end())
}

///|
test "list: the same glide to its end at any frame rate: where it is is a function of the time since it set out" {
  let at = fn(step : Double) -> Double {
    let t = @ui.Tester::new(boxes(fn() { 200 }, varied, stick_end=true), w=300.0, h=400.0)
    t.move(100.0, 100.0)
    t.wheel(100.0, 100.0, -300.0)
    t.run_for(@ui.wheel_ease_ms * 10.0)
    t.ctx().list_to_end("list")
    t.draw()
    let end = t.time() + @ui.list_glide_ms
    while t.time() + step < end {
      t.frame(ms=step)
    }
    t.frame(ms=end - t.time())
    t.list_offset()
  }
  assert_eq(at(8.0), at(16.0))
  assert_eq(at(16.0), at(33.0))
}

///|
test "list: a list not built (a page over it) is at rest, its scroll bar too; shown again it fades on" {
  let shown = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      if shown.val {
        boxes(fn() { 200 }, varied, stick_end=true)(c)
      }
    },
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, -300.0)
  t.run_for(@ui.wheel_ease_ms * 10.0)
  // its scroll bar shows a while: the list moves
  assert_true(t.ctx().list_rest("list") > t.time())
  shown.val = false
  t.draw()
  t.assert_idle()
  shown.val = true
  t.draw()
  assert_true(t.moving().length() > 0)
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  t.assert_idle()
}

///|
test "list: what is built from how it stood is built again once a scroll of one frame moved it" {
  // a way back to the end shown while the list is away from it, read from list_info as a view does
  let away : Array[Bool] = [false]
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        200,
        40.0,
        fn(i) {
          c.box(h=Px(varied(i)), fn() { c.text("Row \{i}", wrap=false) |> ignore })
          |> ignore
        },
        stick_end=true,
      )
      |> ignore
      away[0] = match c.list_info("list") {
        Some(i) => i.below > 120.0
        None => false
      }
    },
    w=300.0,
    h=400.0,
  )
  t.draw()
  assert_true(!away[0])
  // a wheel's scroll, laid out in one frame and nothing moving after it
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, -600.0)
  assert_true(!t.list_moving())
  assert_true(away[0])
}

///|
test "a click seen in a list's row is drawn by the next frame" {
  let on : Ref[Bool] = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if on.val {
        c.text("开着") |> ignore
      }
      c.list("rows", 3, 40.0, fn(i) {
        let id = c.id("row/\{i}")
        if c.clicked(id) {
          on.val = !on.val
        }
        c.box(id~, h=Px(40.0), fn() { c.text("第 \{i} 行") |> ignore }) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.tap_text("第 1 行")
  t.draw()
  assert_true(on.val)
  assert_true(t.find("开着") is Some(_))
}
