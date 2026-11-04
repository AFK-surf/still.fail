// The compatibility leaf participates in the parent's layout. Its measured height is never another event.

///|
test "an old natural leaf is measured in the window tree's theme before its first frame and after resize" {
  let base = Theme::light()
  let app_theme = { ..base, text: { ..base.text, meta: (40.0, 48.0) } }
  let next_theme = { ..base, text: { ..base.text, meta: (20.0, 24.0) } }
  let changed = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  let leaf : Ref[@view.View?] = Ref(None)
  let following : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    set_tree_theme(fn() { if changed.get() { next_theme } else { app_theme } })
    leaf.val = Some(old(root, natural=true, fn(c) { c.text("words", style=text_style(size=Meta)) |> ignore }))
    following.val = Some(root.box(fn(n) { n.height(Is(Some(10.0))) |> ignore }))
  })
  t.frame(ms=16.0)
  assert_eq((leaf.val.unwrap().laid_size().1, following.val.unwrap().rect().1), (48.0, 48.0))
  t.resize(200.0, 300.0)
  assert_eq((leaf.val.unwrap().laid_size().1, following.val.unwrap().rect().1), (48.0, 48.0))
  changed.set(true)
  t.frame(ms=16.0)
  assert_eq((leaf.val.unwrap().laid_size().1, following.val.unwrap().rect().1), (24.0, 24.0))
}

///|
test "an old natural leaf returns its first and changed height in the parent's only layout" {
  let rows = @signals.signal(2)
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  let leaf : Ref[@view.View?] = Ref(None)
  let marker : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    leaf.val = Some(old(root, natural=true, fn(c) {
      for _ in 0..<rows.get() { c.box(h=Px(30.0), fn() { }) |> ignore }
    }))
    marker.val = Some(root.box(fn(m) { m.height(Is(Some(10.0))).ground(Is(0x13579bffL)) |> ignore }))
  })
  t.frame(ms=16.0)
  assert_eq(leaf.val.unwrap().laid_size().1, 60.0)
  assert_eq(marker.val.unwrap().rect().1, 60.0)
  let before = view_tree().unwrap().work().computes
  rows.set(4)
  t.frame(ms=16.0)
  assert_eq(leaf.val.unwrap().laid_size().1, 120.0)
  assert_eq(marker.val.unwrap().rect().1, 120.0)
  assert_eq(view_tree().unwrap().work().computes - before, 1)
}

///|
test "an old natural leaf's content changes are measured before an event reads geometry" {
  let tall = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  let marker : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    old(root, natural=true, fn(c) { c.box(h=Px(if tall.get() { 120.0 } else { 30.0 }), fn() { }) |> ignore }) |> ignore
    marker.val = Some(root.box(fn(m) { m.height(Is(Some(10.0))) |> ignore }))
  })
  t.frame(ms=16.0)
  let seen = Ref(-1.0)
  let tree = view_tree().unwrap()
  tree.event(20.0, fn() { tall.set(true) })
  tree.event(25.0, fn() { seen.val = marker.val.unwrap().laid_place_now().1 })
  assert_eq(seen.val, 120.0)
}

///|
test "an old natural leaf follows the size of a separately kept component inside it" {
  let tall = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  let leaf : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    leaf.val = Some(old(root, natural=true, fn(c) {
      c.part_nodes(c.id("inside"), "", fn() {
        c.box(h=Px(if tall.get() { 120.0 } else { 30.0 }), fn() { }) |> ignore
      }, false, flows=true)
    }))
  })
  t.frame(ms=16.0)
  assert_eq(leaf.val.unwrap().laid_size().1, 30.0)
  view_tree().unwrap().event(20.0, fn() { tall.set(true) })
  assert_eq(leaf.val.unwrap().laid_size().1, 120.0)
}

