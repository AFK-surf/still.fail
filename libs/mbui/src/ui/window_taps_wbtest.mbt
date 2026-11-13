// The window's taps (View::window_taps) as the host tells the tree them (view_pointer): a tap as what took the press
// says it was one: a node's press run, a gesture's tap, a press on nothing let go near where it went down, never past a
// gesture's slop since; a press dragged, let go away, called off or taken over, none.

///|
/// A window 400 × 200 of the tree's alone: a button (0, 0, 100 × 50), a gesture's (0, 60, 100 × 50), nothing else; how
/// many taps the window has told, how many the button and the gesture took.
fn taps_tester() -> (Tester, () -> Int, Ref[Int], Ref[Int]) {
  let root : Ref[@view.View?] = Ref(None)
  let pressed = Ref(0)
  let tapped = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(r) {
    root.val = Some(r)
    r.box(fn(b) {
      b.width(Is(Some(100.0))).height(Is(Some(50.0))).on_press(fn() { pressed.val += 1 }) |> ignore
    })
    |> ignore
    r.box(fn(g) {
      g
      .width(Is(Some(100.0)))
      .height(Is(Some(50.0)))
      .margin(Is((0.0, 10.0, 0.0, 0.0)))
      .gesture(touch_slop(), tap=fn(_) { tapped.val += 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let taps = fn() { @signals.untracked(fn() { root.val.unwrap().window_taps() }) }
  (t, taps, pressed, tapped)
}

///|
test "the window's taps: on nothing, a press let go where it went down; moved past the slop and back, let go away with no move told, or called off, none" {
  let (t, taps, _, _) = taps_tester()
  let far = touch_slop() * 3.0
  t.tap(300.0, 150.0)
  assert_eq(taps(), 1)
  // (moved past the slop and back where it went down)
  t.touch(0, 300.0, 150.0)
  t.touch(1, 300.0 + far, 150.0)
  t.touch(1, 300.0, 150.0)
  t.touch(2, 300.0, 150.0)
  t.draw()
  assert_eq(taps(), 1, msg="moved past the slop and back")
  // (let go away, no move told)
  t.touch(0, 300.0, 150.0)
  t.touch(2, 300.0 + far, 150.0)
  t.draw()
  assert_eq(taps(), 1, msg="let go away")
  // (called off)
  t.touch(0, 300.0, 150.0)
  t.touch(3, 300.0, 150.0)
  t.draw()
  assert_eq(taps(), 1, msg="called off")
  // (within the slop: a tap)
  t.touch(0, 300.0, 150.0)
  t.touch(1, 300.0 + touch_slop() / 2.0, 150.0)
  t.touch(2, 300.0 + touch_slop() / 2.0, 150.0)
  t.draw()
  assert_eq(taps(), 2, msg="within the slop")
}

///|
test "the window's taps: a node's press run, a gesture's tap, each one; a gesture dragged, or a press let go off its node, none" {
  let (t, taps, pressed, tapped) = taps_tester()
  t.tap(50.0, 25.0)
  assert_eq((pressed.val, taps()), (1, 1))
  t.tap(50.0, 85.0)
  assert_eq((tapped.val, taps()), (1, 2))
  // (the gesture dragged past its slop)
  t.drag(50.0, 85.0, 50.0 + touch_slop() * 3.0, 85.0)
  assert_eq((tapped.val, taps()), (1, 2), msg="dragged")
  // (the button pressed, let go off it)
  t.touch(0, 50.0, 25.0)
  t.touch(2, 300.0, 150.0)
  t.draw()
  assert_eq((pressed.val, taps()), (1, 2), msg="let go off it")
}
