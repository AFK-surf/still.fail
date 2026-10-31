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
  from_end? : Bool = false,
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
      from_end~,
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
  // the first frame lays them out, built once: the view read nothing of the list (what reads its rows in view is built
  // again from them in that frame: readback_test)
  assert_eq(frames[0], 1)
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
test "list: laid from its end and short of its view, no frame the wheel scrolls it in moves its rows, either way" {
  let t = @ui.Tester::new(
    boxes(fn() { 5 }, fn(_) { 30.0 }, stick_end=true, from_end=true),
    w=300.0,
    h=400.0,
  )
  // its last row's foot on the view's, the room left over its rows
  assert_eq(bottom_of(t, 4), 400.0)
  // every frame drawn, as a host draws it (each laid out once)
  let firsts : Array[Double] = []
  t.each_frame(Some(fn() { firsts.push(y_of(t, 0)) }))
  t.move(100.0, 300.0)
  for dy in [-40.0, -3.0, 25.0, -100.0, 60.0] {
    t.wheel(100.0, 300.0, dy)
    t.frame()
  }
  t.each_frame(None)
  assert_true(firsts.length() > 0 && firsts.iter().all(fn(y) { y == 250.0 }), msg="\{firsts}")
}

///|
/// How long a finger takes between two of its slow moves: longer than a display's frame, one drawn with no move.
let slow_move_ms : Double = 20.0

