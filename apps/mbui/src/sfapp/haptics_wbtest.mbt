// Haptics (sfbase feel.mbt, the prefs' `haptics`): 外观's 震动 turns them all off and on; something on screen coming to
// be is felt as it comes, not as it is first seen nor while it stays.

///|
test "震动 in 外观 turned off: the prefs' haptics off, nothing felt; on again, felt" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Appearance))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t.click(Switch, label="震动")
  t.frame()
  t.frame()
  let set = named(calls, "prefs.set")
  assert_eq(text(Some(set[set.length() - 1].params), "haptics"), "off")
  let felt = t.haptics().length()
  @ui.haptic(LongPress)
  assert_eq(t.haptics().length(), felt)
  t.click(Switch, label="震动")
  t.frame()
  t.frame()
  let set = named(calls, "prefs.set")
  assert_true(field(Some(set[set.length() - 1].params), "haptics") is Some(Null))
  @ui.haptic(LongPress)
  assert_eq(t.haptics()[t.haptics().length() - 1], @ui.LongPress)
}

///|
test "what comes to be is felt as it comes: not as it is first seen, nor while it stays" {
  @sfbase.reset()
  let now = Ref(false)
  let first = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    @sfbase.felt_change(c, "needed", now.val, Confirm)
    @sfbase.felt_change(c, "there", first.val, Reject)
    c.text("x", wrap=false) |> ignore
  })
  t.draw()
  assert_eq(t.haptics(), [])
  now.val = true
  t.draw()
  assert_eq(t.haptics(), [@ui.Confirm])
  t.draw()
  assert_eq(t.haptics(), [@ui.Confirm])
  now.val = false
  t.draw()
  now.val = true
  t.draw()
  assert_eq(t.haptics(), [@ui.Confirm, @ui.Confirm])
}
