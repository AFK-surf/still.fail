///|
/// How long a page takes across a Tester's window (390 wide): a Move as long as that (350 ms).
let page_ms : Double = @ui.move_ms(390.0)

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
  t.run_for(page_ms)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  assert_true(t.rect_of("title 0") is None)
  assert_true(t.takes_back())
  // halfway through a push: side by side, edge to edge
  nav.push(2)
  t.draw()
  t.run_for(page_ms / 2.0)
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
test "a page from the left comes in from there, the one under it out to the right; back and swiped back, that way" {
  // page 1 is to the left of page 0 (still.fail's settings, its gear at the list's top left: App.kt transition)
  let nav = @ui.Nav::new(0, from_left=fn(i) { i == 1 })
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.run_for(page_ms / 2.0)
  // halfway: coming from the left, page 0 going out to the right beside it
  let x1 = t.rect_of("title 1").unwrap().0
  let x0 = t.rect_of("title 0").unwrap().0
  assert_true(x1 < 0.0 && x1 > -390.0)
  assert_eq((x0 - x1).round(), 390.0)
  t.run_for(page_ms / 2.0)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  // a page pushed over it comes from the right as any does, page 1 going out to the left
  t.tap_text("open 2")
  t.run_for(page_ms / 2.0)
  assert_true(t.rect_of("title 2").unwrap().0 > 0.0)
  assert_true(t.rect_of("title 1").unwrap().0 < 0.0)
  t.run_for(page_ms / 2.0)
  t.back()
  t.run_for(page_ms)
  // back from page 1: it goes back out to the left, page 0 coming from the right
  t.back()
  t.run_for(page_ms / 2.0)
  let x1 = t.rect_of("title 1").unwrap().0
  let x0 = t.rect_of("title 0").unwrap().0
  assert_true(x1 < 0.0 && x0 > 0.0)
  assert_eq((x0 - x1).round(), 390.0)
  t.run_for(page_ms / 2.0)
  assert_eq(nav.depth(), 1)
  // swiped back: as far as the finger has gone, to the left, page 0 beside it on the right
  t.tap_text("open 1")
  t.run_for(page_ms)
  t.hold_drag(5.0, 400.0, 200.0, 400.0)
  assert_eq(t.rect_of("title 1").unwrap().0, -195.0)
  assert_eq(t.rect_of("title 0").unwrap().0, 195.0)
  t.release(200.0, 400.0)
  t.run_for(page_ms)
  assert_eq(nav.depth(), 1)
  assert_eq(t.rect_of("title 0").unwrap().0, 0.0)
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
  t.run_for(page_ms)
  // page 1's own list starts at its top
  assert_eq(t.visible().0, 0)
  t.wheel(100.0, 400.0, 600.0)
  t.back()
  assert_eq(nav.depth(), 1)
  // on_leave told in the frame its slide ends: nothing more drawn for it
  t.run_for(page_ms)
  assert_eq(left, [1])
  assert_eq(t.visible(), before)
  assert_false(t.takes_back())
  // page 1 again is a new page: its list at the top, not where it was left
  t.tap_text("open 1")
  t.run_for(page_ms)
  assert_eq(t.visible().0, 0)
}