///|
test "list: sticking to its end, a finger moving it off by less than a point a move, frames between its moves, moves it as far as the finger went" {
  let t = @ui.Tester::new(
    boxes(fn() { 1000 }, varied, stick_end=true),
    w=300.0,
    h=400.0,
    platform=2,
  )
  assert_eq(bottom_of(t, 999), 400.0)
  // past the slop, then on by a third of a point a move, slowly: frames drawn between the moves
  t.press_at(100.0, 200.0)
  t.move(100.0, 230.0)
  t.run_for(slow_move_ms)
  let from = bottom_of(t, 999)
  for i in 1..=30 {
    t.move(100.0, 230.0 + 0.3 * i.to_double())
    t.run_for(slow_move_ms)
  }
  assert_true((bottom_of(t, 999) - from - 9.0).abs() < 0.01, msg="moved \{bottom_of(t, 999) - from}")
  assert_true(!t.at_end())
  // let go there: where the finger left it, not put back at the end
  t.release(100.0, 239.0)
  t.run_for(slow_move_ms)
  assert_true(bottom_of(t, 999) > 400.0)
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
test "list: scrolling up into a row cut once it is measured moves by exactly the step, never back to its end" {
  // an agent's history read upward from its end (still.fail's): every sixth row holds a card's words, cut to 100 once
  // it knows how tall they are (a fold): laid out whole the first time it is built, cut as the frame is built again
  // from what its layout read
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        60,
        40.0,
        fn(i) {
          if i % 6 == 0 {
            let words = c.id("words")
            let body = fn() {
              c.box(h=Px(600.0), id=words, fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
            }
            if c.laid_size(words) is Some(_) {
              c.box(h=Px(100.0), clip=true, body) |> ignore
            } else {
              c.box(clip=true, body) |> ignore
            }
          } else {
            c.box(h=Px(30.0), fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
          }
        },
        stick_end=true,
      )
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  for _ in 0..<40 {
    let first = t.visible().0
    let before = y_of(t, first)
    t.wheel(100.0, 100.0, -50.0)
    match t.row(first) {
      Some((_, y, _, _)) => assert_eq(y, before + 50.0)
      None => fail("row \{first} out of view after a step of 50 toward the start")
    }
    t.check_rows(0.0, 400.0)
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
test "list: a finger's list scrolled draws no scroll bar, and is at rest once its scroll is (scroll_bar.mbt)" {
  let t = @ui.Tester::new(boxes(fn() { 200 }, varied), w=300.0, h=400.0, platform=2)
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 300.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_true(t.drawn_rects().iter().all(fn(r) { r.2 != 3.0 }), msg="\{t.drawn_rects()}")
  let rest = t.ctx().list_rest("list")
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
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

///|
test "a row followed from its top: a glide to the end stops with its top under the view's, not past it" {
  let n = Ref::new(10)
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "rows",
        n.val,
        40.0,
        fn(i) {
          // the last row taller than the view
          c.column(h=Px(if i == 10 { 600.0 } else { 40.0 }), fn() { c.text("row \{i}", wrap=false) |> ignore })
          |> ignore
        },
        stick_end=true,
        glide_on_growth=true,
      )
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  // (half a second on, as the app lets its list glide)
  t.run_for(@ui.list_glide_ms * 5.0)
  // (followed from its top as it comes: told before the frame it is laid out in)
  t.ctx().list_follow_from("rows", 10, margin=test_follow_margin)
  n.val = 11
  t.draw()
  t.run_for(@ui.list_glide_ms * 10.0)
  let (_, y, _, _) = t.rect_of("row 10").unwrap()
  assert_true((y - test_follow_margin).abs() < 1.0)
  assert_false(t.at_end())
}

///|
test "a row followed from its top, the end come first: the glide ends at the end as it now is, the row under it still growing followed" {
  let n = Ref::new(10)
  let tall = Ref::new(30.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "rows",
        n.val,
        40.0,
        fn(i) {
          c.column(h=Px(if i == 10 { tall.val } else { 40.0 }), fn() { c.text("row \{i}", wrap=false) |> ignore })
          |> ignore
        },
        stick_end=true,
        glide_on_growth=true,
      )
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  t.run_for(@ui.list_glide_ms * 5.0)
  // the row over the new one followed from its top (a message just sent), far under the view's: the end comes first
  t.ctx().list_follow_from("rows", 9, margin=test_follow_margin)
  // a row comes at the end (an agent's line), its room opening a little each frame (less than a point: the tail of
  // its spring), on past the glide's rest
  n.val = 11
  t.draw()
  let step = 1000.0 / 120.0
  let end = t.time() + @ui.list_glide_ms * 12.0
  while t.time() < end {
    tall.val = if tall.val + 0.4 > 110.0 { 110.0 } else { tall.val + 0.4 }
    t.frame(ms=step)
  }
  t.run_for(@ui.list_glide_ms * 5.0)
  let (_, y, _, h) = t.row(10).unwrap()
  assert_true(t.at_end())
  assert_true((y + h - 300.0).abs() < 0.5, msg="the last row's foot at \{y + h}, the view's at 300")
}

///|
test "list: a glide to its end whose end moves on the way goes on from where it is, never standing still or jumping" {
  let n = Ref::new(10)
  let tall = Ref::new(80.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.list(
        "list",
        n.val,
        40.0,
        fn(i) {
          c.box(h=Px(if i == 10 { tall.val } else { 40.0 }), fn() { c.text("Row \{i}", wrap=false) |> ignore })
          |> ignore
        },
        stick_end=true,
        glide_on_growth=true,
      )
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.run_for(@ui.list_glide_ms * 5.0)
  // a row comes at its end: it glides after it; on its way, the row grows (its words laid out, a card under them)
  n.val = 11
  t.draw()
  let moves : Array[Double] = []
  let mut was = t.list_offset()
  // (a frame a sixth of its time constant, about a phone's; the row grows half a time constant in)
  let step = @ui.list_glide_ms / 6.0
  let start = t.time()
  let mut grown = false
  while t.time() < start + @ui.list_glide_ms * 30.0 {
    if !grown && t.time() >= start + @ui.list_glide_ms * 0.5 {
      tall.val = 260.0
      grown = true
    }
    t.frame(ms=step)
    let now = t.list_offset()
    moves.push(now - was)
    was = now
    if t.at_end() && grown {
      break
    }
  }
  assert_true(t.at_end())
  // on every frame of its way it moved, and smoothly: no frame put it a long way that the next did not go on from
  // (a remainder put at once, the frames round it standing still), each at least half of the one before
  let last = moves.length() - 1
  for i, m in moves {
    if i < last {
      assert_true(m > 0.0)
    }
    if i > 0 && i < last {
      assert_true(m >= moves[i - 1] * 0.5)
    }
  }
  // its last step a pixel at most (where it is put at its end)
  assert_true(moves[last] < 2.0)
}

///|
/// How far under the view's top a followed row stops in this test.
let test_follow_margin : Double = 12.0

///|
/// Rows 300 high, each with its words at its top and a mark 18 square held 8 under the list's top (Ctx::stick) as the
/// row scrolls past.
fn stuck_rows() -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.list("list", 20, 300.0, fn(i) {
      c.box(h=Px(300.0), fn() {
        c.text("Row \{i}", wrap=false) |> ignore
        c.layer(fn() {
          let mark = c.box(w=Px(18.0), h=Px(18.0), fn() { c.text("Mark \{i}", wrap=false) |> ignore })
          c.stick(mark, 8.0)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "list: what a row holds stuck stays under the list's top as the row scrolls past, and leaves with its foot" {
  // (each mark drawn over its row's words as it scrolls past, on purpose: words_over.mbt asks nothing of it)
  let t = @ui.Tester::new(stuck_rows(), w=300.0, h=400.0, words_over_held=false)
  // its row at the list's top: held 8 under it already (as CSS's sticky is), its words at the top
  let (_, y0, _, _) = t.rect_of("Mark 0").unwrap()
  assert_eq(y0, 8.0)
  assert_eq(t.rect_of("Row 0").unwrap().1, 0.0)
  // the row 100 up: the mark 8 under the list's top, its words gone up with the row
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 100.0)
  let (_, y1, _, _) = t.rect_of("Mark 0").unwrap()
  assert_eq(y1, 8.0)
  assert_eq(t.rect_of("Row 0").unwrap().1, -100.0)
  // the row's foot coming up past it: it goes with the foot, 18 over it
  t.wheel(100.0, 100.0, 190.0)
  let (_, y2, _, _) = t.rect_of("Mark 0").unwrap()
  assert_eq(y2, 300.0 - 290.0 - 18.0)
  // the next row's own, where it is laid out
  let (_, y3, _, _) = t.rect_of("Mark 1").unwrap()
  assert_eq(y3, 10.0)
}
