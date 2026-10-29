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
  t.run_for(nav_push_ms)
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
test "on Android the page the system's back lets go goes on as fast as the finger went: no frame stands where it lifted" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(nav_push_ms)
  on_back(0, 0.0, 0.0, 0)
  back_step(t)
  for x in [20.0, 40.0, 60.0, 80.0, 100.0, 120.0] {
    on_back(1, x, 0.0, 0)
    back_step(t)
  }
  assert_eq(t.rect_of("title 2").unwrap().0, 120.0)
  // the finger lifted, moving 20 points a step: the system says back a step after its last
  on_back(2, 0.0, 1.0, 0)
  back_step(t)
  // gone on from where it lifted, at least as far as the finger would have taken it by now (two steps), and on
  let first = t.rect_of("title 2").unwrap().0
  assert_true(first >= 160.0)
  back_step(t)
  assert_true(t.rect_of("title 2").unwrap().0 > first + 10.0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
  assert_eq(t.rect_of("title 1").unwrap().0, 0.0)
}

///|
test "on Android a page the system's back lets go after the finger held still sets out from rest, from where it was" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(nav_push_ms)
  on_back(0, 0.0, 0.0, 0)
  back_step(t)
  for x in [40.0, 80.0, 120.0] {
    on_back(1, x, 0.0, 0)
    back_step(t)
  }
  // held still a while (no step said), then lifted
  for _ in 0..<10 {
    back_step(t)
  }
  on_back(2, 0.0, 1.0, 0)
  back_step(t)
  let first = t.rect_of("title 2").unwrap().0
  // (a moving finger's page is past 160 by then)
  assert_true(first > 120.0 && first < 140.0)
  t.run_for(nav.rest() - t.time())
  assert_eq(nav.depth(), 1)
}

///|
test "on Android a finger dragged from the edge is not a swipe back: the page stays where it is" {
  let nav = Nav::new(1)
  let t = Tester::new(back_view(nav), platform=2)
  nav.push(2)
  t.run_for(nav_push_ms)
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
  t.run_for(nav_push_ms)
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
