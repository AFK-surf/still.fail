// A new device showing this one's code (settings/lock_prompts.mbt; Security.kt LockPrompts): put up over the page open,
// whose and what it is, where it asks to be let in, the code; turned away (拒绝), or the panel closed by hand (the code
// still good: lockPrompt.hide), not put up again.

///|
test "a new device waiting on this one's code: its panel over the page, where it asks in, the code; 拒绝 turns it away" {
  let t = settings_tester("home", mode="settings-lock-prompt", shows="settings-lock-prompt", platform=2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="its sheet up over the page")
  assert_true(t.find("林的新设备请求批准") is Some(_))
  assert_true(t.find("Pixel 9") is Some(_))
  // where it asks to be let in, each workspace by name
  assert_true(t.find("申请访问") is Some(_))
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("个人") is Some(_))
  assert_true(t.find("安全码只显示在此设备上") is Some(_))
  // (the button: the last words with 拒绝 in them, the lead says it too)
  let (x, y) = t.find_last("拒绝").unwrap()
  t.tap(x, y)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // turned away: gone, and not put up again
  assert_false(@sf.presenting())
  assert_true(t.find("林的新设备请求批准") is None)
  assert_eq(@settings.fixture_pair_ended(), "deny")
}

///|
test "the panel closed by hand once the code is read: put away, not turned away (the code typed on the new device next)" {
  let t = settings_tester("home", mode="settings-lock-prompt", shows="settings-lock-prompt", platform=2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting())
  // a tap on the page beside it
  t.tap(195.0, 60.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_false(@sf.presenting())
  assert_true(t.find("林的新设备请求批准") is None)
  assert_eq(@settings.fixture_pair_ended(), "hide")
}

///|
test "no device waiting: no panel" {
  let t = settings_tester("home")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_false(@sf.presenting())
}
