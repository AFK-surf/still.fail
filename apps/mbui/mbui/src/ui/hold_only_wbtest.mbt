// A gesture that answers a hold alone (View::gesture's `hold`, nothing else: hold_in.mbt) takes no press nor drag of
// its own: a finger on it presses or drags the first out from it that takes one; held still as long as its hold, its
// hold, and what had the finger nothing of it (no press, no tap).

///|
/// A row 300 by 100 at the window's top left, pressed counted in `pressed` where `presses`, else dragged (a gesture's:
/// each word counted in `drags`); in it at its top left a mark 120 by 40, its hold alone counted in `held`, and in that
/// one where `inner` another 60 by 20 at its top left, its hold alone counted in `inner_held`.
fn hold_only_row(
  pressed : Ref[Int],
  held : Ref[Int],
  presses? : Bool = true,
  drags? : Ref[Int] = Ref(0),
  inner? : Ref[Int]? = None,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.width(Is(Some(300.0))).height(Is(Some(100.0))).says(Is(Some(@view.said(Button, label="Row")))) |> ignore
      if presses {
        r.on_press(fn() { pressed.val = pressed.val + 1 }) |> ignore
      } else {
        r.gesture(touch_slop(), drag=fn(_) { drags.val = drags.val + 1 }) |> ignore
      }
      r.box(fn(v) {
        v
        .width(Is(Some(120.0)))
        .height(Is(Some(40.0)))
        .says(Is(Some(@view.said(Image, label="Avatar"))))
        .gesture(touch_slop(), hold=(long_press_ms, fn(_) { held.val = held.val + 1 }))
        |> ignore
        match inner {
          Some(n) =>
            v.box(fn(i) {
              i
              .width(Is(Some(60.0)))
              .height(Is(Some(20.0)))
              .says(Is(Some(@view.said(Image, label="Badge"))))
              .gesture(touch_slop(), hold=(long_press_ms, fn(_) { n.val = n.val + 1 }))
              |> ignore
            })
            |> ignore
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a mark in a pressed row that answers only a hold: tapped, the row pressed; held, its hold, the row not pressed" {
  let pressed = Ref(0)
  let held = Ref(0)
  let t = hold_only_row(pressed, held)
  // (tapped: the row's press)
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq((pressed.val, held.val), (1, 0))
  // (held as long as a long press, still: the mark's hold; let go, nothing pressed)
  t.touch(0, 20.0, 20.0)
  t.run_for(long_press_ms)
  assert_eq((pressed.val, held.val), (1, 1))
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq((pressed.val, held.val), (1, 1))
  // (beside the mark, in the row: pressed, as ever)
  t.touch(0, 200.0, 60.0)
  t.touch(2, 200.0, 60.0)
  t.draw()
  assert_eq(pressed.val, 2)
}

///|
test "a mark that answers only a hold, the finger moved past its slop before the hold: no hold, the row's as ever" {
  let pressed = Ref(0)
  let held = Ref(0)
  let t = hold_only_row(pressed, held)
  t.touch(0, 20.0, 20.0)
  t.touch(1, 20.0 + touch_slop() * 3.0, 20.0)
  t.run_for(long_press_ms)
  assert_eq(held.val, 0)
  // (let go in the row: its press, as a press moved within it is)
  t.touch(2, 20.0 + touch_slop() * 3.0, 20.0)
  t.draw()
  assert_eq((pressed.val, held.val), (1, 0))
}

///|
test "two marks that answer only a hold, one in the other: held, the innermost's hold alone" {
  let pressed = Ref(0)
  let held = Ref(0)
  let inner = Ref(0)
  let t = hold_only_row(pressed, held, inner=Some(inner))
  t.touch(0, 10.0, 10.0)
  t.run_for(long_press_ms)
  t.touch(2, 10.0, 10.0)
  t.draw()
  assert_eq((inner.val, held.val, pressed.val), (1, 0, 0))
}

///|
test "a mark that answers only a hold in a row that drags: dragged from it, the row's drag; no hold of the mark's" {
  let pressed = Ref(0)
  let held = Ref(0)
  let drags = Ref(0)
  let t = hold_only_row(pressed, held, presses=false, drags~)
  t.touch(0, 20.0, 20.0)
  t.touch(1, 80.0, 20.0)
  t.touch(1, 140.0, 20.0)
  t.run_for(long_press_ms)
  t.touch(2, 140.0, 20.0)
  t.draw()
  assert_true(drags.val > 0, msg="the row not dragged")
  assert_eq(held.val, 0)
}