///|
test "swiped from the left edge the page follows the finger, then goes back" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.run_for(page_ms)
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
  // (on page 1, slid in: the page it covers takes no press while it comes)
  t.run_for(nav.rest() - t.time())
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
test "a page asks the stack where it stands: the root under a page sliding in over it is still the root, one leaving keeps its own" {
  let nav = @ui.Nav::new(0)
  // each page's under as it was last built
  let told : Map[Int, Int?] = {}
  let t = @ui.Tester::new(fn(c) {
    c.nav(nav, fn(i) {
      told[i] = nav.under()
      c.text("title \{i}", wrap=false) |> ignore
    })
    |> ignore
  })
  nav.push(1)
  t.draw()
  t.run_for(page_ms / 2.0)
  // both built as page 1 slides in: the root with none under it, though the stack is two deep
  assert_eq(told.get(0), Some(None))
  assert_eq(told.get(1), Some(Some(0)))
  // outside them, the top's
  assert_eq(nav.under(), Some(0))
  t.run_for(nav.rest() - t.time())
  nav.push(2)
  t.draw()
  t.run_for(nav.rest() - t.time())
  // back: page 2 leaving still has page 1 under it, page 1 coming back the root
  told.clear()
  nav.pop() |> ignore
  t.draw()
  t.run_for(page_ms / 2.0)
  assert_eq(told.get(2), Some(Some(1)))
  assert_eq(told.get(1), Some(Some(0)))
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.under(), Some(0))
  t.assert_idle()
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
  assert_eq(e, t.time() + page_ms)
  // asked again half-way, the same
  t.run_for(page_ms / 2.0)
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
  assert_eq(@ui.nav_rest(), tapped + page_ms)
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
/// How late a slide's first frame is to the screen in these tests: a frame two and a half of the display's long.
let test_first_late_ms : Double = 40.0

///|
/// A first frame far later than a slide waits for (nav_late_most).
let test_first_very_late_ms : Double = 500.0

///|
test "a page pushed whose first frame is late to the screen moves from where that frame drew it, at the display's pace" {
  // the same push, its first frame on time
  let on_time_nav = @ui.Nav::new(0)
  let on_time = @ui.Tester::new(nav_view(on_time_nav))
  on_time.tap_text("open 1")
  let tapped = on_time.time()
  on_time.run_for(page_ms / 2.0)
  let half = on_time.rect_of("title 1").unwrap().0
  // its first frame (the tap's, the page built in it) 40 ms late to the screen, as the host says in the next
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  assert_eq(t.time(), tapped)
  t.frame_late(test_first_late_ms)
  t.run_for(@ui.first_frame_ms)
  // it has not moved yet: where its first frame drew it, at its start
  assert_true(t.rect_of("title 1") is None || t.rect_of("title 1").unwrap().0 >= 390.0)
  assert_eq(nav.rest(), tapped + test_first_late_ms + page_ms)
  // from then, as the one on time from its frame
  t.run_for(tapped + test_first_late_ms + page_ms / 2.0 - t.time())
  // (to the last bits a start moved on rounds otherwise)
  assert_true((t.rect_of("title 1").unwrap().0 - half).abs() < 1.0e-6)
  t.run_for(nav.rest() - t.time())
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "a page pushed whose first frame is very late to the screen waits nav_late_most at most" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  let tapped = t.time()
  t.frame_late(test_first_very_late_ms)
  t.run_for(@ui.first_frame_ms)
  assert_eq(nav.rest(), tapped + @ui.nav_late_most + page_ms)
  t.run_for(nav.rest() - t.time())
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "a page gone back to whose first frame is late to the screen moves from where that frame drew it" {
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(nav_view(nav))
  t.tap_text("open 1")
  t.run_for(nav.rest() - t.time())
  t.back()
  let back = t.time()
  t.frame_late(test_first_late_ms)
  t.run_for(@ui.first_frame_ms)
  assert_eq(nav.rest(), back + test_first_late_ms + page_ms)
  t.run_for(nav.rest() - t.time())
  assert_eq(t.rect_of("title 0").unwrap().0, 0.0)
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
  assert_eq(@ui.nav_rest(), came + page_ms)
  t.run_for(page_ms)
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
  assert_eq(@ui.nav_rest(), pushed + test_page_wait_ms + page_ms)
  t.run_for(test_page_wait_ms + page_ms)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "a page covered by one sliding in takes no press: one where its button still shows goes to the page coming or to nothing; going back, the page leaving takes none" {
  let nav = @ui.Nav::new(0)
  let pressed : Array[Int] = []
  let t = @ui.Tester::new(fn(c) {
    c.nav(
      nav,
      fn(i) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.text("title \{i}", wrap=false) |> ignore
          if c.button("press \{i}") {
            pressed.push(i)
          }
        })
        |> ignore
      },
      bg=0xFFFFFFFFL,
    )
    |> ignore
  })
  // pushed: a little way in, page 0's button still showing to the left of page 1's
  nav.push(1)
  t.draw()
  t.run_for(page_ms / 10.0)
  let (x, y, w, h) = t.rect_of("press 0").unwrap()
  assert_true(x + w > 0.0)
  t.tap((if x > 0.0 { x } else { 0.0 }) + 2.0, y + h / 2.0)
  assert_eq(pressed, [])
  // (and from the moment it is pushed: its first frame, before anything has moved)
  nav.pop() |> ignore
  t.draw()
  t.run_for(nav.rest() - t.time())
  nav.push(1)
  t.draw()
  let (x, y, w, h) = t.rect_of("press 0").unwrap()
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(pressed, [])
  t.run_for(nav.rest() - t.time())
  // at rest, the page on top takes its presses
  let (x, y, w, h) = t.rect_of("press 1").unwrap()
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(pressed, [1])
  // going back: halfway, page 1 leaving takes nothing where its button still shows
  nav.pop() |> ignore
  t.draw()
  t.run_for(page_ms / 2.0)
  let (x, y, _, h) = t.rect_of("press 1").unwrap()
  t.tap(x + 2.0, y + h / 2.0)
  // (page 0 coming may be under it: its own press is its)
  assert_eq(pressed.filter(fn(i) { i == 1 }).length(), 1)
  t.run_for(nav.rest() - t.time())
  t.assert_idle()
}

