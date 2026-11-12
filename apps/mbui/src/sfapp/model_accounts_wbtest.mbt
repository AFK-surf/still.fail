// Choosing any subset of model accounts in the model panel's 账号 sub-panel: 全选, toggling multiple accounts,
// collapsing all checked accounts back to 全选, locking the sole checked account from unchecking, and 仅此.

///|
fn check_model_accounts(t : @ui.Tester, name : String) -> Unit raise {
  assert_eq(t.corner_faults(), [], msg="\{name}: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name}: \{Repr(t.contrast_faults())}")
  assert_true(t.find("全选") is Some(_), msg=name)
  assert_true(t.find("重新分配") is Some(_), msg=name)
  assert_true(t.find("当前") is Some(_), msg=name)
  assert_true(t.find("仅此") is Some(_), msg=name)

  // Unchecking one account from 全选 keeps the other two checked ("2 个账号") and keeps the panel open.
  let api = t.get(Button, label="团队 API key").rect
  t.tap(api.0 + api.2 / 2.0, api.1 + api.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在已选账号间自动切换") is Some(_), msg="\{name}: subset note")
  assert_eq(t.corner_faults(), [], msg="\{name} subset: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name} subset: \{Repr(t.contrast_faults())}")

  // Unchecking a second account leaves Claude 订阅 as the sole checked account; tapping it cannot uncheck to zero.
  let backup = t.get(Button, label="Claude 备用订阅").rect
  t.tap(backup.0 + backup.2 / 2.0, backup.1 + backup.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "p1", msg="\{name}: sole account p1")
  assert_eq(@sffixture.new_fix.d_profiles.length(), 0, msg="\{name}: collapsed to single profile")
  let main_acc = t.get(Button, label="Claude 订阅").rect
  t.tap(main_acc.0 + main_acc.2 / 2.0, main_acc.1 + main_acc.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "p1", msg="\{name}: sole account stays checked")
  assert_eq(t.corner_faults(), [], msg="\{name} sole: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name} sole: \{Repr(t.contrast_faults())}")

  // Checking the remaining two accounts collapses all-checked back to 全选 (d_profile == "", d_profiles == []).
  let backup2 = t.get(Button, label="Claude 备用订阅").rect
  t.tap(backup2.0 + backup2.2 / 2.0, backup2.1 + backup2.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profiles, ["p1", "p3"], msg="\{name}: two checked")
  let api2 = t.get(Button, label="团队 API key").rect
  t.tap(api2.0 + api2.2 / 2.0, api2.1 + api2.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "", msg="\{name}: collapsed to 全选")
  assert_eq(@sffixture.new_fix.d_profiles.length(), 0, msg="\{name}: collapsed profiles empty")
  assert_true(t.find("由 station 选择：现在是 Claude 订阅") is Some(_), msg="\{name}: back to 全选 note")

  // Tapping 仅此 pins that single account immediately; tapping 全选 restores unrestricted selection.
  let only_buttons = t.all(Button, label="仅此")
  assert_eq(only_buttons.length(), 3, msg="\{name}: 3 仅此 buttons when 全选")
  let last_only = only_buttons[2].rect
  t.tap(last_only.0 + last_only.2 / 2.0, last_only.1 + last_only.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "p2", msg="\{name}: 仅此 pinned p2")
  assert_eq(t.all(Button, label="仅此").length(), 2, msg="\{name}: p2 hides its own 仅此")

  let sel_all = t.get(Button, label="全选").rect
  t.tap(sel_all.0 + sel_all.2 / 2.0, sel_all.1 + sel_all.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "", msg="\{name}: 全选 restores unrestricted")
}

///|
test "model accounts: 全选, toggling a subset, locking the last account, 仅此, and collapsing back to 全选" {
  let wide = screen_in("chat-history-side", corner_windows[5], "zh")
  let ctrl = words_exactly_at(wide, "Opus 5.5").unwrap()
  wide.tap(ctrl.0 + ctrl.2 / 2.0, ctrl.1 + ctrl.3 / 2.0)
  wide.run_for(@ui.move_most_ms)
  wide.click(Button, label="全选")
  wide.run_for(@ui.move_most_ms)
  check_model_accounts(wide, "wide")

  let phone = phone_agent_card()
  phone.click(Button, label="账号 林的 Max · 自动 5H 62% W 18%")
  phone.run_for(@ui.move_most_ms)
  phone.run_for(@ui.move_most_ms)
  check_model_accounts(phone, "phone")
}
