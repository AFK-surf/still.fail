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

///|
test "small gestures reach their press rooms, divided between neighbours and respecting disabled controls" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=90.0, platform=2)
  t.check_looks(false)
  let off = @signals.signal(false)
  let said : Array[String] = []
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.width(Is(Some(200.0))).height(Is(Some(90.0))).row(Is(true))
      .padding(Is((30.0, 20.0, 0.0, 0.0))).gap(Is(8.0)).on_press(fn() { said.push("ground") }) |> ignore
      for label in ["First", "Second"] {
        row.box(fn(v) {
          v.width(Is(Some(20.0))).height(Is(Some(20.0)))
          .turned_off(By(fn() { label == "First" && off.get() }))
          .says(Is(Some(@view.said(Button, label~))))
          .gesture(touch_slop(), tap=fn(d) {
            if v.finger_target(d.wx, d.wy) { said.push(label) }
          }) |> ignore
        }) |> ignore
      }
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(Button, label="First").rect
  let (sx, sy, sw, sh) = t.get(Button, label="Second").rect
  t.tap(x + w / 2.0, y + h + 6.0)
  t.tap(sx + sw / 2.0, sy + sh + 6.0)
  // In the overlapping rooms, the nearer button wins.
  t.tap(x + w + 6.0, y + h / 2.0)
  assert_eq(said, ["First", "Second", "Second"])
  said.clear()
  off.set(true)
  t.tap(x + w / 2.0, y + h / 2.0)
  t.tap(x + w / 2.0, y + h + 6.0)
  assert_eq(said, ["ground"])
}

///|
test "a gesture begun on its drawing lets go outside without a tap; one begun in its press room can tap there" {
  for platform in [0, 2] {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=90.0, platform~)
    t.check_looks(false)
    let said : Array[String] = []
    set_view_app(fn(root) {
      root.box(fn(row) {
        row.padding(Is((30.0, 20.0, 0.0, 0.0))) |> ignore
        row.box(fn(v) {
          v.width(Is(Some(20.0))).height(Is(Some(20.0)))
          .says(Is(Some(@view.said(Button, label="Small"))))
          .gesture(touch_slop(), tap=fn(d) {
            if v.finger_target(d.wx, d.wy) { said.push("tap") }
          }) |> ignore
        }) |> ignore
      }) |> ignore
    })
    t.draw()
    let (x, y, w, h) = t.get(Button, label="Small").rect
    let cy = y + h / 2.0
    t.touch_at(0, x + w - 1.0, cy, 10.0)
    t.touch_at(2, x + w + 2.0, cy, 20.0)
    assert_eq(said, [], msg="platform \{platform}: a press begun on its drawing")
    t.touch_at(0, x + w + 2.0, cy, 30.0)
    t.touch_at(2, x + w + 2.0, cy, 40.0)
    t.touch_at(0, x + w + 2.0, cy, 50.0)
    t.touch_at(2, x + w - 1.0, cy, 60.0)
    assert_eq(said, ["tap", "tap"], msg="platform \{platform}: presses begun in its room")
  }
}

///|
test "a resize gesture is reached only in its drawn strip" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=90.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.padding(Is((30.0, 20.0, 0.0, 0.0))) |> ignore
      row.box(fn(v) {
        v.width(Is(Some(12.0))).height(Is(Some(40.0)))
        .cursor(Is(Some(ResizeX)))
        .says(Is(Some(@view.said(Separator, label="Edge"))))
        .gesture(touch_slop(), tap=fn(_) {  }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(Separator, label="Edge").rect
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.cursor(), ResizeX)
  t.move(x + w + 2.0, y + h / 2.0)
  assert_true(t.cursor() != ResizeX)
}

///|
test "a gesture reached outside its drawing can still yield to its scroll ancestor" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=100.0, platform=2)
  t.check_looks(false)
  let list = @view.Scroll::new()
  let said : Array[String] = []
  set_view_app(fn(root) {
    root.box(fn(panel) {
      panel.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(list, fn(body) {
        body.box(fn(gap) { gap.height(Is(Some(30.0))) |> ignore }) |> ignore
        body.box(fn(v) {
          v.width(Is(Some(20.0))).height(Is(Some(20.0)))
          .says(Is(Some(@view.said(Button, label="Small"))))
          .gesture(touch_slop(), press=fn(_) { said.push("down") }, tap=fn(_) { said.push("tap") },
            drag=fn(d) { if d.kind == Off { said.push("off") } }) |> ignore
        }) |> ignore
        body.box(fn(gap) { gap.height(Is(Some(300.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(Button, label="Small").rect
  t.touch_at(0, x + w / 2.0, y + h + 6.0, 10.0)
  t.touch_at(1, x + w / 2.0, y + h - 24.0, 20.0)
  t.touch_at(2, x + w / 2.0, y + h - 24.0, 30.0)
  assert_eq(said, ["down", "off"])
  assert_true(list.at(view_tree().unwrap()) > 0.0)
}