///|
test "an old natural leaf takes a click once before the frame that measures its changed height" {
  let clicks = @signals.signal(0)
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  let leaf : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    leaf.val = Some(old(root, natural=true, fn(c) {
      let id = c.id("grow")
      if c.clicked(id) { clicks.set(clicks.get() + 1) }
      c.box(id~, w=Px(100.0), h=Px(30.0 + clicks.get().to_double() * 20.0), bg=0x13579bffL, fn() { }) |> ignore
    }))
    root.box(fn(m) { m.height(Is(Some(10.0))).ground(Is(0x2468acffL)) |> ignore }) |> ignore
  })
  t.frame(ms=16.0)
  finger(0, 20.0, 20.0)
  finger(2, 20.0, 20.0)
  let before = view_tree().unwrap().work().computes
  t.frame(ms=16.0)
  assert_eq(clicks.get(), 1)
  assert_true(t.drawn_rects().contains((0.0, 50.0, 200.0, 10.0, 0x2468acffL)), msg="the following sibling is already below the changed leaf in the first frame")
  let layouts = view_tree().unwrap().work().computes - before
  // The event may already have resolved the changed size for the next input. A display frame can reuse it.
  assert_true(layouts <= 1, msg="layouts in the host frame: \{layouts}")
  assert_eq(leaf.val.unwrap().laid_size().1, 50.0)
}

///|
test "an old leaf's click changes the next event's target with or without a frame between" {
  let pictures : Array[Array[(Double, Double, Double, Double, Int64)]] = []
  for between in [false, true] {
    let clicks = @signals.signal(0)
    let following = Ref(0)
    let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
    t.check_looks(false)
    set_view_app(fn(root) {
      old(root, natural=true, fn(c) {
        let id = c.id("grow")
        if c.clicked(id) { clicks.set(clicks.get() + 1) }
        c.box(id~, w=Px(100.0), h=Px(30.0 + clicks.get().to_double() * 20.0), bg=0x13579bffL, fn() { }) |> ignore
      }) |> ignore
      root.box(fn(n) {
        n.height(Is(Some(20.0))).ground(Is(0x2468acffL)).presses(Is(true)).on_press(fn() { following.val += 1 }) |> ignore
      }) |> ignore
    })
    t.frame_at(16.0)
    t.advance(4.0)
    finger(0, 20.0, 20.0)
    finger(2, 20.0, 20.0)
    assert_eq(clicks.get(), 1, msg="input is committed before a display frame")
    if between { t.frame_at(35.0) } else { t.advance(15.0) }
    t.advance(15.0)
    finger(0, 20.0, 55.0)
    finger(2, 20.0, 55.0)
    t.frame_at(80.0)
    assert_eq((clicks.get(), following.val), (1, 1), msg="between frames \{between}")
    pictures.push(t.drawn_rects())
  }
  assert_eq(pictures[0], pictures[1])
}

///|
test "a changed old leaf uses its new internal hit geometry before the next frame" {
  for between in [false, true] {
    let tall = @signals.signal(false)
    let pressed = Ref(0)
    let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
    t.check_looks(false)
    set_view_app(fn(root) {
      old(root, natural=true, fn(c) {
        let grow = c.id("grow")
        if c.clicked(grow) { tall.set(true) }
        c.box(id=grow, w=Px(100.0), h=Px(if tall.get() { 50.0 } else { 30.0 }), fn() { }) |> ignore
        let next = c.id("next")
        if c.clicked(next) { pressed.val += 1 }
        c.box(id=next, w=Px(100.0), h=Px(20.0), fn() { }) |> ignore
      }) |> ignore
    })
    t.frame_at(16.0)
    t.advance(4.0)
    finger(0, 20.0, 20.0)
    finger(2, 20.0, 20.0)
    if between { t.frame_at(35.0) } else { t.advance(15.0) }
    t.advance(15.0)
    finger(0, 20.0, 60.0)
    finger(2, 20.0, 60.0)
    assert_eq(pressed.val, 1, msg="new target before frame, inserted frame \{between}")
  }
}

