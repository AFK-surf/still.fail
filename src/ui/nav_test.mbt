///|
/// Page i: its title, a button to the next, and a long list.
fn nav_view(nav : @ui.Nav[Int]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.nav(
      nav,
      fn(i) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.text("title \{i}", wrap=false) |> ignore
          if c.button("open \{i + 1}") {
            nav.push(i + 1)
          }
          c.list("rows", 200, 30.0, fn(r) {
            c.text("row \{r} of \{i}", wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      bg=0xFFFFFFFFL,
    )
    |> ignore
  }
}

///|
test "a page pushed slides in from the right, the one under it out to the left" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  assert_false(t.takes_back())
  t.tap_text("open 1")
  // the state at once; the picture once it has slid in
  assert_eq(nav.depth(), 2)
  t.run_for(@ui.nav_push_ms)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  assert_true(t.rect_of("title 0") is None)
  assert_true(t.takes_back())
  // halfway through a push: side by side, edge to edge
  nav.push(2)
  t.frame()
  t.frame(ms=150.0)
  let x2 = t.rect_of("title 2").unwrap().0
  let x1 = t.rect_of("title 1").unwrap().0
  assert_true(x2 > 0.0 && x2 < 390.0)
  assert_eq((x2 - x1).round(), 390.0)
  // the standard curve is past halfway at half the time
  assert_true(x2 < 195.0)
  t.settle() |> ignore
  assert_eq(t.rect_of("title 2").unwrap().0, 0.0)
}

///|
test "back pops; the page under keeps where its list was scrolled" {
  let left = []
  let nav = @ui.Nav::new(0, on_leave=fn(p) { left.push(p) })
  let t = @ui.Tester::new(nav_view(nav))
  t.wheel(100.0, 400.0, 900.0)
  let before = t.visible()
  assert_true(before.0 > 10)
  t.tap_text("open 1")
  t.run_for(@ui.nav_push_ms)
  // page 1's own list starts at its top
  assert_eq(t.visible().0, 0)
  t.wheel(100.0, 400.0, 600.0)
  t.back()
  assert_eq(nav.depth(), 1)
  // (on_leave is told the frame after the page has slid off: logic on a motion's end, to be told at once instead,
  // the page sliding off then drawn from what it was)
  t.run_for(@ui.nav_push_ms)
  t.frame()
  assert_eq(t.visible(), before)
  assert_eq(left, [1])
  assert_false(t.takes_back())
  // page 1 again is a new page: its list at the top, not where it was left
  t.tap_text("open 1")
  t.run_for(@ui.nav_push_ms)
  assert_eq(t.visible().0, 0)
}

///|
test "swiped from the left edge the page follows the finger, then goes back" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.run_for(@ui.nav_push_ms)
  t.hold_drag(5.0, 400.0, 200.0, 400.0)
  // the page where the finger has it, the one under it beside it
  assert_eq(t.rect_of("title 1").unwrap().0, 195.0)
  assert_eq(t.rect_of("title 0").unwrap().0, -195.0)
  t.release(200.0, 400.0)
  t.settle() |> ignore
  assert_eq(nav.depth(), 1)
  assert_eq(t.rect_of("title 0").unwrap().0, 0.0)
}

///|
test "a short slow swipe comes back; a short fling goes back" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.hold_drag(5.0, 400.0, 65.0, 400.0)
  t.release(65.0, 400.0)
  t.settle() |> ignore
  assert_eq(nav.depth(), 2)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.hold_drag(5.0, 400.0, 85.0, 400.0, steps=2)
  t.release(85.0, 400.0)
  t.settle() |> ignore
  assert_eq(nav.depth(), 1)
}

///|
test "a press on the edge that moves up and down scrolls the list, and a tap there taps" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.drag(10.0, 600.0, 12.0, 300.0)
  t.draw()
  assert_eq(nav.depth(), 2)
  assert_true(t.visible().0 > 0)
}

///|
test "the system's back gesture (predictive back) follows, then goes or not" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.back_gesture(100.0, false)
  t.settle() |> ignore
  assert_eq(nav.depth(), 2)
  t.back_gesture(150.0, true)
  // let go a little way along, it goes on from there
  let x = t.rect_of("title 1").unwrap().0
  assert_true(x >= 150.0 && x < 390.0)
  t.settle() |> ignore
  assert_eq(nav.depth(), 1)
  // nothing to go back to: the app does not take back
  t.back()
  assert_eq(nav.depth(), 1)
}

///|
test "nav_flat: the top page alone, in place; a page left is forgotten and told" {
  let left : Array[String] = []
  let nav = @ui.Nav::new("home", on_leave=fn(p) { left.push(p) })
  let shown : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    c.nav_flat(nav, fn(p) {
      shown.push(p)
      c.text(p, wrap=false) |> ignore
    })
    |> ignore
  })
  nav.push("chat")
  t.frame()
  assert_true(t.find("chat") is Some(_))
  assert_true(t.find("home") is None)
  nav.pop() |> ignore
  t.frame()
  t.frame()
  assert_eq(left, ["chat"])
  assert_true(t.find("home") is Some(_))
}
