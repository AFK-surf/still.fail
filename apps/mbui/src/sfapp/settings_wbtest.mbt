// The settings' pages (src/sfapp/settings) over the made-up ones (settings/fixture.mbt), as the app shows them.

///|
/// The app over the settings' fixture, a page of them open (by its name, @settings.route_of).
fn settings_tester(page : String, mode? : String = "settings") -> @ui.Tester {
  reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_setting(page)
  // the pages opened slide in from the frame that takes them
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "settings: the account, the workspace's rows and how each stands, this device's" {
  let t = settings_tester("home")
  assert_true(t.find("设置") is Some(_))
  assert_true(t.find("lin@example.com") is Some(_))
  // the workspace's heading: its name and the viewer's role
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("Workspace") is Some(_))
  // 3 members, an email added and an invitation out
  assert_true(t.find("3 人") is Some(_))
  assert_true(t.find("1/2 在线") is Some(_))
  assert_true(t.find("外观") is Some(_))
  // a tap on the account's card: the account
  t.tap_text("lin@example.com")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("lin@example.com · Google") is Some(_))
  assert_true(t.find("Chrome · macOS") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "appearance: 深色 chosen, the app is drawn dark at once and the core keeps it" {
  let t = settings_tester("appearance")
  assert_true(t.find("跟随系统") is Some(_))
  assert_false(@sf.theme().dark)
  t.tap_text("深色")
  assert_true(@sf.theme().dark)
  t.tap_text("浅色")
  assert_false(@sf.theme().dark)
  // (not idle yet: the choice's thumb is on a Ctx::spring (settings/parts.mbt), whose end the app cannot read)
}

///|
test "a station renamed from its page's …: the new name is the station's" {
  let t = settings_tester("stations")
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.find("MBA") is Some(_))
  t.tap_text("Studio")
  t.run_for(@ui.nav_push_ms)
  // its machine, large
  assert_true(t.find("内存剩") is Some(_))
  assert_true(t.find("在此 station 上") is Some(_))
  // "…" at the bar's end
  t.tap(357.0, 22.0)
  t.tap_text("重命名")
  assert_true(t.find("station 名称") is Some(_))
  for _ in 0..<6 {
    t.backspace()
  }
  t.type_text("工作室")
  t.tap_text("保存")
  assert_true(t.find("工作室") is Some(_))
  // (not idle yet: the sheet is still sinking on its spring (kit/sheet.mbt), till mbui#25 declares its end)
}

///|
test "a settings sheet goes down on the sheet's spring, only drawn: its 保存 tapped meanwhile renames nothing" {
  let t = settings_tester("stations")
  // the station as the tests before left it
  let name = if t.find("Studio") is Some(_) { "Studio" } else { "工作室" }
  t.tap_text(name)
  t.run_for(@ui.nav_push_ms)
  t.tap(357.0, 22.0)
  t.tap_text("重命名")
  for _ in 0..<name.length() {
    t.backspace()
  }
  t.type_text("没改成的名字")
  assert_true(t.find("保存") is Some(_))
  // the scrim, tapped: it goes down, drawn as it goes, the keyboard let go of
  t.tap_once(195.0, 60.0)
  t.frame()
  t.frame()
  let (sx, sy) = t.find("保存").unwrap()
  let (active, _, _, _) = t.ime()
  assert_true(!active)
  t.tap_once(sx, sy)
  // down at once (only drawn as it sinks), the station's name as it was
  assert_true(!@settings.sheet_up())
  assert_true(t.find(name) is Some(_))
  // (not idle yet: the sheet is still sinking on its spring (kit/sheet.mbt), till mbui#25 declares its end)
}

///|
test "the archive: its chats by day; one restored leaves it" {
  let t = settings_tester("archive")
  assert_true(t.find("已归档") is Some(_))
  assert_true(t.find("整理上个月的发票") is Some(_))
  assert_true(t.find("周会纪要") is Some(_))
  assert_true(t.find("昨天") is Some(_))
  // 还原 at the row's end (its first round button, before 删除)
  let (_, y) = t.find("整理上个月的发票").unwrap()
  t.tap(390.0 - 10.0 - 34.0 - 17.0, y)
  assert_true(t.find("整理上个月的发票") is None)
  assert_true(t.find("周会纪要") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "the workspace: its people, those added, the invitations out" {
  let t = settings_tester("workspace")
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("Ana") is Some(_))
  assert_true(t.find("zhou@example.com") is Some(_))
  assert_true(t.find("he@example.com") is Some(_))
  assert_true(t.find("qin@example.com") is Some(_))
  assert_true(t.find("撤回") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "security mode: a device waiting, confirmed in its sheet by its code" {
  let t = settings_tester("security")
  assert_true(t.find("安全") is Some(_))
  assert_true(t.find("482 917") is Some(_))
  t.tap_text("482 917")
  assert_true(t.find("一致，批准") is Some(_))
  assert_true(t.find("不一致，拒绝") is Some(_))
  // (not idle yet: the sheet is still rising on kit's spring (kit/sheet.mbt), whose end it does not say)
}

///|
test "memory: a station's global memory, its projects, a skill's page" {
  let t = settings_tester("memory:ws1/st1")
  assert_true(t.find("全局记忆") is Some(_))
  assert_true(t.find("发布流程") is Some(_))
  t.tap_text("发布流程")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("步骤") is Some(_))
  assert_true(t.find("checklist") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "usage: the totals, the days, 30 天 picked" {
  let t = settings_tester("usage")
  assert_true(t.find("$118") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  t.tap_text("30 天")
  assert_true(t.find("$486") is Some(_))
  // (not idle yet: a Ctx::spring still moves, till mbui#25 declares its end)
}

///|
test "profiles, connects, the vault: their lists" {
  let t = settings_tester("profiles")
  assert_true(t.find("Claude 主账号") is Some(_))
  assert_true(t.find("Claude 订阅") is Some(_))
  let t2 = settings_tester("connects")
  assert_true(t2.find("星火助手 · 星火") is Some(_))
  assert_true(t2.find("值班机器人") is Some(_))
  let t3 = settings_tester("vault")
  assert_true(t3.find("GitHub token") is Some(_))
  assert_true(t3.find("git push origin main") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t3.run_for(bar.rest() - t3.time())
  t3.assert_idle()
}
