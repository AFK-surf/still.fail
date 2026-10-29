// The swipe back from the screen's left edge on Android: the system's back gesture's (on_back), and no edge swipe of
// mbui's beside it (Ctx::on_edge). A finger at the edge reaches the app too until the system decides it is its gesture
// and takes it (a cancel here); an edge swipe of mbui's started meanwhile was called off by that cancel, and the page
// went back to its place, deaf to the system's steps after it.

///|
fn back_view(nav : Nav[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.nav(nav, fn(p) { c.text("title \{p}", wrap=false) |> ignore }, bg=0xFFFFFFFFL)
    |> ignore
  }
}

///|
/// A frame on, its time an input's step later.
fn back_step(t : Tester) -> Unit {
  let at = t.fake.time + input_step_ms
  t.fake.time = at
  t.frame_at(at)
}

///|
test "on Android the swipe from the edge is the system's: the finger taken from the app, the page goes on following it" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(move_most_ms)
  // the finger down at the edge and moving, seen by the app and by the system, which starts its gesture
  t.touch(0, 2.0, 400.0)
  on_back(0, 2.0, 0.0, 0)
  t.touch(1, 30.0, 400.0)
  on_back(1, 30.0, 0.0, 0)
  back_step(t)
  // the system takes the finger from the app: a cancel
  t.touch(3, 30.0, 400.0)
  for x in [70.0, 110.0, 150.0] {
    on_back(1, x, 0.0, 0)
    back_step(t)
  }
  // where the system says the finger is, from where it began
  assert_eq(t.rect_of("title 2").unwrap().0, 148.0)
  on_back(2, 0.0, 1.0, 0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
}

///|
test "on Android a swipe called off goes back with the system's progress as it falls, not standing where the finger lifted" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(move_most_ms)
  on_back(0, 0.0, 0.0, 0)
  back_step(t)
  // out, then quickly back, and lifted: the system's progress a little behind the finger
  for step in [(40.0, 0.08), (80.0, 0.17), (120.0, 0.26), (160.0, 0.35), (200.0, 0.43), (140.0, 0.38), (80.0, 0.27)] {
    on_back(1, step.0, step.1, 0)
    back_step(t)
  }
  assert_eq(t.rect_of("title 2").unwrap().0, 80.0)
  // called off: the system takes its progress to 0 on its own, the finger's place kept, before it says so
  let mut was = 80.0
  for progress in [0.2, 0.14, 0.09, 0.05, 0.02, 0.0] {
    on_back(1, 80.0, progress, 0)
    back_step(t)
    let x = t.rect_of("title 2").unwrap().0
    assert_true(x <= was, msg="\{x} \{was}")
    was = x
  }
  // back with it: where its progress is, there when it is
  assert_true(was < 1.0, msg="\{was}")
  on_back(3, 0.0, 0.0, 0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 2)
  assert_eq(t.rect_of("title 2").unwrap().0, 0.0)
}

///|
test "on Android a finger dragged from the edge is not a swipe back: the page stays where it is" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(move_most_ms)
  t.hold_drag(5.0, 400.0, 200.0, 400.0)
  assert_eq(t.rect_of("title 2").unwrap().0, 0.0)
  t.release(200.0, 400.0)
  t.draw()
  assert_eq(nav.depth(), 2)
  assert_eq(t.rect_of("title 2").unwrap().0, 0.0)
  t.assert_idle()
}

///|
test "on Android the system's back gesture's steps move the page as it follows them: no frame built again for one" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(move_most_ms)
  on_back(0, 0.0, 0.0, 0)
  back_step(t)
  // (the steps come between frames, as a host's do; the frame after the one the gesture began in is built, as that one asked)
  on_back(1, 20.0, 0.0, 0)
  back_step(t)
  for x in [40.0, 80.0, 120.0] {
    on_back(1, x, 0.0, 0)
    back_step(t)
    assert_eq(t.built_why(), "")
  }
  assert_eq(t.rect_of("title 2").unwrap().0, 120.0)
  on_back(2, 0.0, 1.0, 0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
}
