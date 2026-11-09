// A page made once whose stack takes its back, swiped from its edge while what holds it follows the finger (a stacked
// page slid off as it goes back: the tape's, the narrow shell's): each step to the stack from where it went down in the
// window, as the old frame's from where the page was as the gesture began, not from where the page has slid to.

///|
test "a page made once over another, its stack's back: its edge's swipe goes back when let go past a third, though the page slides with the finger" {
  let nav = Nav::new("a")
  nav.push("b")
  // ("b" at rest over "a": nothing here moves the stack but the swipe)
  nav.settle()
  nav.finger.set(0.0)
  let t = Tester::new(fn(_c) {  }, w=600.0, h=400.0, platform=1)
  set_view_app(fn(root) {
    // (the page, 100 in from the window's edge (whose own swipe is the frame's), slid across by as far as the finger has
    // the stack's top off to the side)
    root.box(fn(h) {
      h.over(Is(true)).offset(By(fn() { (100.0 + nav.finger.get() * 300.0, 0.0) })) |> ignore
      h.box(fn(m) {
        m.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        nav.backs_over(m, nav.pages[1].serial, 20.0, fn() {  })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.touch(0, 105.0, 50.0)
  t.advance(input_step_ms)
  for x in [125.0, 165.0, 205.0, 245.0, 285.0] {
    t.touch(1, x, 50.0)
    t.advance(input_step_ms)
  }
  let p = nav.offset()
  t.advance(input_step_ms * 20.0)
  t.touch(2, 285.0, 50.0)
  t.run_for(move_most_ms)
  // (180 across a page 300 wide: 0.6 of it, past a third; held still before it was let go, not flung)
  assert_true(p > 0.55 && p < 0.65, msg="offset \{p}")
  assert_eq(nav.depth(), 1)
}

///|
/// A stack of "a", "b" and "c", "c" at rest, its old floor 2 (as an old view of the same stack left it: Ctx::nav's
/// `floor`, nav_flat_view's island), the page made once of "c" held 100 in from the window's edge, its back the stack's
/// down to `floor` 1 (above "a": what nav_flat_view gives a page made once).
fn stack_floored() -> (Tester, Nav[String]) {
  let nav = Nav::new("a")
  nav.push("b")
  nav.push("c")
  nav.settle()
  nav.finger.set(0.0)
  nav.floor = 2
  let t = Tester::new(fn(_c) {  }, w=600.0, h=400.0, platform=1)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(By(fn() { (100.0 + nav.finger.get() * 300.0, 0.0) })) |> ignore
      h.box(fn(m) {
        m.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        nav.backs_over(m, nav.pages[2].serial, 20.0, floor=fn() { 1 }, fn() {  })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, nav)
}

///|
test "a page made once whose back is its stack's down to a floor of its own: the edge's swipe and the system's back both go back by that floor, not one the stack kept from an old view" {
  // (swiped 180 of its 300 and let go)
  let (t, nav) = stack_floored()
  t.touch(0, 105.0, 50.0)
  t.advance(input_step_ms)
  for x in [125.0, 165.0, 205.0, 245.0, 285.0] {
    t.touch(1, x, 50.0)
    t.advance(input_step_ms)
  }
  t.advance(input_step_ms * 20.0)
  t.touch(2, 285.0, 50.0)
  t.run_for(move_most_ms)
  assert_eq(nav.depth(), 2, msg="swiped")
  // (the system's back, no gesture)
  let (t, nav) = stack_floored()
  t.back()
  t.run_for(move_most_ms)
  assert_eq(nav.depth(), 2, msg="the system's back")
}

///|
test "a wide page's edge swipe goes back past back_far, short of a third of its width; short of back_far it stays" {
  for case in [(150.0, 1), (100.0, 2)] {
    let (dx, depth) = case
    let nav = Nav::new("a")
    nav.push("b")
    nav.settle()
    nav.finger.set(0.0)
    let t = Tester::new(fn(_c) {  }, w=1000.0, h=400.0, platform=1)
    set_view_app(fn(root) {
      root.box(fn(m) {
        m.width(Is(Some(900.0))).height(Is(Some(300.0))) |> ignore
        nav.backs_over(m, nav.pages[1].serial, 20.0, fn() {  })
      })
      |> ignore
    })
    t.draw()
    t.touch(0, 5.0, 50.0)
    t.advance(input_step_ms)
    for i in 1..=5 {
      t.touch(1, 5.0 + dx * i.to_double() / 5.0, 50.0)
      t.advance(input_step_ms)
    }
    // (held still before it was let go, not flung: only how far it went decides)
    t.advance(input_step_ms * 20.0)
    t.touch(2, 5.0 + dx, 50.0)
    t.run_for(move_most_ms)
    assert_eq(nav.depth(), depth, msg="\{dx} across a page 900 wide")
  }
}
