// A finger on a node of the window's tree held (View::on_drag), as a host hands it on: the node's from down to up, each
// event at its own moment, whatever old view lies under it and whatever frames come.

///|
test "window tree: a finger held on a node over an old view: down, moved off it, up, the node's at their own moments" {
  let seen : Array[(@view.DragIs, Double, Double, Double)] = []
  let old_taps = Ref(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("under")
      if c.clicked(id) {
        old_taps.val = old_taps.val + 1
      }
      c.box(w=Fill(1.0), h=Fill(1.0), id~, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) {
        h.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push((d.kind, d.x, d.y, d.at)) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let t0 = t.time()
  // (taken late, each said with its own moment)
  t.advance(30.0)
  t.touch_at(0, 10.0, 10.0, t0 + 5.0)
  t.touch_at(1, 200.0, 300.0, t0 + 15.0)
  t.touch_at(2, 210.0, 310.0, t0 + 25.0)
  t.drawn_now()
  assert_eq(seen, [(Down, 10.0, 10.0, t0 + 5.0), (Moved, 200.0, 300.0, t0 + 15.0), (Up, 210.0, 310.0, t0 + 25.0)])
  assert_eq(old_taps.val, 0)
}

///|
test "window tree: a finger held on a node, a second one put down: the hold called off; the old view under it takes none of it" {
  let seen : Array[@view.DragIs] = []
  let old_seen = Ref(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("under")
      match c.drag_of(id) {
        Some(_) => old_seen.val = old_seen.val + 1
        None => ()
      }
      c.drag_area(id, axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) { h.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d.kind) }) |> ignore })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let before = old_seen.val
  t.touch(0, 10.0, 10.0)
  t.touch(4, 50.0, 50.0)
  t.touch(5, 60.0, 60.0)
  t.touch(1, 20.0, 20.0)
  t.touch(6, 60.0, 60.0)
  t.touch(2, 20.0, 20.0)
  t.drawn_now()
  assert_eq((seen, old_seen.val), ([Down, Off], before))
}

///|
test "window tree: a finger held on a node, the window no longer in front: called off then, its hold never come" {
  let said : Array[String] = []
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) {
        h
        .width(Is(Some(100.0)))
        .height(Is(Some(100.0)))
        .gesture(6.0, hold=(300.0, fn(_) { said.push("hold") }), drag=fn(d) { said.push("\{d.kind}") })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  app_state_taken(3)
  t.touch(0, 10.0, 10.0)
  t.advance(50.0)
  app_state_taken(1)
  t.run_for(500.0)
  assert_eq(said, ["Off"])
}

///|
/// A node of the tree's pressed (a finger down on it, let go on it), with `between` done while it is down: whether it
/// was pressed, and whether the old view under it took any of it.
fn press_with(between : (Tester, @signals.Signal[Bool]) -> Unit) -> (Int, Int) {
  let pressed = Ref(0)
  let old_seen = Ref(0)
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("under")
      if c.clicked(id) {
        old_seen.val = old_seen.val + 1
      }
      c.box(w=Fill(1.0), h=Fill(1.0), id~, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) {
        h
        .width(Is(Some(100.0)))
        .height(Is(Some(100.0)))
        .presses(By(fn() { on.get() }))
        .on_press(fn() { pressed.val = pressed.val + 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t.app_state(true, true)
  t.touch(0, 10.0, 10.0)
  between(t, on)
  t.touch(2, 10.0, 10.0)
  t.drawn_now()
  (pressed.val, old_seen.val)
}

///|
test "window tree: a press on a node called off as a hold is: the window behind, the node taking no press a while, a second finger" {
  let plain = press_with(fn(_t, _on) {  })
  let behind = press_with(fn(t, _on) { t.app_state(true, false) })
  let pressless = press_with(fn(_t, on) {
    on.set(false)
    on.set(true)
  })
  let second = press_with(fn(t, _on) {
    t.touch(4, 50.0, 50.0)
    t.touch(6, 50.0, 50.0)
  })
  assert_eq((plain, behind, pressless, second), ((1, 0), (0, 0), (0, 0), (0, 0)))
}
