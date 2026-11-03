// A device of the person's set up without the key to a vault of theirs, waiting on this one (settings/vault_prompts.mbt):
// put up over the page open, which device and which vault; 授权 gives it the key (vault.addDevice), 稍后 or the panel
// closed by hand puts it away (vault.hidePrompt), not put up again.

///|
test "a device waiting on this one for a vault's key: its panel over the page, which device and vault; 授权 gives it" {
  let t = settings_tester("home", mode="settings-vault-prompt", shows="settings-vault-prompt", platform=2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="its sheet up over the page")
  assert_true(t.find("Pixel 9 申请密钥库的钥匙") is Some(_))
  assert_true(t.find("星火工作室 · 林的库") is Some(_))
  // (the button: the last words with 授权 in them, the lead says it too)
  let (x, y) = t.find_last("授权").unwrap()
  t.tap(x, y)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // given: gone, and not put up again
  assert_false(@sf.presenting())
  assert_true(t.find("Pixel 9 申请密钥库的钥匙") is None)
  assert_eq(@settings.fixture_key_ask_ended(), "give")
}

///|
test "稍后: put away (shown again only once that device asks again)" {
  let t = settings_tester("home", mode="settings-vault-prompt", shows="settings-vault-prompt", platform=2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting())
  let (x, y) = t.find_last("稍后").unwrap()
  t.tap(x, y)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_false(@sf.presenting())
  assert_true(t.find("Pixel 9 申请密钥库的钥匙") is None)
  assert_eq(@settings.fixture_key_ask_ended(), "hide")
}

///|
test "the panel closed by hand: put away too" {
  let t = settings_tester("home", mode="settings-vault-prompt", shows="settings-vault-prompt", platform=2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting())
  // a tap on the page beside it
  t.tap(195.0, 60.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_false(@sf.presenting())
  assert_eq(@settings.fixture_key_ask_ended(), "hide")
}