///|
test "separate old leaves keep both updated target layouts between frames" {
  let tall = [@signals.signal(false), @signals.signal(false)]
  let pressed = [0, 0]
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    for k in 0..<2 {
      root.box(fn(part) {
        part.height(Is(Some(120.0))) |> ignore
        old(part, natural=true, fn(c) {
          c.box(w=Px(100.0), h=Px(if tall[k].get() { 50.0 } else { 30.0 }), fn() { }) |> ignore
          let next = c.id("next \{k}")
          if c.clicked(next) { pressed[k] += 1 }
          c.box(id=next, w=Px(100.0), h=Px(20.0), fn() { }) |> ignore
        }) |> ignore
      }) |> ignore
    }
  })
  t.frame_at(16.0)
  for k in 0..<2 {
    t.advance(10.0)
    view_event(fn() { tall[k].set(true) })
    finger(1, 180.0, 300.0)
  }
  t.advance(10.0)
  finger(0, 20.0, 60.0)
  finger(2, 20.0, 60.0)
  finger(0, 20.0, 180.0)
  finger(2, 20.0, 180.0)
  assert_eq(pressed, [1, 1])
}

///|
test "an old leaf commits keyboard and semantic activation once before its first changed frame" {
  for semantic in [false, true] {
    let clicks = @signals.signal(0)
    let id = Ref(0)
    let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
    t.check_looks(false)
    set_view_app(fn(root) {
      old(root, natural=true, fn(c) {
        id.val = c.id("grow")
        if c.clicked(id.val) || c.key_pressed(key_of_char('g')) { clicks.set(clicks.get() + 1) }
        let b = c.box(id=id.val, w=Px(100.0), h=Px(30.0 + clicks.get().to_double() * 20.0), bg=0x13579bffL, fn() { })
        c.semantics(b, Button, label="grow")
      }) |> ignore
      root.box(fn(n) { n.height(Is(Some(10.0))).ground(Is(0x2468acffL)) |> ignore }) |> ignore
    })
    t.frame_at(16.0)
    t.advance(4.0)
    if semantic { g().ask_action(id.val, Activate) } else { t.key_told(key_of_char('g'), 0, 20.0) }
    assert_eq(clicks.get(), 1, msg="semantic \{semantic}: handled at the event")
    t.frame_at(32.0)
    assert_eq(clicks.get(), 1, msg="semantic \{semantic}: not handled again by paint")
    assert_true(t.drawn_rects().contains((0.0, 50.0, 200.0, 10.0, 0x2468acffL)))
  }
}

///|
test "measuring an old leaf neither observes nor consumes the pending input of the real build" {
  let seen : Array[String] = []
  let id = 987123
  let t = Tester::new(fn(_) { }, w=200.0, h=400.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, natural=true, fn(c) {
      if c.clicked(id) { seen.push("click") }
      if c.double_clicked(id) { seen.push("double") }
      if c.hovered(id) { seen.push("hover") }
      if c.take_key(key_escape) { seen.push("key") }
      if c.menu_asked(id) is Some(_) { seen.push("menu") }
      if c.action_asked(id, Activate) { seen.push("activate") }
      if c.text_asked(id) is Some(_) { seen.push("text") }
      if c.tapped_anywhere() is Some(_) { seen.push("tap") }
      c.box(w=Px(100.0), h=Px(30.0), fn() { }) |> ignore
    }) |> ignore
  })
  t.frame(ms=16.0)
  let c = g()
  c.clicked.push(id)
  c.double_clicked.push(id)
  c.tapped = Some((20.0, 20.0))
  desk.keys.push((key_escape, 0, false))
  desk.menus.push(([id], 20.0, 20.0))
  c.actions.push((id, Activate))
  c.actions.push((id, SetText("new words")))
  old_measure(c, old_islands[0], 200.0) |> ignore
  assert_eq(seen, [])
  assert_true(c.clicked(id))
  assert_true(c.double_clicked(id))
  assert_eq(c.tapped_anywhere(), Some((20.0, 20.0)))
  assert_true(c.take_key(key_escape))
  assert_false(c.take_key(key_escape))
  assert_eq(c.menu_asked(id), Some((20.0, 20.0)))
  assert_true(c.action_asked(id, Activate))
  assert_eq(c.text_asked(id), Some("new words"))
}
