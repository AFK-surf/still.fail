///|
test "modifier changes are followed between frames and cleared when the window loses focus" {
  let seen : Array[Int] = []
  let t = Tester::new(fn(_) { }, platform=0)
  set_view_app(fn(root) { root.reacts(mods_held, fn(now) { seen.push(now) }) })
  t.draw()
  seen.clear()
  t.hold_mods(mod_alt)
  t.hold_mods(mod_alt)
  t.hold_mods(mod_alt | mod_cmd)
  t.hold_mods(mod_cmd)
  t.app_state(true, false)
  assert_eq(seen, [mod_alt, mod_alt | mod_cmd, mod_cmd, 0])
  assert_eq(mods_held(), 0)
  t.app_state(true, true)
  assert_eq(mods_held(), 0)
}

///|
test "a modifier change redraws a stationary target without a pointer event" {
  let t = Tester::new(fn(_) { }, w=100.0, h=100.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(40.0))).height(Is(Some(40.0)))
      .ground(By(fn() { if (mods_held() & mod_alt) != 0 { 0xFF0000FFL } else { 0x00FF00FFL } })) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x00FF00FFL }))
  t.fake.wants = false
  t.hold_mods(mod_alt)
  assert_true(t.fake.wants, msg="the changed modifier owes a frame")
  t.frames_owed()
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0xFF0000FFL }))
  t.hold_mods(0)
  t.frames_owed()
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x00FF00FFL }))
}
