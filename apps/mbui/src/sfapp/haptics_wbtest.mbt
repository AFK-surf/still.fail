// Haptics (sfbase feel.mbt, the prefs' `haptics`): 外观's 震动 turns them all off and on; something on screen coming to
// be is felt as it comes, not as it is first seen nor while it stays.

///|
test "震动 in 外观 turned off: the prefs' haptics off, nothing felt; on again, felt" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Appearance))
  t.draw()
  t.run_for(@ui.move_most_ms)
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
test "the bottom bar: holding and moving between places is felt once per choice, tapping a different place too" {
  for platform in [1, 2] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w=390.0, h=844.0, platform~)
    t.draw()
    let (xs, y) = bar_places_at()
    t.tap(xs[0], y)
    assert_eq(t.haptics(), [])
    t.press_at(xs[0], y)
    let before_hold = bar_hold_ms / 2.0
    t.run_for(before_hold)
    assert_eq(t.haptics(), [])
    t.run_for(bar_hold_ms - before_hold)
    t.frame()
    assert_eq(t.haptics(), [@ui.LongPress])
    t.move(xs[1], y)
    assert_eq(t.haptics(), [@ui.LongPress, @ui.TextHandleMove])
    t.move(xs[1] + 2.0, y)
    assert_eq(t.haptics(), [@ui.LongPress, @ui.TextHandleMove])
    t.release(xs[1], y)
    assert_true(app.nav.top() == Files)
    assert_eq(t.haptics(), [@ui.LongPress, @ui.TextHandleMove])
    t.tap(xs[0], y)
    assert_true(app.nav.top() == Home)
    assert_eq(t.haptics(), [@ui.LongPress, @ui.TextHandleMove, @ui.TextHandleMove])
  }
}

///|
test "the bottom bar: the 震动 setting turns holding and switching off and on" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=1)
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Appearance))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="震动")
  t.frame()
  t.frame()
  app.nav.pop() |> ignore
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  let (xs, y) = bar_places_at()
  let before = t.haptics().length()
  t.press_at(xs[0], y)
  t.run_for(bar_hold_ms)
  t.frame()
  t.move(xs[1], y)
  t.release(xs[1], y)
  assert_true(app.nav.top() == Files)
  assert_eq(t.haptics().length(), before)
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Appearance))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="震动")
  t.frame()
  t.frame()
  app.nav.pop() |> ignore
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  let before = t.haptics().length()
  t.tap(xs[0], y)
  assert_true(app.nav.top() == Home)
  assert_eq(t.haptics()[before:].to_array(), [@ui.TextHandleMove])
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
