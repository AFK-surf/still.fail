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
