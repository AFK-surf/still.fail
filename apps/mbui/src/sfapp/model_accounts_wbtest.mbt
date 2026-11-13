// Choosing any subset of model accounts in the model panel's 账号 sub-panel: 全选 <-> 全不选 + 点一个,
// toggling multiple accounts, collapsing all checked accounts back to 全选, reverting incomplete 全不选 on close,
// and keeping multi-window quota lines on a single truncated line without wrapping.

///|
fn check_model_accounts(t : @ui.Tester, name : String, max_row_h : Double) -> Unit raise {
  assert_eq(t.corner_faults(), [], msg="\{name}: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name}: \{Repr(t.contrast_faults())}")
  assert_true(t.find("全选") is Some(_), msg=name)
  assert_true(t.find("重新分配") is Some(_), msg=name)
  assert_true(t.find("当前") is Some(_), msg=name)
  assert_true(t.find("仅此") is None, msg="\{name}: no 仅此 button")

  // Middle row with 3-window quota line stays on two single lines (never wraps to 3-4 lines).
  let backup_init = t.get(Button, label="Claude 备用订阅").rect
  assert_true(backup_init.3 <= max_row_h, msg="\{name}: middle row height \{backup_init.3} <= \{max_row_h}")

  // 1) 全选 -> 全不选 -> 点一个: tapping 全选 while all are checked clears all checkboxes into 全不选,
  // then tapping 团队 API key pins p2 immediately.
  let sel_all0 = t.all(Button, label="全选").last().unwrap().rect
  t.tap(sel_all0.0 + sel_all0.2 / 2.0, sel_all0.1 + sel_all0.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_none, true, msg="\{name}: 全不选 active")
  assert_true(t.find("请选择至少一个账号") is Some(_), msg="\{name}: 全不选 prompt")
  assert_true(t.find("重新分配") is None, msg="\{name}: 重新分配 hidden in 全不选")
  assert_eq(t.corner_faults(), [], msg="\{name} none: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name} none: \{Repr(t.contrast_faults())}")

  let api0 = t.get(Button, label="团队 API key").rect
  t.tap(api0.0 + api0.2 / 2.0, api0.1 + api0.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_none, false, msg="\{name}: 点一个 leaves 全不选")
  assert_eq(@sffixture.new_fix.d_profile, "p2", msg="\{name}: 点一个 pinned p2")
  assert_eq(t.corner_faults(), [], msg="\{name} pinned: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name} pinned: \{Repr(t.contrast_faults())}")

  // Restore 全选 by tapping 全选.
  let sel_all1 = t.all(Button, label="全选").last().unwrap().rect
  t.tap(sel_all1.0 + sel_all1.2 / 2.0, sel_all1.1 + sel_all1.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "", msg="\{name}: restored 全选")
  assert_eq(@sffixture.new_fix.d_none, false, msg="\{name}: 全选 not none")

  // 2) Unchecking one account from 全选 keeps the other two checked ("2 个账号").
  let api = t.get(Button, label="团队 API key").rect
  t.tap(api.0 + api.2 / 2.0, api.1 + api.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在已选账号间自动切换") is Some(_), msg="\{name}: subset note")
  assert_eq(t.corner_faults(), [], msg="\{name} subset: \{Repr(t.corner_faults())}")
  assert_eq(t.contrast_faults(), [], msg="\{name} subset: \{Repr(t.contrast_faults())}")

  // 3) Unchecking down to 0 accounts also enters 全不选, and tapping another account pins it; checking all collapses to 全选.
  let backup = t.get(Button, label="Claude 备用订阅").rect
  t.tap(backup.0 + backup.2 / 2.0, backup.1 + backup.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "p1", msg="\{name}: sole account p1")
  let main_acc = t.get(Button, label="Claude 订阅").rect
  t.tap(main_acc.0 + main_acc.2 / 2.0, main_acc.1 + main_acc.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_none, true, msg="\{name}: unchecking last enters 全不选")
  let main_acc2 = t.get(Button, label="Claude 订阅").rect
  t.tap(main_acc2.0 + main_acc2.2 / 2.0, main_acc2.1 + main_acc2.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_profile, "p1", msg="\{name}: re-checking p1 pins p1")

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
}

///|
test "model accounts: 全不选 + 点一个, subset toggling, single-line quota rows, and reverting incomplete 全不选 on close" {
  let wide = screen_in("chat-history-side", corner_windows[5], "zh")
  let ctrl = words_exactly_at(wide, "Opus 5.5").unwrap()
  wide.tap(ctrl.0 + ctrl.2 / 2.0, ctrl.1 + ctrl.3 / 2.0)
  wide.run_for(@ui.move_most_ms)
  let model_panel = wide.get(Dialog, label="模型").rect
  wide.click(Button, label="全选")
  wide.run_for(@ui.move_most_ms)
  let accounts_panel = wide.get(Dialog, label="账号").rect
  assert_eq(accounts_panel.0, model_panel.0, msg="wide: 账号 left matches 模型 left")
  assert_eq(accounts_panel.2, 340.0, msg="wide: 账号 keeps its own width")
  assert_eq(accounts_panel.1, model_panel.1 + model_panel.3 + @sf.panel_offset, msg="wide: 账号 stands panel_offset below 模型")
  check_model_accounts(wide, "wide", 56.0)

  // Entering 全不选 and dismissing the 账号 popover reverts the incomplete 0-account draft back to saved selection.
  let sel_all = wide.all(Button, label="全选").last().unwrap().rect
  wide.tap(sel_all.0 + sel_all.2 / 2.0, sel_all.1 + sel_all.3 / 2.0)
  wide.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_none, true, msg="wide: entered 全不选 before dismiss")
  wide.key(@ui.key_escape)
  wide.run_for(@ui.move_most_ms)
  assert_eq(@sffixture.new_fix.d_none, false, msg="wide: Escape from 账号 reverts 全不选")
  assert_true(wide.find("未选择") is None, msg="wide: chip reverted from 未选择")

  // Widening the parent model panel (全部模型 in newchat-providers-model) aligns 账号 left & gap while keeping its own width.
  let crowded = model_pop("newchat-providers-model")
  crowded.click(Button, label="全部模型")
  crowded.run_for(@ui.move_most_ms)
  let crowded_model = crowded.get(Dialog, label="模型").rect
  assert_true(crowded_model.2 > model_panel.2, msg="crowded 全部模型 panel is wider than narrow model panel")
  crowded.click(Button, label="全选")
  crowded.run_for(@ui.move_most_ms)
  let crowded_accounts = crowded.get(Dialog, label="账号").rect
  assert_eq(crowded_accounts.0, crowded_model.0, msg="crowded: 账号 left matches 模型 left")
  assert_eq(crowded_accounts.2, 340.0, msg="crowded: 账号 keeps its own width")
  let crowded_gap = if crowded_accounts.1 >= crowded_model.1 + crowded_model.3 {
    crowded_accounts.1 - (crowded_model.1 + crowded_model.3)
  } else {
    crowded_model.1 - (crowded_accounts.1 + crowded_accounts.3)
  }
  assert_eq(crowded_gap, @sf.panel_offset, msg="crowded: 账号 stands panel_offset from 模型")

  let phone = phone_agent_card()
  phone.click(Button, label="账号 林的 Max · 自动 5H 62% W 18%")
  phone.run_for(@ui.move_most_ms)
  phone.run_for(@ui.move_most_ms)
  check_model_accounts(phone, "phone", 66.0)
}
