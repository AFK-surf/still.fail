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
  t.draw()
  t.run_for(@ui.nav_push_ms / 2.0)
  let x2 = t.rect_of("title 2").unwrap().0
  let x1 = t.rect_of("title 1").unwrap().0
  assert_true(x2 > 0.0 && x2 < 390.0)
  assert_eq((x2 - x1).round(), 390.0)
  // the standard curve is past halfway at half the time
  assert_true(x2 < 195.0)
  t.run_for(nav.rest() - t.time())
  assert_eq(t.rect_of("title 2").unwrap().0, 0.0)
  t.assert_idle()
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
  // on_leave told in the frame its slide ends: nothing more drawn for it
  t.run_for(@ui.nav_push_ms)
  assert_eq(left, [1])
  assert_eq(t.visible(), before)
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
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
  assert_eq(t.rect_of("title 0").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "a short slow swipe comes back; a short fling goes back" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.hold_drag(5.0, 400.0, 65.0, 400.0)
  t.release(65.0, 400.0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 2)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.hold_drag(5.0, 400.0, 85.0, 400.0, steps=2)
  t.release(85.0, 400.0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
  t.assert_idle()
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
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 2)
  t.back_gesture(150.0, true)
  // let go a little way along, it goes on from there
  let x = t.rect_of("title 1").unwrap().0
  assert_true(x >= 150.0 && x < 390.0)
  t.run_for(nav.rest() - t.time())
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

///|
test "a stack's slide starts at its first frame, whoever asks its end before or between" {
  let quiet_nav = @ui.Nav::new(0)
  let quiet = @ui.Tester::new(nav_view(quiet_nav))
  quiet_nav.push(1)
  quiet.draw()
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  nav.push(1)
  // asked before its first frame: it has not started, no end to say
  assert_true(nav.rest() > 1.0e300)
  t.draw()
  let e = nav.rest()
  assert_eq(e, quiet_nav.rest())
  assert_eq(e, t.time() + @ui.nav_push_ms)
  // asked again half-way, the same
  t.run_for(@ui.nav_push_ms / 2.0)
  assert_eq(nav.rest(), e)
  t.run_for(e - t.time())
  t.assert_idle()
}

///|
test "nav_rest: a test runs to the end of the stacks' slides, holding none of them" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.draw()
  assert_eq(@ui.nav_rest(), -1.0)
  // the slide sets out in the tap's frame, drawn at its moment: its end the push's length on
  let tapped = t.time()
  t.tap_text("open 1")
  assert_eq(@ui.nav_rest(), tapped + @ui.nav_push_ms)
  t.run_for(@ui.nav_rest() - t.time())
  t.assert_idle()
  assert_eq(@ui.nav_rest(), -1.0)
}

///|
test "a stack made before a Tester (as an app makes its own at start) slides to its end beside what else moves, in any Tester after another" {
  for run in 0..<2 {
    // made before the Tester's context, as still.fail's app.nav is
    let nav = @ui.Nav::new(0)
    let opened = Ref(false)
    let t = @ui.Tester::new(fn(c) {
      nav_view(nav)(c)
      // something else that moves, told in the same frame as the push
      let _ = c.spring("other", if opened.val { 1.0 } else { 0.0 })
    })
    nav.push(1)
    opened.val = true
    t.draw()
    t.run_for(nav.rest() - t.time())
    assert_eq(t.rect_of("title 1").unwrap().0, 0.0, msg="run \{run}")
    t.run_for(t.rest_of("\"other\"") - t.time())
    t.assert_idle()
  }
}

///|
test "a push is over at the end it declares, to the bit: the page under it no longer built there" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  // set out at the display's 27th frame, 450.00000000000006: (t0 + 300 − t0) / 300 falls short of 1 by a rounding
  // there
  t.frame_at(@ui.first_frame_ms * 27.0)
  t.tap_text("open 1")
  t.run_for(nav.rest() - t.time())
  assert_true(t.rest_of("a stack's slide") < 0.0)
  assert_true(t.find("title 0") is None)
  t.assert_idle()
}

///|
test "a push whose end is a hair past one of the display's frames is run to its end, not to that frame" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  // set out at 450.0000000000001, its end 750.0000000000001: a hair past the display's 45th frame, 750
  let at = @ui.first_frame_ms * 27.0
  t.advance(at - t.time())
  t.tap_text("open 1")
  t.run_for(nav.rest() - t.time())
  assert_true(t.rest_of("a stack's slide") < 0.0)
  assert_true(t.find("title 0") is None)
  t.assert_idle()
}

///|
/// The stack's view, its pushes waiting for what the page shows (`ready`) at most `most` ms.
fn nav_wait_view(nav : @ui.Nav[Int], ready : Ref[Bool], most : Double) -> (@ui.Ctx) -> Unit {
  let page = nav_view(nav)
  fn(c) {
    nav.comes_when(fn() { ready.val }, most)
    page(c)
  }
}

///|
/// How long a push waits for its page in these tests.
let test_page_wait_ms : Double = 100.0

///|
test "a page pushed waits for what it shows: the slide starts as it comes, from then" {
  let nav = @ui.Nav::new(0)
  let ready = Ref::new(false)
  let t = @ui.Tester::new(nav_wait_view(nav, ready, test_page_wait_ms))
  t.tap_text("open 1")
  let pushed = t.time()
  // not come yet: nothing moves, the page under it as it was
  t.run_for(test_page_wait_ms / 2.0)
  assert_true(t.rect_of("title 1") is None || t.rect_of("title 1").unwrap().0 > 1.0)
  assert_eq(t.rect_of("title 0").unwrap().0, 0.0)
  // it comes: the slide from that moment, over in its 300 ms
  ready.val = true
  t.draw()
  let came = t.time()
  assert_true(came < pushed + test_page_wait_ms)
  assert_eq(@ui.nav_rest(), came + @ui.nav_push_ms)
  t.run_for(@ui.nav_push_ms)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "a page pushed whose data never comes slides in once it has waited the most" {
  let nav = @ui.Nav::new(0)
  let ready = Ref::new(false)
  let t = @ui.Tester::new(nav_wait_view(nav, ready, test_page_wait_ms))
  t.tap_text("open 1")
  let pushed = t.time()
  // (held from the frame after the one it was pushed in: at rest by the latest its slide could end)
  t.draw()
  assert_eq(@ui.nav_rest(), pushed + test_page_wait_ms + @ui.nav_push_ms)
  t.run_for(test_page_wait_ms + @ui.nav_push_ms)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.assert_idle()
}
