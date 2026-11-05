// A node's notch (View::notch) cut into its top as an old view's box's (Ctx::box `notch_*`, Ctx::notch_by): on its
// ground as it is drawn, none at a radius of 0; said again, its own layer alone drawn again, nothing of the old frame.

///|
test "a node's notch: cut into its ground as an old view's box's is, the same instance" {
  let old = Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(56.0), bg=0x2040FFFFL, radius=28.0, notch_y=-4.0, notch_r=20.0, notch_fillet=8.0, fn() {  })
    |> ignore
  })
  old.draw()
  old.frame()
  let was = old.drawn_notches()
  let t = Tester::new(fn(_c) {  }, w=200.0, h=56.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(Is(Some(56.0)))
      .ground(Is(0x2040FFFFL))
      .radius(Is(28.0))
      .notch(Is((-4.0, 20.0, 8.0)))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  assert_eq(t.drawn_notches().map(fn(n) { (n.1, n.2, n.3, n.4) }), was.map(fn(n) { (n.1, n.2, n.3, n.4) }))
  assert_eq(was.length(), 1)
}

///|
test "a node's notch said again: its own layer alone drawn again, where the node is; none at a radius of 0" {
  let notch = @signals.signal((-4.0, 20.0, 8.0), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(Is(Some(56.0)))
      .ground(Is(0xFFFFFFFFL))
      .radius(Is(28.0))
      .notch(By(fn() { notch.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  assert_eq(t.drawn_notches().map(fn(n) { (n.2, n.3, n.4) }), [(-4.0, 20.0, 8.0)])
  t.record_host()
  notch.set((-2.0, 10.0, 8.0))
  t.frame()
  let frames = t.host_frames()
  assert_eq(t.drawn_notches().map(fn(n) { (n.2, n.3, n.4) }), [(-2.0, 10.0, 8.0)])
  // (the window drawn again where the node is alone, its edge's antialiasing round it: 2 past it, none of the box
  // over it)
  let outside = frames.filter(fn(f) {
    f.damage.iter().any(fn(d) { d.2 < 0.0 || d.0 < -2.0 || d.1 < 200.0 - 2.0 || d.1 + d.3 > 256.0 + 2.0 || d.0 + d.2 > 200.0 + 2.0 })
  })
  assert_eq(outside.length(), 0, msg="\{frames}")
  assert_true(frames.iter().any(fn(f) { f.changed }), msg="\{frames}")
  notch.set((0.0, 0.0, 0.0))
  t.frame()
  assert_eq(t.drawn_notches().length(), 0)
}

///|
test "a node's shadow cast outside it only (View::shadow_outside): the same instance as an old view's box's shadow_out" {
  let shadow_of = fn(t : Tester) { t.drawn_instances().filter(fn(a) { a[5] == 2.0 }).map(fn(a) { a[0:14].to_array() }) }
  let old = Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(56.0), radius=28.0, shadow=6.0, shadow_color=0x00000029L, shadow_y=4.0, shadow_out=true, fn() {  })
    |> ignore
  })
  old.draw()
  old.frame()
  let was = shadow_of(old)
  let t = Tester::new(fn(_c) {  }, w=200.0, h=56.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(Is(Some(56.0)))
      .radius(Is(28.0))
      .shadow(Is((6.0, 4.0, 0x00000029L)))
      .shadow_outside(Is(true))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  assert_eq(was.length(), 1)
  assert_eq(shadow_of(t), was)
}

///|
test "a node's cut across (View::cut_across) said again: what it holds drawn again, all of it, where the node is" {
  let across = @signals.signal(Some((20.0, 60.0)), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(200.0))).height(Is(Some(56.0))).clips(Is(true)).cut_across(By(fn() { across.get() })) |> ignore
      b.box(fn(k) { k.width(Is(Some(200.0))).height(Is(Some(56.0))).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  let first = t.frame_export()
  t.record_host()
  across.set(Some((30.0, 90.0)))
  t.frame()
  let frames = t.host_frames()
  let outside = frames.filter(fn(f) {
    f.damage.iter().any(fn(d) { d.2 < 0.0 || d.0 < -2.0 || d.1 < 200.0 - 2.0 || d.1 + d.3 > 256.0 + 2.0 || d.0 + d.2 > 200.0 + 2.0 })
  })
  assert_eq(outside.length(), 0, msg="\{frames}")
  assert_true(frames.iter().any(fn(f) { f.changed && f.layers_drawn > 0 }), msg="\{frames}")
  assert_true(t.frame_export() != first)
}
