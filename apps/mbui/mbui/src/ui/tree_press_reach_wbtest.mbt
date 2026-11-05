// A small control inside a field (a composer's attach button in its ground) reached from round it in the window's tree as in
// the old frame (press_reach): a press's room at least 36 points across with a keyboard and mouse, 44 with a finger; the
// pointer lit and a press taken by the same (Tree::target_in, Tree::reached).

///|
fn cursor_reach_probe(node : Bool) -> (Cursor, Int) {
  let hits = Ref(0)
  let t = Tester::new(fn(c) {
    if !node {
      let cap = c.id("composer")
      let button = c.id("attach")
      c.cursor(cap, IBeam)
      c.clicked(cap) |> ignore
      if c.clicked(button) { hits.val = hits.val + 1 }
      c.box(w=Px(120.0), h=Px(60.0), pl=20.0, pt=14.0, id=cap, fn() {
        c.box(w=Px(32.0), h=Px(32.0), id=button, fn() { }) |> ignore
      }) |> ignore
    }
  }, w=120.0, h=60.0, platform=0)
  if node {
    set_view_app(fn(root) {
      root.box(fn(cap) {
        cap.width(Is(Some(120.0))).height(Is(Some(60.0))).padding(Is((20.0, 14.0, 0.0, 0.0)))
        .presses(Is(true)).on_press(fn() { }).cursor(Is(Some(IBeam))) |> ignore
        cap.box(fn(button) {
          button.width(Is(Some(32.0))).height(Is(Some(32.0))).presses(Is(true))
          .on_press(fn() { hits.val = hits.val + 1 }) |> ignore
        }) |> ignore
      }) |> ignore
    })
  }
  t.draw()
  // A 32-point control has a 36-point room on a keyboard-and-mouse screen; x=19 is just outside its drawn x=20.
  t.move(19.0, 30.0)
  let cursor = t.cursor()
  t.press_at(19.0, 30.0)
  t.release(19.0, 30.0)
  (cursor, hits.val)
}

///|
test "a small button inside a field has the same pointer and press reach in the tree as the old frame" {
  assert_eq(cursor_reach_probe(false), (Hand, 1), msg="the old frame reaches the button")
  assert_eq(cursor_reach_probe(true), (Hand, 1), msg="the tree reaches the button")
}

///|
/// A field pressed for its ground, a 32-point button in it turned off: where the pointer at (x, y) is, its shape, and
/// how many presses the button and the field took.
fn turned_off_probe(x : Double, y : Double) -> (Cursor, Int, Int) {
  let hits = Ref(0)
  let ground = Ref(0)
  let t = Tester::new(fn(_) {  }, w=120.0, h=60.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(cap) {
      cap.width(Is(Some(120.0))).height(Is(Some(60.0))).padding(Is((20.0, 14.0, 0.0, 0.0)))
      .presses(Is(true)).on_press(fn() { ground.val = ground.val + 1 }).cursor(Is(Some(IBeam))) |> ignore
      cap.box(fn(button) {
        button.width(Is(Some(32.0))).height(Is(Some(32.0))).turned_off(Is(true))
        .on_press(fn() { hits.val = hits.val + 1 }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.move(x, y)
  let cursor = t.cursor()
  t.press_at(x, y)
  t.release(x, y)
  (cursor, hits.val, ground.val)
}

///|
test "a button turned off in a field: the pointer an arrow over it, its press taken by nothing, the field not pressed" {
  assert_eq(turned_off_probe(36.0, 30.0), (Arrow, 0, 0))
  // (beside it, the field's own)
  assert_eq(turned_off_probe(100.0, 30.0), (IBeam, 0, 1))
}
