// A desktop's page whose frame says the mouse drags no list (Ctx::mouse_drags_lists false) over a page's list of the
// window's tree: the mouse's drag scrolls nothing and sets off no glide, as over an old view's list; said true (a
// phone's page in a window), it is dragged and flung as a finger drags it; a finger on the same page drags it.

///|
/// How long after a drag let go, or a wheel turned, what it did is looked at: past where a fling of that drag ends.
let md_after_ms : Double = 500.0

///|
/// A Tester on a desktop (a mouse) whose frame says `drags()` of the mouse and lists at each frame, over a page's list
/// of the tree 400 by 200 of 40 rows 40 tall; and what the list is scrolled to.
fn md_case(drags : () -> Bool) -> (Tester, () -> Double) {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  // (the frame around the tree saying it, as a desktop's frames say it, then the old frame's own)
  set_view_app(
    around=fn(c) {
      c.mouse_drags_lists(drags())
      old_frame(c)
    },
    fn(root) {
      root.box(fn(v) {
        v
        .width(Is(Some(400.0)))
        .height(Is(Some(200.0)))
        .scrolls_window(scroll, fn() { Array::makei(40, fn(i) { i }) }, est=40.0, fn(b, k) {
          b.height(Is(Some(40.0))).words(Is("row \{k}")) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
  )
  t.draw()
  (t, fn() { scroll.at(view_tree().unwrap()) })
}

///|
test "a desktop's page saying the mouse drags no list: the mouse dragged up over a list of the tree scrolls it not and flings it not; the wheel scrolls it; said it drags them, dragged and flung on; a finger there drags it" {
  // (the mouse drags no list: it stands, then and after)
  let (t, at) = md_case(fn() { false })
  t.drag(200.0, 180.0, 200.0, 40.0, steps=4)
  let dragged = at()
  t.run_for(md_after_ms)
  assert_eq((dragged, at()), (0.0, 0.0))
  // (the wheel scrolls it as ever)
  t.wheel(200.0, 100.0, 120.0)
  t.run_for(md_after_ms)
  assert_true(at() > 0.0, msg="the wheel scrolled nothing")
  // (said it drags them: dragged, and on after it is let go)
  let (t2, at2) = md_case(fn() { true })
  t2.drag(200.0, 180.0, 200.0, 40.0, steps=4)
  let held = at2()
  t2.run_for(md_after_ms)
  assert_true(held > 0.0 && at2() > held, msg="dragged to \{held}, on to \{at2()}")
  // (a desktop's page saying a finger drags lists, the mouse none (as its frames say it: pane_finger), a finger there:
  // the finger drags it)
  let (t3, at3) = md_case(fn() { pointing() is Finger })
  t3.host_says_finger(Some(true))
  // (its frame saying so as the hand is a finger)
  t3.draw()
  t3.drag(200.0, 180.0, 200.0, 40.0, steps=4)
  assert_true(at3() > 0.0, msg="a finger dragged nothing")
}