///|
/// A flat stack's view (Ctx::nav_flat), its pages put on top waiting for what they show (`ready`) at most `most` ms.
fn flat_wait_view(nav : @ui.Nav[String], ready : Ref[Bool], most : Double) -> (@ui.Ctx) -> Unit {
  fn(c) {
    nav.shows_when(fn() { ready.val }, most)
    c.nav_flat(nav, fn(p) { c.text(p, wrap=false) |> ignore }) |> ignore
  }
}

///|
test "nav_flat: a page put on top shows once it has what it shows, the page before staying as it was and told it left only then" {
  let left : Array[String] = []
  let nav = @ui.Nav::new("page one", on_leave=fn(p) { left.push(p) })
  let ready = Ref::new(false)
  let t = @ui.Tester::new(flat_wait_view(nav, ready, test_page_wait_ms))
  t.draw()
  nav.replace("page two")
  t.draw()
  assert_true(t.find("page one") is Some(_) && t.find("page two") is None)
  assert_eq(left, [])
  ready.val = true
  t.draw()
  assert_true(t.find("page two") is Some(_) && t.find("page one") is None)
  assert_eq(left, ["page one"])
  t.assert_idle()
}

///|
test "nav_flat: a page put on top whose data never comes shows once it has waited the most" {
  let nav = @ui.Nav::new("page one")
  let ready = Ref::new(false)
  let t = @ui.Tester::new(flat_wait_view(nav, ready, test_page_wait_ms))
  t.draw()
  nav.push("page two")
  t.draw()
  t.run_for(test_page_wait_ms / 2.0)
  assert_true(t.find("page one") is Some(_) && t.find("page two") is None)
  t.run_for(test_page_wait_ms)
  assert_true(t.find("page two") is Some(_))
  t.assert_idle()
}

///|
test "nav_flat: not asked to wait (Nav::shows_when), a page put on top shows at once" {
  let nav = @ui.Nav::new("page one")
  let t = @ui.Tester::new(fn(c) { c.nav_flat(nav, fn(p) { c.text(p, wrap=false) |> ignore }) |> ignore })
  t.draw()
  nav.push("page two")
  t.draw()
  assert_true(t.find("page two") is Some(_))
}

///|
/// A stack drawn flat whose pages pushed over (Nav::push_over) are its own (Ctx::nav_flat `stacks`): each page its
/// title, as wide as the window.
fn stacking_view(nav : @ui.Nav[String]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.nav_flat(nav, fn(p) { c.text(p, wrap=false) |> ignore }, bg=0xFFFFFFFFL, stacks=true) |> ignore
  }
}

