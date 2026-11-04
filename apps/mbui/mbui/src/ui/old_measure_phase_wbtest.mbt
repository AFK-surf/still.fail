// The compatibility leaf participates in the parent's layout. Its measured height is never another event.

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
test "an old natural leaf takes a click once and measures its changed height" {
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
  })
  t.frame(ms=16.0)
  t.tap_once(20.0, 20.0)
  t.frame(ms=16.0)
  assert_eq(clicks.get(), 1)
  assert_eq(leaf.val.unwrap().laid_size().1, 50.0)
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
