// Integration of C1's host damage with #4269's one wake per layer. Inputs and frames go through the Tester; none
// of the scene's wake or damage functions is called by this test. Each glyph look asks for its next step while
// painted. The glyphs here are synthetic, not pixel evidence.

///|
test "two layers waking together or separately retain moved and redrawn reaches without duplicate pending wakes" {
  for checked in [false, true] {
    for other_period in [300.0, 450.0] {
      let x = @signals.signal(20.0)
      let word = @signals.signal("x")
      let t = Tester::new(fn(_) { }, w=440.0, h=300.0)
      set_view_app(fn(root) {
        root.box(fn(n) {
          n.over(Is(true)).offset(By(fn() { (x.get(), 20.0) })).width(Is(Some(100.0))).height(Is(Some(50.0))) |> ignore
          n.words(By(fn() { "a \{word.get()}" })).glyphs_by(Is(Some(0.0)), fn(_, _) {
            { alpha: 1.0, dx: 0.0, dy: (g().every(300.0) % 2).to_double() * 5.0, scale: 1.0, sx: 1.0 }
          }) |> ignore
        }) |> ignore
        root.box(fn(n) {
          n.over(Is(true)).offset(Is((260.0, 20.0))).width(Is(Some(100.0))).height(Is(Some(50.0))) |> ignore
          n.words(Is("b")).glyphs_by(Is(Some(0.0)), fn(_, _) {
            { alpha: 1.0, dx: 0.0, dy: (g().every(other_period) % 2).to_double() * 5.0, scale: 1.0, sx: 1.0 }
          }) |> ignore
        }) |> ignore
        root.box(fn(n) {
          n.over(Is(true)).offset(Is((380.0, 20.0))).width(Is(Some(40.0))).height(Is(Some(40.0)))
            .ground(Is(0x1559C4FFL)) |> ignore
        }) |> ignore
      })
      t.draw()
      t.measure_as_host()
      t.check_looks(checked)
      t.record_host()
      let at = t.time()
      let first = periods_at(at, 0.0, 300.0).1
      let second = periods_at(at, 0.0, other_period).1
      assert_true(at + 40.0 < first && first <= second)
      let mut before = t.glyphs_shown().filter(fn(r) { r.0 < 250.0 })
      assert_false(before.is_empty())
      for (x_to, ms, text) in [(80.0, 20.0, "xy"), (140.0, 40.0, "z")] {
        x.set(x_to)
        word.set(text)
        t.frame_at(at + ms)
        let frame = t.host_frames()[0]
        let after = t.glyphs_shown().filter(fn(r) { r.0 < 250.0 })
        assert_true(before.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="old reach erased: \{frame}")
        assert_true(after.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="new reach drawn: \{frame}")
        before = after
      }
      let pending = scene.wakes.length()
      let work = scene.parts.work()
      t.frame_at(first)
      let a = t.host_frames()[0]
      assert_true(a.changed)
      assert_true(before.iter().all(fn(r) { paint_damage_covers(a, r) }), msg="first layer's wake: \{a}")
      let after = t.glyphs_shown().filter(fn(r) { r.0 < 250.0 })
      assert_true(after.iter().all(fn(r) { paint_damage_covers(a, r) }), msg="first layer's new reach: \{a}")
      assert_true(a.damage.iter().all(fn(p) { p.2 >= 0.0 && p.0 + p.2 < 380.0 }))
      let other = t.glyphs_shown().filter(fn(r) { r.0 >= 260.0 })
      assert_false(other.is_empty())
      if second == first {
        assert_true(other.iter().all(fn(r) { paint_damage_covers(a, r) }), msg="both layers due: \{a}")
      } else {
        assert_true(a.damage.iter().all(fn(p) { p.0 + p.2 < 260.0 }), msg="second layer is not yet due: \{a}")
        t.frame_at(second)
        let b = t.host_frames()[0]
        assert_true(b.changed)
        assert_true(other.iter().all(fn(r) { paint_damage_covers(b, r) }), msg="second layer's wake: \{b}")
        let after = t.glyphs_shown().filter(fn(r) { r.0 >= 260.0 })
        assert_true(after.iter().all(fn(r) { paint_damage_covers(b, r) }), msg="second layer's new reach: \{b}")
        assert_true(b.damage.iter().all(fn(p) { p.2 >= 0.0 && p.0 >= 258.0 && p.0 + p.2 < 380.0 }),
          msg="first layer and blue block remain kept: \{b}")
        println("separate wake at \{second}: \{b.damage}")
      }
      println("two-layer wakes: checked \{checked}, period \{other_period}, pending \{pending}, work \{scene.parts.work() - work}, first \{a.damage}")
      assert_eq(pending, 2, msg="each layer owns only its earliest pending wake")
      assert_eq(scene.wakes.length(), 2, msg="each layer has its next wake after this one")
    }
  }
}

///|
test "a layer redrawn without its timer and a layer removed leave no wake behind" {
  let ticking = @signals.signal(true, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) { }, w=440.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(100.0))).height(Is(Some(50.0)))
        .words(Is("a")).glyphs_by(Is(Some(0.0)), fn(_, _) {
          let step = if ticking.get() { g().every(300.0) } else { 0 }
          { alpha: 1.0, dx: 0.0, dy: (step % 2).to_double() * 5.0, scale: 1.0, sx: 1.0 }
        }) |> ignore
    }) |> ignore
    root.show(fn() { shown.get() }, fn(slot) {
      slot.box(fn(n) {
        n.over(Is(true)).offset(Is((260.0, 20.0))).width(Is(Some(100.0))).height(Is(Some(50.0)))
          .words(Is("b")).glyphs_by(Is(Some(0.0)), fn(_, _) {
            { alpha: 1.0, dx: 0.0, dy: (g().every(450.0) % 2).to_double() * 5.0, scale: 1.0, sx: 1.0 }
          }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  t.record_host()
  let at = t.time()
  assert_eq(scene.wakes.length(), 2)
  ticking.set(false)
  t.frame_at(at + 20.0)
  assert_eq(scene.wakes.length(), 1, msg="a redraw replaces the previous timer with no timer")
  assert_eq(t.host_frames().length(), 1)
  let before = t.glyphs_shown().filter(fn(r) { r.0 >= 260.0 })
  assert_false(before.is_empty())
  shown.set(false)
  t.frame_at(at + 40.0)
  let removed = t.host_frames()[0]
  assert_true(before.iter().all(fn(r) { paint_damage_covers(removed, r) }), msg="removed layer's old reach: \{removed}")
  assert_eq(scene.wakes.length(), 0, msg="a removed layer owns no pending timer")
  // The host may still deliver a timer it was already asked for. Once that comes, neither layer may renew it.
  // run_as_host records real frame requests; a direct frame_at is always marked asked by the test.
  t.run_as_host(600.0)
  let after = t.host_frames()
  assert_false(after.is_empty())
  assert_true(after.iter().all(fn(f) { !f.changed }), msg="neither former timer changes the drawing: \{after}")
  let past = periods_at(at, 0.0, 450.0).1
  let later = after.filter(fn(f) { f.at > past })
  assert_false(later.is_empty())
  assert_true(later.iter().all(fn(f) { !f.asked }), msg="neither former timer is renewed: \{later}")
}