///|
test "nav_flat stacking: one pushed over slides in, back takes it off sliding; one put in place shows in place, back not its" {
  let nav = @ui.Nav::new("list")
  let t = @ui.Tester::new(stacking_view(nav))
  // put in place (a list's choice): at once, and back is not the stack's
  nav.push("chosen")
  t.draw()
  assert_eq(t.rect_of("chosen").unwrap().0, 0.0)
  assert_false(t.takes_back())
  // pushed over it: it slides in from the right, the one under it beside it
  nav.push_over("opened")
  t.draw()
  t.run_for(page_ms / 2.0)
  let x = t.rect_of("opened").unwrap().0
  assert_true(x > 0.0 && x < 390.0, msg="halfway in at \{x}")
  assert_true(t.rect_of("chosen") is Some(_))
  t.run_for(nav.rest() - t.time())
  assert_eq(t.rect_of("opened").unwrap().0, 0.0)
  assert_true(t.takes_back())
  // the system's back gesture: it follows, called off it comes back; gone through, on from where it was let go, the
  // one put in place under it, back not the stack's again
  t.back_gesture(100.0, false)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 3)
  t.back_gesture(150.0, true)
  let x = t.rect_of("opened").unwrap().0
  assert_true(x >= 150.0 && x < 390.0, msg="let go at \{x}")
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.pages(), ["list", "chosen"])
  assert_eq(t.rect_of("chosen").unwrap().0, 0.0)
  assert_false(t.takes_back())
  t.assert_idle()
}

///|
test "nav_flat stacking: what is put in place of one pushed over is over too; popped past it, in place again" {
  let nav = @ui.Nav::new("list")
  let t = @ui.Tester::new(stacking_view(nav))
  nav.push("chosen")
  nav.push_over("opened")
  t.run_for(page_ms)
  nav.replace("opened again")
  t.draw()
  assert_true(nav.top_over())
  assert_true(t.takes_back())
  t.back()
  t.run_for(nav.rest() - t.time())
  assert_false(nav.top_over())
  assert_eq(t.rect_of("chosen").unwrap().0, 0.0)
  assert_false(t.takes_back())
}

///|
/// Where page 1's title is half a page's slide after it set out, pushed as `how` says: "laid" (between frames, the
/// stack laid out before: it sets out at the next frame), "before" (before the window's first frame), "first" (as the first frame builds the
/// stack, before it was laid out); `dense`: frames drawn all the way, else that moment alone.
fn half_way_x(how : String, dense : Bool) -> Double {
  let nav = @ui.Nav::new(0)
  let pushed = Ref(false)
  if how == "before" {
    nav.push(1)
  }
  let view = nav_view(nav)
  let t = @ui.Tester::new(fn(c) {
    if how == "first" && !pushed.val {
      pushed.val = true
      nav.push(1)
    }
    view(c)
  })
  if how == "laid" {
    t.draw()
    nav.push(1)
  }
  // (the frame it sets out at)
  t.draw()
  let start = t.time()
  if dense {
    // (a frame each display's frame all the way, as a host draws them)
    let mut at = start
    while at + @ui.frame_period_default < start + page_ms / 2.0 {
      at = at + @ui.frame_period_default
      t.frame_at(at)
    }
    t.frame_at(start + page_ms / 2.0)
  } else {
    t.advance(page_ms / 2.0)
    t.draw()
  }
  t.rect_of("title 1").unwrap().0
}

///|
test "a page pushed before the stack was ever laid out (before the first frame, or as it first builds it): its slide as long as its way across the room once that is known, from when it was pushed; frames between or none, where it is at a moment the same" {
  let tapped = half_way_x("laid", true)
  assert_true(tapped > 0.0, msg="half way: \{tapped}")
  assert_eq(half_way_x("laid", false), tapped, msg="no frame between")
  assert_eq(half_way_x("before", true), tapped, msg="pushed before the first frame")
  assert_eq(half_way_x("before", false), tapped, msg="pushed before the first frame, no frame between")
  assert_eq(half_way_x("first", true), tapped, msg="pushed as the first frame builds it")
  assert_eq(half_way_x("first", false), tapped, msg="pushed as the first frame builds it, no frame between")
}

///|
test "nav_flat, its owner saying what shows (Nav::flat_keep): the stay kept shows in place of the one on top, its entry kept though it left the stack; let go, told it left once; another entry of the same page none of it" {
  let left : Array[String] = []
  let nav = @ui.Nav::new("page one", on_leave=fn(p) { left.push(p) })
  nav.flat_owned(true)
  let t = @ui.Tester::new(fn(c) { c.nav_flat(nav, fn(p) { c.text(p, wrap=false) |> ignore }) |> ignore })
  t.draw()
  let one = nav.top_stay()
  // put in its place, the one before kept: drawn whatever frames come, not told it left
  nav.replace("page two")
  nav.flat_keep(Some(one))
  t.draw()
  t.draw()
  assert_true(t.find("page one") is Some(_) && t.find("page two") is None)
  assert_eq(left, [])
  // let go: the one on top shows, the one kept told it left, once
  nav.flat_keep(None)
  t.draw()
  t.draw()
  assert_true(t.find("page two") is Some(_) && t.find("page one") is None)
  assert_eq(left, ["page one"])
  // the same page put there again is another entry: the stay kept before keeps nothing of it
  nav.replace("page one")
  nav.flat_keep(Some(one))
  t.draw()
  assert_true(t.find("page one") is Some(_) && t.find("page two") is None)
  assert_eq(left, ["page one", "page two"])
  // back to the frames' way (Nav::shows_when, none asked): the one on top at once
  nav.flat_owned(false)
  nav.replace("page three")
  t.draw()
  assert_true(t.find("page three") is Some(_))
}

///|
/// A flat stack's view whose owner says what shows (Nav::flat_owned): page i its title and a long list.
fn flat_kept_view(nav : @ui.Nav[Int]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.nav_flat(nav, fn(i) {
      c.column(w=Fill(1.0), h=Fill(1.0), fn() {
        c.text("title \{i}", wrap=false) |> ignore
        c.list("rows", 200, 30.0, fn(r) { c.text("row \{r} of \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "nav_flat, its owner keeping the page before (Nav::flat_keep): its list where it was scrolled, frame after frame; let go, the page on top from its top, told it left once; the same page again a new list" {
  let left = []
  let nav = @ui.Nav::new(0, on_leave=fn(p) { left.push(p) })
  nav.flat_owned(true)
  let t = @ui.Tester::new(flat_kept_view(nav))
  t.wheel(100.0, 400.0, 900.0)
  let before = t.visible()
  assert_true(before.0 > 10)
  let zero = nav.top_stay()
  nav.replace(1)
  nav.flat_keep(Some(zero))
  t.draw()
  t.draw()
  assert_true(t.find("title 0") is Some(_))
  assert_eq(t.visible(), before)
  assert_eq(left, [])
  nav.flat_keep(None)
  t.draw()
  assert_true(t.find("title 1") is Some(_))
  assert_eq(t.visible().0, 0)
  t.draw()
  assert_eq(left, [0])
  // page 0 again: another entry, its list from its top
  nav.replace(0)
  t.draw()
  assert_eq(t.visible().0, 0)
  assert_eq(left, [0, 1])
}

///|
test "nav_flat, its owner keeping a stay: one on top again since (come back to: another time on top) keeps nothing" {
  let nav = @ui.Nav::new(0)
  nav.flat_owned(true)
  let t = @ui.Tester::new(flat_kept_view(nav))
  t.draw()
  let zero = nav.top_stay()
  // over it and back: page 0 the same entry, another time on top
  nav.push(1)
  t.draw()
  nav.pop() |> ignore
  t.run_for(page_ms)
  assert_eq(nav.top_stay().0, zero.0)
  assert_true(nav.top_stay() != zero)
  // another put on top, the stay before page 0's last time on top asked to be kept: none
  nav.push(2)
  nav.flat_keep(Some(zero))
  t.draw()
  assert_true(t.find("title 2") is Some(_) && t.find("title 0") is None)
}
